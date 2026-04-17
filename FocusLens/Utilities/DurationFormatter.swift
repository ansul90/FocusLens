import Foundation

enum DurationFormatter {

    static func string(from seconds: Double) -> String {
        format(seconds: seconds)
    }

    static func shortString(from seconds: Double) -> String {
        format(seconds: seconds)
    }

    private static func format(seconds: Double) -> String {
        guard seconds >= 0 else { return "0m" }
        guard seconds >= 60 else { return "< 1m" }

        let totalMinutes = Int(seconds / 60)
        guard totalMinutes >= 60 else { return "\(totalMinutes)m" }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }
}
