import SwiftUI
import Charts

// MARK: - DailyCategoryChart

struct DailyCategoryChart: View {
    let dailyCategoryBreakdown: [(date: Date, colorHex: String, seconds: Double)]
    let range: DateInterval
    let kind: ActivityScope

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var effectiveEnd: Date {
        min(range.end, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!))
    }

    private var days: [Date] {
        let cal = Calendar.current
        var result: [Date] = []
        var cursor = cal.startOfDay(for: range.start)
        let end = cal.startOfDay(for: effectiveEnd)
        while cursor < end {
            result.append(cursor)
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return result
    }

    // Top 5 colorHex values by total seconds across the range; rest become neutral gray.
    private var top5Colors: Set<String> {
        var totals: [String: Double] = [:]
        for entry in dailyCategoryBreakdown {
            totals[entry.colorHex, default: 0] += entry.seconds
        }
        let sorted = totals.sorted { $0.value > $1.value }
        return Set(sorted.prefix(5).map(\.key))
    }

    private var chartData: [(date: Date, colorHex: String, seconds: Double)] {
        let cal = Calendar.current
        let top = top5Colors
        var byDayColor: [Date: [String: Double]] = [:]
        for entry in dailyCategoryBreakdown {
            let day = cal.startOfDay(for: entry.date)
            let key = top.contains(entry.colorHex) ? entry.colorHex : "9E9E9E"
            byDayColor[day, default: [:]][key, default: 0] += entry.seconds
        }
        var result: [(date: Date, colorHex: String, seconds: Double)] = []
        for day in days {
            for (colorHex, seconds) in (byDayColor[day] ?? [:]) where seconds > 0 {
                result.append((date: day, colorHex: colorHex, seconds: seconds))
            }
        }
        return result
    }

    var body: some View {
        if dailyCategoryBreakdown.isEmpty {
            Text("No activity recorded")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(Array(chartData.enumerated()), id: \.offset) { item in
                BarMark(
                    x: .value("Day", item.element.date, unit: .day),
                    y: .value("Hours", item.element.seconds / 3600)
                )
                .foregroundStyle(Color(hex: item.element.colorHex) ?? .gray)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text(kind == .week
                                 ? Self.dayFormatter.string(from: date)
                                 : Self.dateFormatter.string(from: date))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let h = value.as(Double.self) {
                            Text("\(Int(h))h")
                        }
                    }
                    AxisGridLine()
                }
            }
        }
    }
}

// MARK: - DailyTierChart

struct DailyTierChart: View {
    let dailyTierBreakdown: [(date: Date, tier: Int, seconds: Double)]
    let range: DateInterval
    let kind: ActivityScope

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    // Cap the chart domain to today so partial periods don't show empty future bars.
    private var effectiveEnd: Date {
        min(range.end, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!))
    }

    // All days in the visible range as (date, label) pairs.
    private var days: [(date: Date, label: String)] {
        let cal = Calendar.current
        var result: [(date: Date, label: String)] = []
        var cursor = cal.startOfDay(for: range.start)
        let end = cal.startOfDay(for: effectiveEnd)
        while cursor < end {
            let label = kind == .week
                ? Self.dayFormatter.string(from: cursor)
                : Self.dateFormatter.string(from: cursor)
            result.append((date: cursor, label: label))
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return result
    }

    // Flattened data for the Chart, ensuring every (day, tier) pair appears.
    private var chartData: [(date: Date, tier: Int, hours: Double)] {
        let cal = Calendar.current
        var byDayTier: [Date: [Int: Double]] = [:]
        for entry in dailyTierBreakdown {
            let day = cal.startOfDay(for: entry.date)
            byDayTier[day, default: [:]][entry.tier, default: 0] += entry.seconds
        }
        var result: [(date: Date, tier: Int, hours: Double)] = []
        for day in days.map(\.date) {
            for tier in TierColors.ordered {
                let seconds = byDayTier[day]?[tier] ?? 0
                result.append((date: day, tier: tier, hours: seconds / 3600))
            }
        }
        return result
    }

    var body: some View {
        if dailyTierBreakdown.isEmpty {
            Text("No activity recorded")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(Array(chartData.enumerated()), id: \.offset) { item in
                BarMark(
                    x: .value("Day", item.element.date, unit: .day),
                    y: .value("Hours", item.element.hours)
                )
                .foregroundStyle(TierColors.color(for: item.element.tier))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text(kind == .week
                                 ? Self.dayFormatter.string(from: date)
                                 : Self.dateFormatter.string(from: date))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let h = value.as(Double.self) {
                            Text("\(Int(h))h")
                        }
                    }
                    AxisGridLine()
                }
            }
        }
    }
}
