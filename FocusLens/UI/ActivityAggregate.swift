import Foundation
import Observation
import os

enum ActivityScope: String, CaseIterable, Identifiable, Equatable {
    case today = "Today"
    case week  = "Week"
    case month = "Month"
    var id: String { rawValue }
}

@Observable
@MainActor
final class ActivityAggregate {

    // MARK: - Scope / Navigation

    private(set) var scope: ActivityScope = .today
    private(set) var selectedDate: Date = Date()
    private(set) var range: DateInterval = .init()
    private(set) var previousRange: DateInterval = .init()

    // MARK: - Shared stats

    private(set) var topApps: [(appName: String, appBundleId: String, totalSeconds: Double)] = []
    private(set) var totalActiveSeconds: Double = 0
    private(set) var categoryBreakdown: [(category: Category, totalSeconds: Double)] = []
    private(set) var productivityScore: Int = 50
    private(set) var productivityTierBreakdown: [(tier: Int, seconds: Double)] = []
    private(set) var topInterruptors: [(appName: String, appBundleId: String, totalSeconds: Double, tier: Int)] = []
    private(set) var previousActiveSeconds: Double = 0
    private(set) var previousProductivityScore: Int = 50
    private(set) var previousHasData: Bool = false

    // MARK: - Today-only stats

    private(set) var hourlyTierBreakdown: [(hour: Int, tier: Int, seconds: Double)] = []
    private(set) var hourlyCategoryBreakdown: [(hour: Int, colorHex: String, seconds: Double)] = []
    private(set) var topWindowTitles: [(windowTitle: String, appName: String, appBundleId: String, totalSeconds: Double, tier: Int)] = []
    private(set) var weekDailySeconds: [(date: Date, seconds: Double)] = []

    // MARK: - Range-only stats

    private(set) var dailyTierBreakdown: [(date: Date, tier: Int, seconds: Double)] = []

    // MARK: - Live tracking state (MenuBarView)

    var currentAppName: String = ""
    var isPaused: Bool = false

    // MARK: - Computed

    var activeSecondsDelta: Double { totalActiveSeconds - previousActiveSeconds }
    var productivityScoreDelta: Int { productivityScore - previousProductivityScore }

    var isCurrentPeriod: Bool {
        switch scope {
        case .today:        return Calendar.current.isDateInToday(selectedDate)
        case .week, .month: return range.contains(Date())
        }
    }

    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "ActivityAggregate")
    private let store: ActivitySessionStore
    private let categoryStore: CategoryStore

    init(store: ActivitySessionStore = .init(), categoryStore: CategoryStore = .init()) {
        self.store = store
        self.categoryStore = categoryStore
        let (r, p) = Self.calendarRange(component: .weekOfYear, anchor: Date())
        range = r
        previousRange = p
    }

    // MARK: - Navigation

    func selectScope(_ newScope: ActivityScope) async {
        scope = newScope
        switch newScope {
        case .today:
            selectedDate = Date()
        case .week:
            let (r, p) = Self.calendarRange(component: .weekOfYear, anchor: Date())
            range = r; previousRange = p
        case .month:
            let (r, p) = Self.calendarRange(component: .month, anchor: Date())
            range = r; previousRange = p
        }
        await refreshStats()
    }

    func selectDate(_ date: Date) async {
        selectedDate = date
        await refreshStats()
    }

    func previousPeriod() async {
        let component: Calendar.Component = scope == .week ? .weekOfYear : .month
        let anchor = Calendar.current.date(byAdding: component, value: -1, to: range.start)!
        let (r, p) = Self.calendarRange(component: component, anchor: anchor)
        range = r; previousRange = p
        await refreshStats()
    }

    func nextPeriod() async {
        let component: Calendar.Component = scope == .week ? .weekOfYear : .month
        let anchor = Calendar.current.date(byAdding: component, value: 1, to: range.start)!
        let (r, p) = Self.calendarRange(component: component, anchor: anchor)
        range = r; previousRange = p
        await refreshStats()
    }

    func jumpToCurrent() async {
        let component: Calendar.Component = scope == .week ? .weekOfYear : .month
        let (r, p) = Self.calendarRange(component: component, anchor: Date())
        range = r; previousRange = p
        await refreshStats()
    }

    // MARK: - Refresh

    func refreshStats() async {
        switch scope {
        case .today:        await refreshToday()
        case .week, .month: await refreshRange()
        }
    }

    // MARK: - Today refresh

    private struct TodaySnapshot: Sendable {
        let topApps: [(appName: String, appBundleId: String, totalSeconds: Double)]
        let totalActiveSeconds: Double
        let hourlyTierBreakdown: [(hour: Int, tier: Int, seconds: Double)]
        let hourlyCategoryBreakdown: [(hour: Int, colorHex: String, seconds: Double)]
        let rawBreakdown: [(categoryId: Int64?, totalSeconds: Double)]
        let topInterruptors: [(appName: String, appBundleId: String, totalSeconds: Double, tier: Int)]
        let topWindowTitles: [(windowTitle: String, appName: String, appBundleId: String, totalSeconds: Double, tier: Int)]
        let previousActiveSeconds: Double
        let previousRawBreakdown: [(categoryId: Int64?, totalSeconds: Double)]
        let previousHourlyTierBreakdown: [(hour: Int, tier: Int, seconds: Double)]
        let weekDailySeconds: [(date: Date, seconds: Double)]
        let categories: [Category]
    }

    private func refreshToday() async {
        let store = self.store
        let categoryStore = self.categoryStore
        let date = self.selectedDate
        let previousDate = Calendar.current.date(byAdding: .day, value: -1, to: date)!

        let weekInterval = Calendar.current.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 0)

        let snapshot = await Task.detached(priority: .utility) { () -> TodaySnapshot in
            TodaySnapshot(
                topApps: (try? store.fetchTopApps(for: date, limit: 10)) ?? [],
                totalActiveSeconds: (try? store.fetchActiveSeconds(for: date)) ?? 0,
                hourlyTierBreakdown: (try? store.fetchHourlyTierBreakdown(for: date)) ?? [],
                hourlyCategoryBreakdown: (try? store.fetchHourlyCategoryBreakdown(for: date)) ?? [],
                rawBreakdown: (try? store.fetchCategoryBreakdown(for: date)) ?? [],
                topInterruptors: (try? store.fetchTopInterruptors(for: date, limit: 5)) ?? [],
                topWindowTitles: (try? store.fetchTopWindowTitles(for: date, limit: 30)) ?? [],
                previousActiveSeconds: (try? store.fetchActiveSeconds(for: previousDate)) ?? 0,
                previousRawBreakdown: (try? store.fetchCategoryBreakdown(for: previousDate)) ?? [],
                previousHourlyTierBreakdown: (try? store.fetchHourlyTierBreakdown(for: previousDate)) ?? [],
                weekDailySeconds: (try? store.fetchDailyActiveSeconds(start: weekInterval.start, end: weekInterval.end)) ?? [],
                categories: (try? categoryStore.fetchAllCategories()) ?? []
            )
        }.value

        guard date == selectedDate, scope == .today else { return }

        topApps = snapshot.topApps
        totalActiveSeconds = snapshot.totalActiveSeconds
        hourlyTierBreakdown = snapshot.hourlyTierBreakdown
        hourlyCategoryBreakdown = snapshot.hourlyCategoryBreakdown
        topInterruptors = snapshot.topInterruptors
        topWindowTitles = snapshot.topWindowTitles
        weekDailySeconds = snapshot.weekDailySeconds
        previousActiveSeconds = snapshot.previousActiveSeconds
        previousHasData = snapshot.previousActiveSeconds > 0
        dailyTierBreakdown = []

        let todayResult = computeProductivityScore(
            rawBreakdown: snapshot.rawBreakdown,
            hourlyTierBreakdown: snapshot.hourlyTierBreakdown,
            categories: snapshot.categories
        )
        categoryBreakdown = todayResult.categoryBreakdown
        productivityScore = todayResult.score
        productivityTierBreakdown = todayResult.tierBreakdown

        let prevResult = computeProductivityScore(
            rawBreakdown: snapshot.previousRawBreakdown,
            hourlyTierBreakdown: snapshot.previousHourlyTierBreakdown,
            categories: snapshot.categories
        )
        previousProductivityScore = prevResult.score
    }

    // MARK: - Range refresh

    private struct RangeSnapshot: Sendable {
        let activeSeconds: Double
        let rawBreakdown: [(categoryId: Int64?, totalSeconds: Double)]
        let topApps: [(appName: String, appBundleId: String, totalSeconds: Double)]
        let topInterruptors: [(appName: String, appBundleId: String, totalSeconds: Double, tier: Int)]
        let dailyTierBreakdown: [(date: Date, tier: Int, seconds: Double)]
        let previousActiveSeconds: Double
        let previousRawBreakdown: [(categoryId: Int64?, totalSeconds: Double)]
        let categories: [Category]
    }

    private func refreshRange() async {
        let store = self.store
        let categoryStore = self.categoryStore
        let currentRange = self.range
        let prevRange = self.previousRange
        let currentScope = self.scope

        let snapshot = await Task.detached(priority: .utility) { () -> RangeSnapshot in
            RangeSnapshot(
                activeSeconds: (try? store.fetchActiveSeconds(start: currentRange.start, end: currentRange.end)) ?? 0,
                rawBreakdown: (try? store.fetchCategoryBreakdown(start: currentRange.start, end: currentRange.end)) ?? [],
                topApps: (try? store.fetchTopApps(start: currentRange.start, end: currentRange.end, limit: 5)) ?? [],
                topInterruptors: (try? store.fetchTopInterruptors(start: currentRange.start, end: currentRange.end, limit: 5)) ?? [],
                dailyTierBreakdown: (try? store.fetchDailyActiveTierBreakdown(start: currentRange.start, end: currentRange.end)) ?? [],
                previousActiveSeconds: (try? store.fetchActiveSeconds(start: prevRange.start, end: prevRange.end)) ?? 0,
                previousRawBreakdown: (try? store.fetchCategoryBreakdown(start: prevRange.start, end: prevRange.end)) ?? [],
                categories: (try? categoryStore.fetchAllCategories()) ?? []
            )
        }.value

        guard range == currentRange, scope == currentScope else { return }

        totalActiveSeconds = snapshot.activeSeconds
        topApps = snapshot.topApps
        topInterruptors = snapshot.topInterruptors
        dailyTierBreakdown = snapshot.dailyTierBreakdown
        previousActiveSeconds = snapshot.previousActiveSeconds
        previousHasData = snapshot.previousActiveSeconds > 0
        hourlyTierBreakdown = []
        hourlyCategoryBreakdown = []
        topWindowTitles = []
        weekDailySeconds = []

        let result = computeProductivityScoreForRange(
            rawBreakdown: snapshot.rawBreakdown,
            categories: snapshot.categories
        )
        categoryBreakdown = result.categoryBreakdown
        productivityScore = result.score
        productivityTierBreakdown = result.tierBreakdown

        let prevResult = computeProductivityScoreForRange(
            rawBreakdown: snapshot.previousRawBreakdown,
            categories: snapshot.categories
        )
        previousProductivityScore = prevResult.score
    }

    // MARK: - Calendar helpers

    private static func calendarRange(component: Calendar.Component, anchor: Date) -> (DateInterval, DateInterval) {
        let cal = Calendar.current
        let current = cal.dateInterval(of: component, for: anchor) ?? DateInterval(start: anchor, duration: 0)
        let prevAnchor = cal.date(byAdding: component, value: -1, to: current.start)!
        let previous = cal.dateInterval(of: component, for: prevAnchor) ?? DateInterval(start: prevAnchor, duration: 0)
        return (current, previous)
    }
}
