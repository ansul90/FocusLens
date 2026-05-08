import Foundation
import Observation
import os

enum RangeKind: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    var id: String { rawValue }
}

@Observable
@MainActor
final class RangeAggregate {
    private(set) var kind: RangeKind = .week
    private(set) var range: DateInterval = .init()
    private(set) var previousRange: DateInterval = .init()

    private(set) var totalActiveSeconds: Double = 0
    private(set) var productivityScore: Int = 50
    private(set) var productivityTierBreakdown: [(tier: Int, seconds: Double)] = []
    private(set) var categoryBreakdown: [(category: Category, totalSeconds: Double)] = []
    private(set) var topApps: [(appName: String, appBundleId: String, totalSeconds: Double)] = []
    private(set) var topInterruptors: [(appName: String, appBundleId: String, totalSeconds: Double, tier: Int)] = []
    private(set) var dailyTierBreakdown: [(date: Date, tier: Int, seconds: Double)] = []

    private(set) var previousActiveSeconds: Double = 0
    private(set) var previousProductivityScore: Int = 50
    private(set) var previousHasData: Bool = false

    var activeSecondsDelta: Double { totalActiveSeconds - previousActiveSeconds }
    var productivityScoreDelta: Int { productivityScore - previousProductivityScore }

    var isCurrentPeriod: Bool {
        range.contains(Date())
    }

    private let logger = Logger(subsystem: "com.focuslens.app", category: "RangeAggregate")
    private let store: ActivitySessionStore
    private let categoryStore: CategoryStore

    init(store: ActivitySessionStore = .init(), categoryStore: CategoryStore = .init()) {
        self.store = store
        self.categoryStore = categoryStore
        let (r, p) = Self.calendarRange(kind: .week, anchor: Date())
        range = r
        previousRange = p
    }

    func selectKind(_ newKind: RangeKind) async {
        kind = newKind
        let (r, p) = Self.calendarRange(kind: newKind, anchor: range.start)
        range = r
        previousRange = p
        await refreshStats()
    }

    func nextPeriod() async {
        let unit: Calendar.Component = kind == .week ? .weekOfYear : .month
        let anchor = Calendar.current.date(byAdding: unit, value: 1, to: range.start)!
        let (r, p) = Self.calendarRange(kind: kind, anchor: anchor)
        range = r
        previousRange = p
        await refreshStats()
    }

    func previousPeriod() async {
        let unit: Calendar.Component = kind == .week ? .weekOfYear : .month
        let anchor = Calendar.current.date(byAdding: unit, value: -1, to: range.start)!
        let (r, p) = Self.calendarRange(kind: kind, anchor: anchor)
        range = r
        previousRange = p
        await refreshStats()
    }

    func jumpToCurrent() async {
        let (r, p) = Self.calendarRange(kind: kind, anchor: Date())
        range = r
        previousRange = p
        await refreshStats()
    }

    func refreshStats() async {
        let store = self.store
        let categoryStore = self.categoryStore
        let currentRange = self.range
        let prevRange = self.previousRange

        let fetched = await Task.detached(priority: .utility) { () -> RangeFetchedSnapshot in
            RangeFetchedSnapshot(
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

        guard range == currentRange else { return }

        totalActiveSeconds = fetched.activeSeconds
        topApps = fetched.topApps
        topInterruptors = fetched.topInterruptors
        dailyTierBreakdown = fetched.dailyTierBreakdown
        previousActiveSeconds = fetched.previousActiveSeconds
        previousHasData = fetched.previousActiveSeconds > 0

        let result = computeProductivityScoreForRange(
            rawBreakdown: fetched.rawBreakdown,
            categories: fetched.categories
        )
        categoryBreakdown = result.categoryBreakdown
        productivityScore = result.score
        productivityTierBreakdown = result.tierBreakdown

        let prevResult = computeProductivityScoreForRange(
            rawBreakdown: fetched.previousRawBreakdown,
            categories: fetched.categories
        )
        previousProductivityScore = prevResult.score
    }

    // Returns (currentRange, previousRange) for a calendar week or month containing anchor.
    private static func calendarRange(kind: RangeKind, anchor: Date) -> (DateInterval, DateInterval) {
        let cal = Calendar.current
        let component: Calendar.Component = kind == .week ? .weekOfYear : .month
        let current = cal.dateInterval(of: component, for: anchor) ?? DateInterval(start: anchor, duration: 0)
        let prevAnchor = cal.date(byAdding: kind == .week ? .weekOfYear : .month, value: -1, to: current.start)!
        let previous = cal.dateInterval(of: component, for: prevAnchor) ?? DateInterval(start: prevAnchor, duration: 0)
        return (current, previous)
    }
}

private struct RangeFetchedSnapshot: Sendable {
    let activeSeconds: Double
    let rawBreakdown: [(categoryId: Int64?, totalSeconds: Double)]
    let topApps: [(appName: String, appBundleId: String, totalSeconds: Double)]
    let topInterruptors: [(appName: String, appBundleId: String, totalSeconds: Double, tier: Int)]
    let dailyTierBreakdown: [(date: Date, tier: Int, seconds: Double)]
    let previousActiveSeconds: Double
    let previousRawBreakdown: [(categoryId: Int64?, totalSeconds: Double)]
    let categories: [Category]
}
