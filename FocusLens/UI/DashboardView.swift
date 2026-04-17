import SwiftUI

struct DashboardView: View {
    @Environment(TodayAggregate.self) private var aggregate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerRow
                if !aggregate.categoryBreakdown.isEmpty {
                    categorySection
                }
                hourlySection
                appRankingsSection
            }
            .padding(24)
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Header: productivity score + total time

    private var headerRow: some View {
        HStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Productivity Score")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(aggregate.productivityScore)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
                Text("out of 100")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Divider().frame(height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text("Active Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DurationFormatter.string(from: aggregate.totalActiveSeconds))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
            }
            Spacer()
        }
    }

    private var scoreColor: Color {
        switch aggregate.productivityScore {
        case 75...: return .green
        case 50..<75: return .orange
        default: return .red
        }
    }

    // MARK: - Category breakdown

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Category")
                .font(.headline)
            HStack(alignment: .top, spacing: 24) {
                CategoryDonutChart(breakdown: aggregate.categoryBreakdown)
                    .frame(width: 180, height: 180)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(aggregate.categoryBreakdown, id: \.category.name) { entry in
                        HStack {
                            Circle()
                                .fill(Color(hex: entry.category.colorHex) ?? .gray)
                                .frame(width: 10, height: 10)
                            Text(entry.category.name)
                                .font(.callout)
                            Spacer()
                            Text(DurationFormatter.string(from: entry.totalSeconds))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Hourly timeline

    private var hourlySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Timeline")
                .font(.headline)
            if aggregate.hourlyBreakdown.isEmpty {
                Text("No activity recorded yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HourlyTimelineChart(hourlyBreakdown: aggregate.hourlyBreakdown)
                    .frame(height: 120)
            }
        }
    }

    // MARK: - App rankings

    private var appRankingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Apps")
                .font(.headline)
            if aggregate.topApps.isEmpty {
                Text("No activity recorded yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(aggregate.topApps.indices, id: \.self) { i in
                    let app = aggregate.topApps[i]
                    HStack {
                        Text("\(i + 1).")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(app.appName)
                        Spacer()
                        Text(DurationFormatter.string(from: app.totalSeconds))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    if i < aggregate.topApps.count - 1 { Divider() }
                }
            }
        }
    }
}
