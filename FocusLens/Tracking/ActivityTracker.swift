import AppKit
import Foundation
import os

@MainActor
final class ActivityTracker {
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
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "ActivityTracker")

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
        await handleAppActivation(NSWorkspace.shared.frontmostApplication)
    }

    func pause() async {
        isPaused = true
        onStateChanged?(currentAppName, isPaused)
        await closeCurrentSession()
    }

    func resume() async {
        isPaused = false
        onStateChanged?(currentAppName, isPaused)
        await handleAppActivation(NSWorkspace.shared.frontmostApplication)
    }

    private func recoverOpenSessions() async {
        let now = Date()
        let openSessions: [ActivitySession]
        do {
            openSessions = try store.fetchOpenSessions()
        } catch {
            logger.error("ActivityTracker: failed to fetch open sessions for recovery: \(error)")
            return
        }
        for session in openSessions {
            guard let id = session.id else { continue }
            let closeAt = min(now, session.startedAt.addingTimeInterval(AppConstants.maxReasonableSessionSeconds))
            let duration = closeAt.timeIntervalSince(session.startedAt)
            if duration < AppConstants.minimumSessionSeconds {
                do {
                    try store.delete(id: id)
                } catch {
                    logger.error("ActivityTracker: failed to delete short recovered session \(id): \(error)")
                }
            } else {
                do {
                    try store.close(id: id, at: closeAt)
                } catch {
                    logger.error("ActivityTracker: failed to close recovered session \(id): \(error)")
                }
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
        do {
            try store.updateWindowTitle(id: id, windowTitle: title)
        } catch {
            logger.error("ActivityTracker: failed to update window title for session \(id): \(error)")
        }
    }

    private func openSession(for app: NSRunningApplication) async {
        guard let bundleId = app.bundleIdentifier else { return }
        do {
            if try neverTrackStore.contains(bundleId: bundleId) { return }
        } catch {
            logger.error("ActivityTracker: failed to check never-track list for \(bundleId): \(error)")
        }

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
        do {
            currentSession = try store.insert(session)
        } catch {
            logger.error("ActivityTracker: failed to insert session for \(name): \(error)")
        }
        currentAppName = name
        onStateChanged?(currentAppName, isPaused)
    }

    private func openIdleSession(for app: NSRunningApplication) async {
        guard let bundleId = app.bundleIdentifier else { return }
        do {
            if try neverTrackStore.contains(bundleId: bundleId) { return }
        } catch {
            logger.error("ActivityTracker: failed to check never-track list for \(bundleId) (idle): \(error)")
        }

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
        do {
            currentSession = try store.insert(session)
        } catch {
            logger.error("ActivityTracker: failed to insert idle session for \(name): \(error)")
        }
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
        let isNeverTrackedTitle: Bool
        if let t = finalTitle {
            do {
                isNeverTrackedTitle = try neverTrackStore.containsTitle(bundleId: session.appBundleId, title: t)
            } catch {
                logger.error("ActivityTracker: failed to check never-track title for \(session.appBundleId): \(error)")
                isNeverTrackedTitle = false
            }
        } else {
            isNeverTrackedTitle = false
        }
        if duration < AppConstants.minimumSessionSeconds || isNoisy || isNeverTrackedTitle {
            do {
                try store.delete(id: id)
            } catch {
                logger.error("ActivityTracker: failed to delete short/noisy session \(id): \(error)")
            }
        } else {
            do {
                try store.close(id: id, at: now, windowTitle: finalTitle)
            } catch {
                logger.error("ActivityTracker: failed to close session \(id): \(error)")
            }
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
        await handleAppActivation(NSWorkspace.shared.frontmostApplication)
    }
}
