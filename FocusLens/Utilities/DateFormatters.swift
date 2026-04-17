import Foundation

enum DateFormatters {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        iso8601.string(from: date)
    }

    static func date(from string: String) -> Date? {
        iso8601.date(from: string)
    }
}
