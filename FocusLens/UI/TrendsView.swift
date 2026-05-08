import SwiftUI

struct TrendsView: View {
    @Environment(RangeAggregate.self) private var aggregate

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private var periodLabel: String {
        switch aggregate.kind {
        case .week:
            let start = Self.shortDateFormatter.string(from: aggregate.range.start)
            // range.end is the start of next week — show the last day instead
            let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: aggregate.range.end)!
            let end = Self.shortDateFormatter.string(from: lastDay)
            return "\(start) – \(end)"
        case .month:
            return Self.monthYearFormatter.string(from: aggregate.range.start)
        }
    }

    private var comparisonLabel: String {
        switch aggregate.kind {
        case .week: return "vs last week"
        case .month: return "vs last month"
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                periodHeader
                    .padding(.bottom, 16)

                heroRow
                    .padding(.bottom, 16)

                Divider()

                chartSection
                    .padding(.vertical, 16)

                Divider()

                bottomRow
                    .padding(.top, 16)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Period Header

    private var periodHeader: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { aggregate.kind },
                set: { kind in Task { await aggregate.selectKind(kind) } }
            )) {
                ForEach(RangeKind.allCases) { k in
                    Text(k.rawValue).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 130)

            Spacer().frame(width: 8)

            Button {
                Task { await aggregate.previousPeriod() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Text(periodLabel)
                .font(.callout)
                .monospacedDigit()
                .frame(minWidth: 140, alignment: .center)

            Button {
                Task { await aggregate.nextPeriod() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(aggregate.isCurrentPeriod)

            Spacer()

            if !aggregate.isCurrentPeriod {
                Button(aggregate.kind == .week ? "This week" : "This month") {
                    Task { await aggregate.jumpToCurrent() }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(aggregate.kind == .week ? "This week" : "This month")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Hero Row

    private var heroRow: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Time logged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DurationFormatter.string(from: aggregate.totalActiveSeconds))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                RangeDeltaCaption(
                    delta: aggregate.activeSecondsDelta,
                    unit: .seconds,
                    hasComparison: aggregate.previousHasData,
                    comparisonLabel: comparisonLabel
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .center, spacing: 6) {
                ProductivityGaugeView(score: aggregate.productivityScore)
                    .frame(width: 110, height: 110)
                RangeDeltaCaption(
                    delta: Double(aggregate.productivityScoreDelta),
                    unit: .points,
                    hasComparison: aggregate.previousHasData,
                    comparisonLabel: comparisonLabel
                )
            }
            .frame(width: 160)
        }
    }

    // MARK: - Chart Section

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DAILY ACTIVITY")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if aggregate.isCurrentPeriod {
                    Text("· in progress")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            DailyTierChart(
                dailyTierBreakdown: aggregate.dailyTierBreakdown,
                range: aggregate.range,
                kind: aggregate.kind
            )
            .frame(height: 120)

            ProductivityBreakdownBar(breakdown: aggregate.productivityTierBreakdown)
                .frame(height: 8)
                .padding(.top, 4)

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

        return HStack(spacing: 12) {
            ForEach(activeTiers, id: \.self) { tier in
                HStack(spacing: 4) {
                    Circle()
                        .fill(TierColors.color(for: tier))
                        .frame(width: 6, height: 6)
                    Text(TierColors.label(for: tier))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack(alignment: .top, spacing: 0) {
            categoriesColumn
            Divider().padding(.horizontal, 12)
            topAppsColumn
            Divider().padding(.horizontal, 12)
            topInterruptorsColumn
        }
    }

    private var categoriesColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CATEGORIES")
                .font(.caption)
                .foregroundStyle(.secondary)

            if aggregate.categoryBreakdown.isEmpty {
                Text("No data yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(aggregate.categoryBreakdown.prefix(6), id: \.category.name) { entry in
                    CategoryPercentRow(
                        name: entry.category.name,
                        colorHex: entry.category.colorHex,
                        seconds: entry.totalSeconds,
                        totalSeconds: aggregate.totalActiveSeconds
                    )
                }
            }
        }
        .frame(width: 260, alignment: .leading)
    }

    private var topAppsColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOP APPS")
                .font(.caption)
                .foregroundStyle(.secondary)

            if aggregate.topApps.isEmpty {
                Text("No data yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(aggregate.topApps, id: \.appName) { app in
                    AppListRow(
                        appName: app.appName,
                        seconds: app.totalSeconds,
                        totalSeconds: aggregate.totalActiveSeconds
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topInterruptorsColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOP INTERRUPTORS")
                .font(.caption)
                .foregroundStyle(.secondary)

            if aggregate.topInterruptors.isEmpty {
                Text("No distractions logged")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(aggregate.topInterruptors, id: \.appName) { app in
                    AppListRow(
                        appName: app.appName,
                        seconds: app.totalSeconds,
                        totalSeconds: aggregate.totalActiveSeconds,
                        tierTint: TierColors.color(for: app.tier)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - RangeDeltaCaption

private struct RangeDeltaCaption: View {
    let delta: Double
    let unit: DeltaUnit
    let hasComparison: Bool
    let comparisonLabel: String

    private var isPositive: Bool { delta >= 0 }
    private var arrow: String { isPositive ? "↑" : "↓" }
    private var color: Color { isPositive ? TierColors.color(for: 1) : TierColors.color(for: -1) }

    private var formattedDelta: String {
        switch unit {
        case .seconds: return DurationFormatter.string(from: abs(delta))
        case .points: return "\(Int(abs(delta)))pts"
        }
    }

    var body: some View {
        if !hasComparison {
            Text("No previous \(comparisonLabel.replacingOccurrences(of: "vs ", with: "")) data")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else if delta == 0 {
            Text("Same as \(comparisonLabel.replacingOccurrences(of: "vs ", with: ""))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("\(arrow) \(formattedDelta) \(comparisonLabel)")
                .font(.caption2)
                .foregroundStyle(color)
        }
    }
}
