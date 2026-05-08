import SwiftUI

struct DashboardView: View {
    @Environment(TodayAggregate.self) private var aggregate
    @Environment(RangeAggregate.self) private var rangeAggregate
    @Environment(AskViewModel.self) private var askViewModel

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    @State private var selectedNav: NavDestination? = .stats

    private enum NavDestination: String, Hashable {
        case stats, trends, ask
        case settingsGeneral, settingsCategories, settingsNeverTrack, settingsAI
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(aggregate.selectedDate)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedNav) {
                Section("Overview") {
                    Label("Today", systemImage: "chart.bar.fill")
                        .tag(NavDestination.stats)
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                        .tag(NavDestination.trends)
                    Label("Ask FocusLens", systemImage: "bubble.left.and.bubble.right.fill")
                        .tag(NavDestination.ask)
                }
                Section("Settings") {
                    Label("General", systemImage: "gear")
                        .tag(NavDestination.settingsGeneral)
                    Label("Categories", systemImage: "tag")
                        .tag(NavDestination.settingsCategories)
                    Label("Never Track", systemImage: "eye.slash")
                        .tag(NavDestination.settingsNeverTrack)
                    Label("AI", systemImage: "sparkles")
                        .tag(NavDestination.settingsAI)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 200)
        } detail: {
            switch selectedNav ?? .stats {
            case .stats:
                statsContent
            case .trends:
                TrendsView()
                    .environment(rangeAggregate)
            case .ask:
                AskFocusLensView(viewModel: askViewModel)
            case .settingsGeneral:
                GeneralSettingsTab()
            case .settingsCategories:
                CategorySettingsView()
            case .settingsNeverTrack:
                NeverTrackTab()
            case .settingsAI:
                AISettingsView()
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    // MARK: - Stats content

    private var statsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                dateHeader
                    .padding(.bottom, 16)

                heroRow
                    .padding(.bottom, 16)

                Divider()

                midRow
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
    }

    // MARK: - Hero Row: time logged + productivity gauge

    private var heroRow: some View {
        HStack(alignment: .top, spacing: 24) {
            HeroTimeView(
                totalSeconds: aggregate.totalActiveSeconds,
                previousSeconds: aggregate.previousDayActiveSeconds,
                hasComparison: aggregate.previousDayHasData
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .center, spacing: 6) {
                ProductivityGaugeView(score: aggregate.productivityScore)
                    .frame(width: 110, height: 110)
                DeltaCaption(
                    delta: Double(aggregate.productivityScoreDelta),
                    unit: .points,
                    hasComparison: aggregate.previousDayHasData
                )
            }
            .frame(width: 160)
        }
    }

    // MARK: - Mid Row: timeline + categories

    private var midRow: some View {
        HStack(alignment: .top, spacing: 20) {
            timelineColumn
                .frame(maxWidth: .infinity)

            Divider()

            categoriesColumn
                .frame(width: 260)
        }
    }

    private var timelineColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TIMELINE")
                .font(.caption)
                .foregroundStyle(.secondary)

            HourlyTierChart(hourlyTierBreakdown: aggregate.hourlyTierBreakdown)
                .frame(height: 90)

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
    }

    // MARK: - Bottom Row: top apps | top interruptors | top window titles

    private var bottomRow: some View {
        HStack(alignment: .top, spacing: 0) {
            topAppsColumn
            Divider().padding(.horizontal, 12)
            topInterruptorsColumn
            Divider().padding(.horizontal, 12)
            topWindowTitlesColumn
        }
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
                ForEach(aggregate.topApps.prefix(5), id: \.appName) { app in
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

    private var topWindowTitlesColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOP WINDOWS")
                .font(.caption)
                .foregroundStyle(.secondary)

            if aggregate.topWindowTitles.isEmpty {
                Text("No window data available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(aggregate.topWindowTitles, id: \.windowTitle) { entry in
                    WindowTitlePillRow(
                        title: entry.windowTitle,
                        appName: entry.appName,
                        seconds: entry.totalSeconds,
                        tier: entry.tier
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
