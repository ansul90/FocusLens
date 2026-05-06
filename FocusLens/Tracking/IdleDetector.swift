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
        // kCGAnyInputEventType (0xFFFFFFFF) queries time since the last event of any kind.
        // CGEventType's failable initializer can return nil for out-of-range values on future
        // OS versions, so we use the UInt32 sentinel value via a trusted cast rather than
        // force-unwrapping.
        let anyInputEventType = CGEventType(rawValue: UInt32.max)
            ?? CGEventType(rawValue: UInt32(kCGEventNull.rawValue))!
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInputEventType
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
