import AppKit
import Foundation

actor ActivityTracker {
    private(set) var isPaused: Bool = false
    private(set) var currentAppName: String = ""
    var onSessionEnded: (@Sendable () -> Void)?
    var onStateChanged: (@Sendable (String, Bool) -> Void)?

    private var currentSession: ActivitySession? = nil
    private var currentApp: NSRunningApplication? = nil
    private var notificationObservers: [NSObjectProtocol] = []
    private let store: ActivitySessionStore
    private let neverTrackStore: NeverTrackStore
    private let idleDetector: IdleDetector
    private let permissionManager: PermissionManager
    private var isStarted: Bool = false

    init(
        store: ActivitySessionStore = .init(),
        neverTrackStore: NeverTrackStore = .init(),
        idleDetector: IdleDetector = .init(),
        permissionManager: PermissionManager = .init()
    ) {
        self.store = store
        self.neverTrackStore = neverTrackStore
        self.idleDetector = idleDetector
        self.permissionManager = permissionManager
    }

    func setCallbacks(
        onSessionEnded: @escaping @Sendable () -> Void,
        onStateChanged: @escaping @Sendable (String, Bool) -> Void
    ) {
        self.onSessionEnded = onSessionEnded
        self.onStateChanged = onStateChanged
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        if !permissionManager.accessibilityGranted {
            permissionManager.requestAccessibility()
        }
        await recoverOpenSessions()
        registerNotifications()
        setupIdleDetectorCallbacks()
        idleDetector.start()
        let frontApp = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        await handleAppActivation(frontApp)
    }

    func pause() async {
        isPaused = true
        onStateChanged?(currentAppName, isPaused)
        await closeCurrentSession()
    }

    func resume() async {
        isPaused = false
        onStateChanged?(currentAppName, isPaused)
        let frontApp = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        await handleAppActivation(frontApp)
    }

    private func recoverOpenSessions() async {
        let now = Date()
        guard let openSessions = try? store.fetchOpenSessions() else { return }
        for session in openSessions {
            guard let id = session.id else { continue }
            let closeAt = min(now, session.startedAt.addingTimeInterval(AppConstants.maxReasonableSessionSeconds))
            let duration = closeAt.timeIntervalSince(session.startedAt)
            if duration < AppConstants.minimumSessionSeconds {
                try? store.delete(id: id)
            } else {
                try? store.close(id: id, at: closeAt)
            }
        }
    }

    private func registerNotifications() {
        let wsCenter = NSWorkspace.shared.notificationCenter

        let appObs = wsCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: nil
        ) { [weak self] note in
            guard let self else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { await self.handleAppActivation(app) }
        }

        let sleepObs = wsCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleSleep() }
        }

        let wakeObs = wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleWake() }
        }

        notificationObservers = [appObs, sleepObs, wakeObs]
    }

    private func setupIdleDetectorCallbacks() {
        idleDetector.onBecameIdle = { [weak self] in
            guard let self else { return }
            let app = NSWorkspace.shared.frontmostApplication  // captured on @MainActor
            Task {
                await self.closeCurrentSession()
                if let app { await self.openIdleSession(for: app) }
            }
        }
        idleDetector.onBecameActive = { [weak self] in
            guard let self else { return }
            let app = NSWorkspace.shared.frontmostApplication  // captured on @MainActor
            Task {
                await self.closeCurrentSession()
                if let app { await self.handleAppActivation(app) }
            }
        }
        idleDetector.onTick = { [weak self] in
            guard let self else { return }
            Task { await self.updateCurrentSessionTitle() }
        }
    }

    private func updateCurrentSessionTitle() async {
        guard let session = currentSession,
              let id = session.id,
              let app = currentApp,
              !session.isIdle else { return }
        guard let title = PermissionManager.windowTitle(for: app), !title.isEmpty else { return }
        try? store.updateWindowTitle(id: id, windowTitle: title)
    }

    private func openSession(for app: NSRunningApplication) async {
        guard let bundleId = app.bundleIdentifier else { return }
        guard (try? neverTrackStore.contains(bundleId: bundleId)) != true else { return }

        currentApp = app
        let windowTitle = PermissionManager.windowTitle(for: app)
        let name = app.localizedName ?? bundleId
        let session = ActivitySession(
            id: nil,
            appBundleId: bundleId,
            appName: name,
            windowTitle: windowTitle,
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            isIdle: false,
            categoryId: nil
        )
        currentSession = try? store.insert(session)
        currentAppName = name
        onStateChanged?(currentAppName, isPaused)
    }

    private func openIdleSession(for app: NSRunningApplication) async {
        guard let bundleId = app.bundleIdentifier else { return }
        guard (try? neverTrackStore.contains(bundleId: bundleId)) != true else { return }

        let name = app.localizedName ?? bundleId
        let session = ActivitySession(
            id: nil,
            appBundleId: bundleId,
            appName: name,
            windowTitle: nil,
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            isIdle: true,
            categoryId: nil
        )
        currentSession = try? store.insert(session)
        currentAppName = name
        onStateChanged?(currentAppName, isPaused)
    }

    private func closeCurrentSession() async {
        guard let session = currentSession, let id = session.id else { return }
        currentSession = nil
        let app = currentApp
        currentApp = nil
        let now = Date()
        let duration = now.timeIntervalSince(session.startedAt)
        let finalTitle = app.flatMap { PermissionManager.windowTitle(for: $0) }
        let isNoisy = finalTitle.map { t in
            let lower = t.lowercased()
            return AppConstants.noisyWindowTitlePrefixes.contains { lower.hasPrefix($0) }
        } ?? false
        if duration < AppConstants.minimumSessionSeconds || isNoisy {
            try? store.delete(id: id)
        } else {
            try? store.close(id: id, at: now, windowTitle: finalTitle)
        }
        onSessionEnded?()
    }

    private func handleAppActivation(_ app: NSRunningApplication?) async {
        guard !isPaused else { return }
        guard let app else { return }
        guard app.bundleIdentifier != currentSession?.appBundleId else { return }
        await closeCurrentSession()
        await openSession(for: app)
    }

    private func handleSleep() async {
        await closeCurrentSession()
    }

    private func handleWake() async {
        let frontApp = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        await handleAppActivation(frontApp)
    }
}
