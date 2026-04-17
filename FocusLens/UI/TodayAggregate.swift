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
    var currentAppName: String = ""
    var isPaused: Bool = false
    private(set) var selectedDate: Date = Date()

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
        let categories: [Category]
    }

    func refreshStats() async {
        let store = self.store
        let categoryStore = self.categoryStore
        let date = self.selectedDate

        let fetched = await Task.detached(priority: .utility) { () -> FetchedSnapshot in
            FetchedSnapshot(
                topApps: (try? store.fetchTopApps(for: date, limit: 10)) ?? [],
                totalActiveSeconds: (try? store.fetchActiveSeconds(for: date)) ?? 0,
                hourlyTierBreakdown: (try? store.fetchHourlyTierBreakdown(for: date)) ?? [],
                rawBreakdown: (try? store.fetchCategoryBreakdown(for: date)) ?? [],
                categories: (try? categoryStore.fetchAllCategories()) ?? []
            )
        }.value

        topApps = fetched.topApps
        totalActiveSeconds = fetched.totalActiveSeconds
        hourlyTierBreakdown = fetched.hourlyTierBreakdown
        refreshCategoryBreakdown(rawBreakdown: fetched.rawBreakdown, categories: fetched.categories)
    }

    private func refreshCategoryBreakdown(
        rawBreakdown: [(categoryId: Int64?, totalSeconds: Double)],
        categories: [Category]
    ) {
        guard !categories.isEmpty else {
            categoryBreakdown = []
            productivityScore = 50
            productivityTierBreakdown = []
            return
        }

        let categoryMap = Dictionary(uniqueKeysWithValues: categories.compactMap { c -> (Int64, Category)? in
            guard let id = c.id else { return nil }
            return (id, c)
        })

        var breakdown: [(category: Category, totalSeconds: Double)] = []
        var weightedSum: Double = 0
        var categorizedTotal: Double = 0

        for entry in rawBreakdown {
            guard let categoryId = entry.categoryId,
                  let category = categoryMap[categoryId] else { continue }
            breakdown.append((category: category, totalSeconds: entry.totalSeconds))
            weightedSum += Double(category.productivityScore) * entry.totalSeconds
            categorizedTotal += entry.totalSeconds
        }

        categoryBreakdown = breakdown.sorted { $0.totalSeconds > $1.totalSeconds }

        var tierTotals: [Int: Double] = [:]
        for entry in hourlyTierBreakdown {
            tierTotals[entry.tier, default: 0] += entry.seconds
        }
        productivityTierBreakdown = tierTotals.map { (tier: $0.key, seconds: $0.value) }
            .sorted { $0.tier > $1.tier }

        if categorizedTotal > 0 {
            let avg = weightedSum / categorizedTotal
            productivityScore = max(0, min(100, Int(((avg + 2.0) / 4.0) * 100)))
        } else {
            productivityScore = 50
        }
    }
}
