import Testing
@testable import FocusLens

@Suite("ActivityTracker")
@MainActor
struct ActivityTrackerTests {
    @Test("isPaused starts false")
    func startsUnpaused() async {
        let tracker = ActivityTracker()
        #expect(await tracker.isPaused == false)
    }

    @Test("pause sets isPaused true")
    func pauseSetsFlag() async {
        let tracker = ActivityTracker()
        await tracker.pause()
        #expect(await tracker.isPaused == true)
    }

    @Test("resume clears isPaused")
    func resumeClearsFlag() async {
        let tracker = ActivityTracker()
        await tracker.pause()
        await tracker.resume()
        #expect(await tracker.isPaused == false)
    }
}
