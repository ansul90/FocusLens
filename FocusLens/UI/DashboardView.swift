import SwiftUI

struct DashboardView: View {
    @Environment(TodayAggregate.self) private var aggregate

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateHeader
            topSection
            Divider()
            middleSection
            Divider()
            bottomSection
        }
        .padding(20)
        .frame(width: 680, height: 500)
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        Text(formattedDate)
            .font(.title3).bold()
            .padding(.bottom, 12)
    }

    // MARK: - Top Section: Gauge + Summary

    private var topSection: some View {
        HStack(spacing: 20) {
            ProductivityGaugeView(score: aggregate.productivityScore)
                .frame(width: 120, height: 120)

            summaryColumn
        }
        .padding(.vertical, 16)
    }

    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(DurationFormatter.string(from: aggregate.totalActiveSeconds))
                    .font(.title2).bold()
                Text("tracked today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProductivityBreakdownBar(breakdown: aggregate.productivityTierBreakdown)
                .frame(height: 12)

            tierLegend
        }
    }

    private var tierLegend: some View {
        let tierSeconds: [Int: Double] = Dictionary(
            aggregate.productivityTierBreakdown.map { ($0.tier, $0.seconds) },
            uniquingKeysWith: { first, _ in first }
        )
        let activeTiers = TierColors.ordered.filter { tier in
            (tierSeconds[tier] ?? 0) > 0
        }

        return VStack(alignment: .leading, spacing: 2) {
            ForEach(activeTiers, id: \.self) { tier in
                HStack(spacing: 4) {
                    Circle()
                        .fill(TierColors.color(for: tier))
                        .frame(width: 8, height: 8)
                    Text(TierColors.label(for: tier))
                        .font(.caption2)
                    Spacer()
                    Text(DurationFormatter.string(from: tierSeconds[tier] ?? 0))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Middle Section: Categories + Top Apps

    private var middleSection: some View {
        HStack(alignment: .top, spacing: 0) {
            categoriesColumn
            Divider().padding(.horizontal, 12)
            appsColumn
        }
        .padding(.vertical, 16)
    }

    private var categoriesColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CATEGORIES")
                .font(.caption)
                .foregroundStyle(.secondary)

            if aggregate.categoryBreakdown.isEmpty {
                Text("No data yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                let maxCatSeconds = aggregate.categoryBreakdown.first?.totalSeconds ?? 1
                ForEach(aggregate.categoryBreakdown.prefix(6), id: \.category.name) { entry in
                    CategoryBarRow(
                        name: entry.category.name,
                        colorHex: entry.category.colorHex,
                        seconds: entry.totalSeconds,
                        maxSeconds: maxCatSeconds
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOP APPS")
                .font(.caption)
                .foregroundStyle(.secondary)

            if aggregate.topApps.isEmpty {
                Text("No data yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(aggregate.topApps.prefix(6), id: \.appName) { app in
                    HStack {
                        Text(app.appName)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text(DurationFormatter.string(from: app.totalSeconds))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bottom Section: Timeline

    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TIMELINE")
                .font(.caption)
                .foregroundStyle(.secondary)
            HourlyTierChart(hourlyTierBreakdown: aggregate.hourlyTierBreakdown)
                .frame(height: 100)
        }
        .padding(.vertical, 16)
    }
}
