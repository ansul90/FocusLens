import Foundation

enum DateUtils {
    // DateFormatter is not thread-safe, so each call gets its own instance.
    private static func isoFormatter() -> DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        fmt.timeZone = TimeZone(identifier: "UTC")!
        return fmt
    }

    static func dayBoundsISO(for date: Date) -> (start: String, end: String) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let fmt = isoFormatter()
        return (fmt.string(from: start), fmt.string(from: end))
    }

    static func rangeBoundsISO(start: Date, end: Date) -> (start: String, end: String) {
        let fmt = isoFormatter()
        return (fmt.string(from: start), fmt.string(from: end))
    }
}
