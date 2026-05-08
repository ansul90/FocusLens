import Foundation
import Observation
import os

@Observable
@MainActor
final class TodayAggregate {
    private(set) var topApps: [(appName: String, appBundleId: String, totalSeconds: Double)] = []
    private(set) var totalActiveSeconds: Double = 0
    private(set) var categoryBreakdown: [(category: Category, totalSeconds: Double)] = []
    private(set) var productivityScore: Int = 50
    private(set) var productivityTierBreakdown: [(tier: Int, seconds: Double)] = []
    private(set) var hourlyTierBreakdown: [(hour: Int, tier: Int, seconds: Double)] = []
    private(set) var topInterruptors: [(appName: String, appBundleId: String, totalSeconds: Double, tier: Int)] = []
    private(set) var topWindowTitles: [(windowTitle: String, appName: String, appBundleId: String, totalSeconds: Double, tier: Int)] = []
    private(set) var previousDayActiveSeconds: Double = 0
    private(set) var previousDayProductivityScore: Int = 50
    private(set) var previousDayHasData: Bool = false
    var currentAppName: String = ""
    var isPaused: Bool = false
    private(set) var selectedDate: Date = Date()

    var activeSecondsDelta: Double { totalActiveSeconds - previousDayActiveSeconds }
    var productivityScoreDelta: Int { productivityScore - previousDayProductivityScore }

    private let logger = Logger(subsystem: "com.focuslens.app", category: "TodayAggregate")
    private let store: ActivitySessionStore
    private let categoryStore: CategoryStore

    init(store: ActivitySessionStore = .init(), categoryStore: CategoryStore = .init()) {
        self.store = store
        self.categoryStore = categoryStore
    }

    func selectDate(_ date: Date) async {
        selectedDate = date
        await refreshStats()
    }

    private struct FetchedSnapshot: Sendable {
        let topApps: [(appName: String, appBundleId: String, totalSeconds: Double)]
        let totalActiveSeconds: Double
        let hourlyTierBreakdown: [(hour: Int, tier: Int, seconds: Double)]
        let rawBreakdown: [(categoryId: Int64?, totalSeconds: Double)]
        let topInterruptors: [(appName: String, appBundleId: String, totalSeconds: Double, tier: Int)]
        let topWindowTitles: [(windowTitle: String, appName: String, appBundleId: String, totalSeconds: Double, tier: Int)]
        let previousActiveSeconds: Double
        let previousRawBreakdown: [(categoryId: Int64?, totalSeconds: Double)]
        let previousHourlyTierBreakdown: [(hour: Int, tier: Int, seconds: Double)]
        let categories: [Category]
    }

    func refreshStats() async {
        let store = self.store
        let categoryStore = self.categoryStore
        let date = self.selectedDate
        let previousDate = Calendar.current.date(byAdding: .day, value: -1, to: date)!

        let fetched = await Task.detached(priority: .utility) { () -> FetchedSnapshot in
            FetchedSnapshot(
                topApps: (try? store.fetchTopApps(for: date, limit: 10)) ?? [],
                totalActiveSeconds: (try? store.fetchActiveSeconds(for: date)) ?? 0,
                hourlyTierBreakdown: (try? store.fetchHourlyTierBreakdown(for: date)) ?? [],
                rawBreakdown: (try? store.fetchCategoryBreakdown(for: date)) ?? [],
                topInterruptors: (try? store.fetchTopInterruptors(for: date, limit: 5)) ?? [],
                topWindowTitles: (try? store.fetchTopWindowTitles(for: date, limit: 5)) ?? [],
                previousActiveSeconds: (try? store.fetchActiveSeconds(for: previousDate)) ?? 0,
                previousRawBreakdown: (try? store.fetchCategoryBreakdown(for: previousDate)) ?? [],
                previousHourlyTierBreakdown: (try? store.fetchHourlyTierBreakdown(for: previousDate)) ?? [],
                categories: (try? categoryStore.fetchAllCategories()) ?? []
            )
        }.value

        guard date == selectedDate else { return }

        topApps = fetched.topApps
        totalActiveSeconds = fetched.totalActiveSeconds
        hourlyTierBreakdown = fetched.hourlyTierBreakdown
        topInterruptors = fetched.topInterruptors
        topWindowTitles = fetched.topWindowTitles
        previousDayActiveSeconds = fetched.previousActiveSeconds
        previousDayHasData = fetched.previousActiveSeconds > 0

        let todayResult = computeProductivityScore(
            rawBreakdown: fetched.rawBreakdown,
            hourlyTierBreakdown: fetched.hourlyTierBreakdown,
            categories: fetched.categories
        )
        categoryBreakdown = todayResult.categoryBreakdown
        productivityScore = todayResult.score
        productivityTierBreakdown = todayResult.tierBreakdown

        let prevResult = computeProductivityScore(
            rawBreakdown: fetched.previousRawBreakdown,
            hourlyTierBreakdown: fetched.previousHourlyTierBreakdown,
            categories: fetched.categories
        )
        previousDayProductivityScore = prevResult.score
    }

}
