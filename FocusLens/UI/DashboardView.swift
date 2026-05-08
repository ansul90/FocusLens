import SwiftUI

struct DashboardView: View {
    @Environment(ActivityAggregate.self) private var aggregate
    @Environment(AskViewModel.self) private var askViewModel

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

    @State private var selectedNav: NavDestination? = .activity
    @State private var hourlyColorMode: HourlyColorMode = .tier

    private enum NavDestination: String, Hashable {
        case activity, ask
        case settingsGeneral, settingsCategories, settingsNeverTrack, settingsAI
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedNav) {
                Section("Overview") {
                    Label("Activity", systemImage: "chart.bar.fill")
                        .tag(NavDestination.activity)
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
            switch selectedNav ?? .activity {
            case .activity:
                activityContent
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

    // MARK: - Activity Content

    private var activityContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                activityHeader
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

    // MARK: - Header (scope picker + navigation)

    private var activityHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: Binding(
                get: { aggregate.scope },
                set: { scope in Task { await aggregate.selectScope(scope) } }
            )) {
                ForEach(ActivityScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            if aggregate.scope == .today {
                todayNavRow
            } else {
                rangeNavRow
            }
        }
    }

    private var todayNavRow: some View {
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
            .disabled(aggregate.isCurrentPeriod)

            Spacer()

            if !aggregate.isCurrentPeriod {
                Button("Today") {
                    Task { await aggregate.selectDate(Date()) }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var rangeNavRow: some View {
        HStack(spacing: 8) {
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
                Button(aggregate.scope == .week ? "This week" : "This month") {
                    Task { await aggregate.jumpToCurrent() }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(aggregate.scope == .week ? "This week" : "This month")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Hero Row

    private var heroRow: some View {
        HStack(alignment: .top, spacing: 24) {
            HeroTimeView(
                totalSeconds: aggregate.totalActiveSeconds,
                previousSeconds: aggregate.previousActiveSeconds,
                hasComparison: aggregate.previousHasData,
                comparisonLabel: heroComparisonLabel
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .center, spacing: 6) {
                ProductivityGaugeView(score: aggregate.productivityScore)
                    .frame(width: 110, height: 110)
                DeltaCaption(
                    delta: Double(aggregate.productivityScoreDelta),
                    unit: .points,
                    hasComparison: aggregate.previousHasData,
                    comparisonLabel: heroComparisonLabel
                )
            }
            .frame(width: 160)
        }
    }

    // MARK: - Mid Row: chart + categories

    private var midRow: some View {
        HStack(alignment: .top, spacing: 20) {
            chartColumn
                .frame(maxWidth: .infinity)

            Divider()

            categoriesColumn
                .frame(width: 260)
        }
    }

    private var chartColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(aggregate.scope == .today ? "TIMELINE" : "DAILY ACTIVITY")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if aggregate.scope != .today && aggregate.isCurrentPeriod {
                    Text("· in progress")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if aggregate.scope == .today {
                    Picker("", selection: $hourlyColorMode) {
                        ForEach(HourlyColorMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
            }

            if aggregate.scope == .today {
                WeekOverviewBars(
                    weekDailySeconds: aggregate.weekDailySeconds,
                    selectedDate: aggregate.selectedDate
                )
                .frame(height: 52)
                .padding(.bottom, 8)

                if hourlyColorMode == .tier {
                    HourlyTierChart(hourlyTierBreakdown: aggregate.hourlyTierBreakdown)
                        .frame(height: 90)
                } else {
                    HourlyCategoryChart(hourlyCategoryBreakdown: aggregate.hourlyCategoryBreakdown)
                        .frame(height: 90)
                }
            } else {
                DailyTierChart(
                    dailyTierBreakdown: aggregate.dailyTierBreakdown,
                    range: aggregate.range,
                    kind: aggregate.scope
                )
                .frame(height: 120)
            }

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
        let activeTiers = TierColors.ordered.filter { (tierSeconds[$0] ?? 0) > 0 }

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

    // MARK: - Bottom Row: unified app list

    private var bottomRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOP APPS")
                .font(.caption)
                .foregroundStyle(.secondary)

            if aggregate.topApps.isEmpty {
                Text("No data yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(aggregate.topApps, id: \.appBundleId) { app in
                    ExpandableAppRow(
                        appName: app.appName,
                        appBundleId: app.appBundleId,
                        seconds: app.totalSeconds,
                        totalSeconds: aggregate.totalActiveSeconds,
                        tierTint: interruptorTier(for: app.appBundleId),
                        windowTitles: windows(for: app.appBundleId)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func interruptorTier(for bundleId: String) -> Color? {
        aggregate.topInterruptors.first { $0.appBundleId == bundleId }
            .map { TierColors.color(for: $0.tier) }
    }

    private func windows(for bundleId: String) -> [(windowTitle: String, totalSeconds: Double, tier: Int)] {
        aggregate.topWindowTitles
            .filter { $0.appBundleId == bundleId }
            .map { (windowTitle: $0.windowTitle, totalSeconds: $0.totalSeconds, tier: $0.tier) }
    }

    // MARK: - Helpers

    private var heroComparisonLabel: String {
        switch aggregate.scope {
        case .today:  return "vs yesterday"
        case .week:   return "vs last week"
        case .month:  return "vs last month"
        }
    }

    private var periodLabel: String {
        switch aggregate.scope {
        case .today:
            return ""
        case .week:
            let start = Self.shortDateFormatter.string(from: aggregate.range.start)
            let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: aggregate.range.end)!
            let end = Self.shortDateFormatter.string(from: lastDay)
            return "\(start) – \(end)"
        case .month:
            return Self.monthYearFormatter.string(from: aggregate.range.start)
        }
    }
}
