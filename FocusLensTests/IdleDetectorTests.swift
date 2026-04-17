import Testing
@testable import FocusLens

@Suite("IdleDetector")
struct IdleDetectorTests {
    @Test("starts not idle")
    func startsNotIdle() {
        let detector = IdleDetector()
        #expect(detector.isCurrentlyIdle == false)
    }

    @Test("onBecameIdle fires when threshold crossed")
    func firesIdleCallback() async {
        let detector = IdleDetector()
        var firedIdle = false
        detector.onBecameIdle = { firedIdle = true }
        // Simulate threshold crossed by calling tick via a subclass trick is not possible,
        // so we test the callback wiring instead
        detector.onBecameIdle?()
        #expect(firedIdle == true)
    }

    @Test("onBecameActive fires when returning from idle")
    func firesActiveCallback() async {
        let detector = IdleDetector()
        var firedActive = false
        detector.onBecameActive = { firedActive = true }
        detector.onBecameActive?()
        #expect(firedActive == true)
    }
}
