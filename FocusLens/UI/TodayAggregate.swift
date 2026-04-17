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
    private(set) var hourlyBreakdown: [(hour: Int, seconds: Double)] = []
    private(set) var productivityTierBreakdown: [(tier: Int, seconds: Double)] = []
    private(set) var hourlyTierBreakdown: [(hour: Int, tier: Int, seconds: Double)] = []
    var currentAppName: String = ""
    var isPaused: Bool = false

    private let logger = Logger(subsystem: "com.focuslens.app", category: "TodayAggregate")
    private let store: ActivitySessionStore
    private let categoryStore: CategoryStore

    init(store: ActivitySessionStore = .init(), categoryStore: CategoryStore = .init()) {
        self.store = store
        self.categoryStore = categoryStore
    }

    func refreshStats() {
        topApps = (try? store.fetchTodayTopApps(limit: 10)) ?? []
        totalActiveSeconds = (try? store.fetchTodayActiveSeconds()) ?? 0
        hourlyBreakdown = (try? store.fetchTodayHourlyBreakdown()) ?? []
        do {
            hourlyTierBreakdown = try store.fetchTodayHourlyTierBreakdown()
        } catch {
            logger.error("fetchTodayHourlyTierBreakdown failed: \(error)")
            hourlyTierBreakdown = []
        }
        refreshCategoryBreakdown()
    }

    private func refreshCategoryBreakdown() {
        guard let rawBreakdown = try? store.fetchTodayCategoryBreakdown(),
              let categories = try? categoryStore.fetchAllCategories() else {
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

        // Productivity score: map weighted average from [-2,+2] to [0,100]
        if categorizedTotal > 0 {
            let avg = weightedSum / categorizedTotal  // range [-2, +2]
            productivityScore = max(0, min(100, Int(((avg + 2.0) / 4.0) * 100)))
        } else {
            productivityScore = 50  // neutral when no data
        }
    }
}
