import SwiftUI

struct DashboardView: View {
    @Environment(TodayAggregate.self) private var aggregate
    @Environment(AskViewModel.self) private var askViewModel

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let minimumBarSeconds: Double = 1.0

    @State private var selectedTab: DashboardTab = .stats

    private enum DashboardTab: String, CaseIterable {
        case stats = "Stats"
        case ask = "Ask FocusLens"

        var icon: String {
            switch self {
            case .stats: return "chart.bar.fill"
            case .ask: return "bubble.left.and.bubble.right.fill"
            }
        }
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(aggregate.selectedDate)
    }

    private var formattedDate: String {
        Self.dateFormatter.string(from: aggregate.selectedDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()

            switch selectedTab {
            case .stats:
                statsContent
            case .ask:
                AskFocusLensView(viewModel: askViewModel)
            }
        }
        .frame(width: 680, height: 540)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == tab
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Stats content (original dashboard)

    private var statsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateHeader
            topSection
            Divider()
            middleSection
            Divider()
            bottomSection
        }
        .padding(20)
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        HStack(spacing: 8) {
            Button {
                Task { await aggregate.selectDate(
                    Calendar.current.date(byAdding: .day, value: -1, to: aggregate.selectedDate)!
                )}
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            DatePicker(
                "",
                selection: Binding(
                    get: { aggregate.selectedDate },
                    set: { date in Task { await aggregate.selectDate(date) } }
                ),
                in: ...Date(),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)

            Button {
                Task { await aggregate.selectDate(
                    Calendar.current.date(byAdding: .day, value: 1, to: aggregate.selectedDate)!
                )}
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(isToday)

            Spacer()

            if !isToday {
                Button("Today") {
                    Task { await aggregate.selectDate(Date()) }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
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
                Text("tracked")
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
                let maxCatSeconds = aggregate.categoryBreakdown.first?.totalSeconds ?? Self.minimumBarSeconds
                ForEach(aggregate.categoryBreakdown.prefix(8), id: \.category.name) { entry in
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
