import SwiftUI
import Charts

// MARK: - TierColors

enum TierColors {
    static func color(for tier: Int) -> Color {
        switch tier {
        case 2:  return Color(hex: "4CAF50") ?? .green
        case 1:  return Color(hex: "8BC34A") ?? .green
        case -1: return Color(hex: "FF9800") ?? .orange
        case -2: return Color(hex: "F44336") ?? .red
        default: return Color(hex: "9E9E9E") ?? .gray
        }
    }

    static let ordered: [Int] = [2, 1, 0, -1, -2]

    static func label(for tier: Int) -> String {
        switch tier {
        case 2:  return "Very Productive"
        case 1:  return "Productive"
        case -1: return "Distracting"
        case -2: return "Very Distracting"
        default: return "Neutral"
        }
    }
}

// MARK: - ProductivityGaugeView

struct ProductivityGaugeView: View {
    let score: Int

    private static let arcFraction: Double = 0.75
    private static let lineWidth: CGFloat = 14
    private static let rotationDegrees: Double = 135
    private static let scoreFontSize: CGFloat = 28
    private static let gaugeSize: CGFloat = 120

    private var gaugeColor: Color {
        switch score {
        case 75...: return TierColors.color(for: 2)
        case 50..<75: return TierColors.color(for: -1)
        default: return TierColors.color(for: -2)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: Self.arcFraction)
                .stroke(
                    Color.gray.opacity(0.2),
                    style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(Self.rotationDegrees))

            Circle()
                .trim(from: 0, to: Self.arcFraction * Double(score) / 100.0)
                .stroke(
                    gaugeColor,
                    style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(Self.rotationDegrees))
                .animation(.easeOut(duration: 0.6), value: score)

            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: Self.scoreFontSize, weight: .bold, design: .rounded))
                Text("/ 100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.gaugeSize, height: Self.gaugeSize)
    }
}

// MARK: - ProductivityBreakdownBar

struct ProductivityBreakdownBar: View {
    let breakdown: [(tier: Int, seconds: Double)]

    private var sorted: [(tier: Int, seconds: Double)] {
        let tierOrder = TierColors.ordered
        return breakdown.sorted { a, b in
            let ai = tierOrder.firstIndex(of: a.tier) ?? tierOrder.count
            let bi = tierOrder.firstIndex(of: b.tier) ?? tierOrder.count
            return ai < bi
        }
    }

    private var total: Double {
        breakdown.reduce(0) { $0 + $1.seconds }
    }

    var body: some View {
        GeometryReader { geometry in
            if breakdown.isEmpty {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                HStack(spacing: 0) {
                    ForEach(sorted, id: \.tier) { entry in
                        Rectangle()
                            .fill(TierColors.color(for: entry.tier))
                            .frame(width: geometry.size.width * (entry.seconds / total))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(height: 12)
    }
}

// MARK: - CategoryBarRow

struct CategoryBarRow: View {
    let name: String
    let colorHex: String
    let seconds: Double
    let maxSeconds: Double

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: colorHex) ?? .gray)
                .frame(width: 10, height: 10)

            Text(name)
                .font(.callout)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geometry in
                let barWidth = maxSeconds > 0 ? geometry.size.width * (seconds / maxSeconds) : 0
                Rectangle()
                    .fill((Color(hex: colorHex) ?? .gray).opacity(0.7))
                    .frame(width: barWidth, height: 8)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .frame(maxHeight: .infinity, alignment: .center)
            }

            Text(DurationFormatter.string(from: seconds))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(alignment: .trailing)
        }
        .frame(height: 20)
    }
}

// MARK: - HourlyTierChart

struct HourlyTierChart: View {
    let hourlyTierBreakdown: [(hour: Int, tier: Int, seconds: Double)]

    private static let xAxisStride = stride(from: 0, through: 23, by: 4).map { $0 }

    var body: some View {
        if hourlyTierBreakdown.isEmpty {
            Text("No activity recorded yet")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(Array(hourlyTierBreakdown.enumerated()), id: \.offset) { item in
                BarMark(
                    x: .value("Hour", item.element.hour),
                    y: .value("Minutes", item.element.seconds / 60)
                )
                .foregroundStyle(TierColors.color(for: item.element.tier))
            }
            .chartXAxis {
                AxisMarks(values: Self.xAxisStride) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text("\(hour)")
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text("\(Int(minutes))m")
                        }
                    }
                    AxisGridLine()
                }
            }
        }
    }
}

// MARK: - HourlyColorMode + HourlyCategoryChart

enum HourlyColorMode: String, CaseIterable, Identifiable {
    case tier     = "Productivity"
    case category = "Category"
    var id: String { rawValue }
}

struct HourlyCategoryChart: View {
    let hourlyCategoryBreakdown: [(hour: Int, colorHex: String, seconds: Double)]

    private static let xAxisStride = stride(from: 0, through: 23, by: 4).map { $0 }

    var body: some View {
        if hourlyCategoryBreakdown.isEmpty {
            Text("No activity recorded yet")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(Array(hourlyCategoryBreakdown.enumerated()), id: \.offset) { item in
                BarMark(
                    x: .value("Hour", item.element.hour),
                    y: .value("Minutes", item.element.seconds / 60)
                )
                .foregroundStyle(Color(hex: item.element.colorHex) ?? .gray)
            }
            .chartXAxis {
                AxisMarks(values: Self.xAxisStride) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text("\(hour)")
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text("\(Int(minutes))m")
                        }
                    }
                    AxisGridLine()
                }
            }
        }
    }
}

// MARK: - WeekOverviewBars

struct WeekOverviewBars: View {
    let weekDailySeconds: [(date: Date, seconds: Double)]
    let selectedDate: Date

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    // All 7 days of the week containing selectedDate, filled with 0 for missing days.
    private var days: [(date: Date, seconds: Double)] {
        let cal = Calendar.current
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: selectedDate) else { return [] }
        let byDay = Dictionary(weekDailySeconds.map {
            (cal.startOfDay(for: $0.date), $0.seconds)
        }, uniquingKeysWith: { first, _ in first })

        var result: [(date: Date, seconds: Double)] = []
        var cursor = cal.startOfDay(for: weekInterval.start)
        let weekEnd = cal.startOfDay(for: weekInterval.end)
        while cursor < weekEnd {
            result.append((date: cursor, seconds: byDay[cursor] ?? 0))
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return result
    }

    // Average over days that have elapsed (don't count future days or days with no data).
    private var avgHours: Double {
        let now = Calendar.current.startOfDay(for: Date())
        let elapsed = days.filter { $0.date <= now && $0.seconds > 0 }
        guard !elapsed.isEmpty else { return 0 }
        return elapsed.reduce(0) { $0 + $1.seconds } / Double(elapsed.count) / 3600
    }

    var body: some View {
        Chart {
            ForEach(days, id: \.date) { entry in
                BarMark(
                    x: .value("Day", entry.date, unit: .day),
                    y: .value("Hours", entry.seconds / 3600)
                )
                .foregroundStyle(
                    Calendar.current.isDate(entry.date, inSameDayAs: selectedDate)
                        ? Color.accentColor
                        : Color.secondary.opacity(0.35)
                )
            }
            if avgHours > 0 {
                RuleMark(y: .value("Avg", avgHours))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(Self.dayFormatter.string(from: date))
                            .font(.caption2)
                            .foregroundStyle(
                                Calendar.current.isDate(date, inSameDayAs: selectedDate)
                                    ? Color.primary
                                    : Color.secondary
                            )
                    }
                }
            }
        }
        .chartYAxis(.hidden)
    }
}

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b)
    }
}
