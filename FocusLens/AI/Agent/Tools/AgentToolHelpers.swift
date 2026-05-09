import Foundation

// MARK: - Shared date helpers

let isoDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

struct DateRange { let start: String; let end: String }

func resolveDate(_ raw: String) -> Date {
    let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
    let cal = Calendar.current
    let now = Date()
    switch lower {
    case "today": return now
    case "yesterday": return cal.date(byAdding: .day, value: -1, to: now)!
    default: return isoDateFormatter.date(from: raw) ?? now
    }
}

func buildDateRange(_ raw: String) -> DateRange {
    let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
    let cal = Calendar.current
    let now = Date()

    switch lower {
    case "this_week":
        let startOfWeek = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let start = cal.date(from: startOfWeek)!
        let end = cal.date(byAdding: .day, value: 7, to: start)!
        let (s, _) = DateUtils.dayBoundsISO(for: start)
        let (_, e) = DateUtils.dayBoundsISO(for: cal.date(byAdding: .day, value: -1, to: end)!)
        return DateRange(start: s, end: e)
    case "last_week":
        let startOfThisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let startOfLastWeek = cal.date(byAdding: .day, value: -7, to: startOfThisWeek)!
        let (s, _) = DateUtils.dayBoundsISO(for: startOfLastWeek)
        let (_, e) = DateUtils.dayBoundsISO(for: cal.date(byAdding: .day, value: 6, to: startOfLastWeek)!)
        return DateRange(start: s, end: e)
    default:
        let date = resolveDate(raw)
        let (s, e) = DateUtils.dayBoundsISO(for: date)
        return DateRange(start: s, end: e)
    }
}

extension Double {
    func rounded(digits: Int) -> Double {
        let multiplier = pow(10.0, Double(digits))
        return (self * multiplier).rounded() / multiplier
    }
}
