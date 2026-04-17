import SwiftUI
import Charts

// MARK: - Category Donut Chart

struct CategoryDonutChart: View {
    let breakdown: [(category: Category, totalSeconds: Double)]

    var body: some View {
        Chart(breakdown, id: \.category.name) { entry in
            SectorMark(
                angle: .value("Time", entry.totalSeconds),
                innerRadius: .ratio(0.55),
                angularInset: 1.5
            )
            .foregroundStyle(Color(hex: entry.category.colorHex) ?? .gray)
            .annotation(position: .overlay) { }
        }
    }
}

// MARK: - Hourly Timeline Bar Chart

struct HourlyTimelineChart: View {
    let hourlyBreakdown: [(hour: Int, seconds: Double)]

    var body: some View {
        Chart(hourlyBreakdown, id: \.hour) { entry in
            BarMark(
                x: .value("Hour", "\(entry.hour):00"),
                y: .value("Minutes", entry.seconds / 60)
            )
            .foregroundStyle(.blue.opacity(0.7))
        }
        .chartXAxis {
            AxisMarks(values: stride(from: 0, through: 23, by: 4).map { "\($0):00" }) { value in
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel("\(value.as(Double.self).map { Int($0) } ?? 0)m")
            }
        }
    }
}

// MARK: - Color(hex:) extension

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
