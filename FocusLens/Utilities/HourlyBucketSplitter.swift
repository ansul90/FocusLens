import Foundation

struct RawSession: Sendable {
    let startedAt: Date
    let endedAt: Date
    let tier: Int
    let colorHex: String
}

enum HourlyBucketSplitter {

    static func splitByTier(
        _ sessions: [RawSession],
        dayBound: Date,
        calendar: Calendar = .current
    ) -> [(hour: Int, tier: Int, seconds: Double)] {
        var accumulator: [Int: [Int: Double]] = [:]
        for session in sessions {
            let clippedEnd = min(session.endedAt, dayBound)
            guard session.startedAt < clippedEnd else { continue }
            eachHourSlice(from: session.startedAt, to: clippedEnd, calendar: calendar) { hour, secs in
                accumulator[hour, default: [:]][session.tier, default: 0] += secs
            }
        }
        return accumulator.flatMap { hour, tierMap in
            tierMap.map { tier, secs in (hour: hour, tier: tier, seconds: secs) }
        }.sorted { $0.hour < $1.hour }
    }

    static func splitByCategory(
        _ sessions: [RawSession],
        dayBound: Date,
        calendar: Calendar = .current
    ) -> [(hour: Int, colorHex: String, seconds: Double)] {
        var accumulator: [Int: [String: Double]] = [:]
        for session in sessions {
            let clippedEnd = min(session.endedAt, dayBound)
            guard session.startedAt < clippedEnd else { continue }
            eachHourSlice(from: session.startedAt, to: clippedEnd, calendar: calendar) { hour, secs in
                accumulator[hour, default: [:]][session.colorHex, default: 0] += secs
            }
        }
        return accumulator.flatMap { hour, colorMap in
            colorMap.map { colorHex, secs in (hour: hour, colorHex: colorHex, seconds: secs) }
        }.sorted { $0.hour < $1.hour }
    }

    private static func eachHourSlice(
        from start: Date,
        to end: Date,
        calendar: Calendar,
        yield: (Int, Double) -> Void
    ) {
        var cursor = start
        while cursor < end {
            let hour = calendar.component(.hour, from: cursor)
            let hourStart = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: cursor)!
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: hourStart)!
            let sliceEnd = min(nextHour, end)
            let secs = sliceEnd.timeIntervalSince(cursor)
            if secs > 0 {
                yield(hour, secs)
            }
            cursor = sliceEnd
        }
    }
}
