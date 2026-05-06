import Cocoa
import CoreGraphics

@MainActor
final class IdleDetector {
    var onBecameIdle: (() -> Void)?
    var onBecameActive: (() -> Void)?
    var onTick: (() -> Void)?
    private(set) var isCurrentlyIdle = false
    private var timer: Timer?

    // nonisolated: init only sets nil/false defaults; no main-actor resources allocated.
    nonisolated init() {}

    func start() {
        let t = Timer(timeInterval: AppConstants.idlePollIntervalSeconds, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
        // Fallback uses rawValue 0 (kCGEventNull), which is always a valid CGEventType.
        let anyInputEventType = CGEventType(rawValue: UInt32.max)
            ?? CGEventType(rawValue: 0)!
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
        if !nowIdle { onTick?() }
    }
}
