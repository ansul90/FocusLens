import Foundation
import Observation

@Observable
@MainActor
final class TodayAggregate {
    private(set) var topApps: [(appName: String, appBundleId: String, totalSeconds: Double)] = []
    private(set) var totalActiveSeconds: Double = 0
    private(set) var categoryBreakdown: [(category: Category, totalSeconds: Double)] = []
    private(set) var productivityScore: Int = 50
    private(set) var hourlyBreakdown: [(hour: Int, seconds: Double)] = []
    var currentAppName: String = ""
    var isPaused: Bool = false

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
        refreshCategoryBreakdown()
    }

    private func refreshCategoryBreakdown() {
        guard let rawBreakdown = try? store.fetchTodayCategoryBreakdown(),
              let categories = try? categoryStore.fetchAllCategories() else {
            categoryBreakdown = []
            productivityScore = 50
            return
        }

        let categoryMap = Dictionary(uniqueKeysWithValues: categories.compactMap { c -> (Int64, Category)? in
            guard let id = c.id else { return nil }
            return (id, c)
        })

        // Build breakdown for categorized sessions only
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

        // Productivity score: map weighted average from [-2,+2] to [0,100]
        if categorizedTotal > 0 {
            let avg = weightedSum / categorizedTotal  // range [-2, +2]
            productivityScore = Int(((avg + 2.0) / 4.0) * 100)
        } else {
            productivityScore = 50  // neutral when no data
        }
    }
}
