import Cocoa
import CoreGraphics

final class IdleDetector {
    var onBecameIdle: (() -> Void)?
    var onBecameActive: (() -> Void)?
    private(set) var isCurrentlyIdle = false
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(
            withTimeInterval: AppConstants.idlePollIntervalSeconds,
            repeats: true
        ) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
        let nowIdle = idleSeconds >= AppConstants.idleThresholdSeconds
        if nowIdle && !isCurrentlyIdle {
            isCurrentlyIdle = true
            onBecameIdle?()
        } else if !nowIdle && isCurrentlyIdle {
            isCurrentlyIdle = false
            onBecameActive?()
        }
    }
}
