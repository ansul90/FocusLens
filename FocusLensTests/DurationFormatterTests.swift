import Testing
@testable import FocusLens

@Suite("DurationFormatter")
struct DurationFormatterTests {

    @Test("negative seconds returns 0m")
    func negativeSeconds() {
        #expect(DurationFormatter.string(from: -1.0) == "0m")
    }

    @Test("zero seconds returns < 1m")
    func zeroSeconds() {
        #expect(DurationFormatter.string(from: 0.0) == "< 1m")
    }

    @Test("59.9 seconds returns < 1m")
    func underOneMinute() {
        #expect(DurationFormatter.string(from: 59.9) == "< 1m")
    }

    @Test("60 seconds returns 1m")
    func exactlyOneMinute() {
        #expect(DurationFormatter.string(from: 60.0) == "1m")
    }

    @Test("90 seconds rounds down to 1m")
    func ninetySeconds() {
        #expect(DurationFormatter.string(from: 90.0) == "1m")
    }

    @Test("2700 seconds (45 min) returns 45m")
    func fortyFiveMinutes() {
        #expect(DurationFormatter.string(from: 2700.0) == "45m")
    }

    @Test("3600 seconds (1h) returns 1h")
    func exactlyOneHour() {
        #expect(DurationFormatter.string(from: 3600.0) == "1h")
    }

    @Test("5580 seconds (1h 33m) returns 1h 33m")
    func oneHourThirtyThreeMinutes() {
        #expect(DurationFormatter.string(from: 5580.0) == "1h 33m")
    }

    @Test("7200 seconds (2h) returns 2h")
    func twoHours() {
        #expect(DurationFormatter.string(from: 7200.0) == "2h")
    }
}
