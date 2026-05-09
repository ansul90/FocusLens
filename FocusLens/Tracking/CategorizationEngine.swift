import Foundation
import GRDB
import os

private let logger = Logger(subsystem: "com.focuslens.app", category: "CategorizationEngine")

struct CategorizationEngine {
    private let store: CategoryStore

    init(store: CategoryStore = CategoryStore()) {
        self.store = store
    }

    // Returns the best-matching Category for a given session.
    // Resolution order: overrides > rules > nil.
    func categorize(bundleId: String, windowTitle: String?) -> Category? {
        let rules: [CategoryRule]
        let allCategories: [Category]
        let overrides: [CategoryOverride]
        do {
            rules = try store.fetchAllRulesOrdered()
            allCategories = try store.fetchAllCategories()
            overrides = try store.fetchAllOverrides()
        } catch {
            logger.error("Failed to load rules/categories/overrides: \(error)")
            return nil
        }
        let categoryMap = Dictionary(uniqueKeysWithValues: allCategories.compactMap { c -> (Int64, Category)? in
            guard let id = c.id else { return nil }
            return (id, c)
        })

        // 1. Override wins unconditionally
        if let override = overrides.first(where: { $0.appBundleId == bundleId }),
           let category = categoryMap[override.categoryId] {
            return category
        }

        // 2. Best rule match
        guard let matchedRule = CategorizationEngine.bestMatch(rules: rules, bundleId: bundleId, windowTitle: windowTitle) else {
            return nil
        }
        return categoryMap[matchedRule.categoryId]
    }

    private static let grdbDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.timeZone = TimeZone(identifier: "UTC")!
        return f
    }()

    // Categorizes all completed sessions that have no category yet.
    // Returns the number of sessions updated.
    @discardableResult
    func batchCategorize() throws -> Int {
        let rules = try store.fetchAllRulesOrdered()
        let categories = try store.fetchAllCategories()
        let overrides = try store.fetchAllOverrides()
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.compactMap { c -> (Int64, Category)? in
            guard let id = c.id else { return nil }
            return (id, c)
        })
        let overrideMap = Dictionary(uniqueKeysWithValues: overrides.map { ($0.appBundleId, $0.categoryId) })

        let pool = DatabaseManager.shared.dbPool
        let uncategorized: [ActivitySession] = try pool.read { db in
            try ActivitySession
                .filter(ActivitySession.Columns.endedAt != nil)
                .filter(ActivitySession.Columns.isIdle == false)
                .filter(ActivitySession.Columns.categoryId == nil)
                .fetchAll(db)
        }

        var count = 0
        try pool.write { db in
            for session in uncategorized {
                guard let id = session.id else { continue }
                // Override wins first
                if let overrideCategoryId = overrideMap[session.appBundleId],
                   categoryMap[overrideCategoryId] != nil {
                    try db.execute(sql: "UPDATE activity_sessions SET category_id = ? WHERE id = ?",
                                   arguments: [overrideCategoryId, id])
                    count += 1
                    continue
                }
                guard let matchedRule = CategorizationEngine.bestMatch(
                    rules: rules, bundleId: session.appBundleId, windowTitle: session.windowTitle
                ) else { continue }
                guard categoryMap[matchedRule.categoryId] != nil else { continue }
                try db.execute(
                    sql: "UPDATE activity_sessions SET category_id = ? WHERE id = ?",
                    arguments: [matchedRule.categoryId, id]
                )
                count += 1
            }
        }
        return count
    }

    // Recategorizes all sessions (including already-categorized) since a given date.
    // Returns the number of sessions updated.
    @discardableResult
    func recategorizeAll(since date: Date) throws -> Int {
        let rules = try store.fetchAllRulesOrdered()
        let categories = try store.fetchAllCategories()
        let overrides = try store.fetchAllOverrides()
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.compactMap { c -> (Int64, Category)? in
            guard let id = c.id else { return nil }
            return (id, c)
        })
        let overrideMap = Dictionary(uniqueKeysWithValues: overrides.map { ($0.appBundleId, $0.categoryId) })

        let pool = DatabaseManager.shared.dbPool
        let sinceStr = CategorizationEngine.grdbDateFormatter.string(from: date)

        let sessions: [ActivitySession] = try pool.read { db in
            try ActivitySession
                .filter(ActivitySession.Columns.endedAt != nil)
                .filter(ActivitySession.Columns.isIdle == false)
                .filter(ActivitySession.Columns.startedAt >= sinceStr)
                .fetchAll(db)
        }

        var count = 0
        try pool.write { db in
            for session in sessions {
                guard let id = session.id else { continue }
                // Override wins first
                if let overrideCategoryId = overrideMap[session.appBundleId],
                   categoryMap[overrideCategoryId] != nil {
                    try db.execute(sql: "UPDATE activity_sessions SET category_id = ? WHERE id = ?",
                                   arguments: [overrideCategoryId, id])
                    count += 1
                    continue
                }
                let matchedRule = CategorizationEngine.bestMatch(
                    rules: rules, bundleId: session.appBundleId, windowTitle: session.windowTitle
                )
                let categoryId: Int64? = matchedRule.flatMap { categoryMap[$0.categoryId] != nil ? $0.categoryId : nil }
                try db.execute(
                    sql: "UPDATE activity_sessions SET category_id = ? WHERE id = ?",
                    arguments: [categoryId, id]
                )
                if categoryId != nil { count += 1 }
            }
        }
        return count
    }

    // MARK: - Internal static helper (also used by tests via @testable import)

    /// Returns the highest-priority matching rule for the given session context.
    /// Tie-breaking when priorities are equal: .appBundle > .windowTitleContains > .windowTitleRegex.
    static func bestMatch(rules: [CategoryRule], bundleId: String, windowTitle: String?) -> CategoryRule? {
        let matchTypeOrder: (RuleMatchType) -> Int = { type in
            switch type {
            case .appBundle: return 0
            case .windowTitleContains: return 1
            case .windowTitleRegex: return 2
            }
        }

        let sorted = rules.sorted {
            if $0.priority != $1.priority {
                return $0.priority > $1.priority
            }
            return matchTypeOrder($0.matchType) < matchTypeOrder($1.matchType)
        }

        return sorted.first { rule in
            ruleMatches(rule: rule, bundleId: bundleId, windowTitle: windowTitle)
        }
    }

    // MARK: - Private

    private static func ruleMatches(rule: CategoryRule, bundleId: String, windowTitle: String?) -> Bool {
        switch rule.matchType {
        case .appBundle:
            return bundleId == rule.matchValue
        case .windowTitleContains:
            guard let title = windowTitle else { return false }
            return title.localizedCaseInsensitiveContains(rule.matchValue)
        case .windowTitleRegex:
            guard let title = windowTitle else { return false }
            return (try? NSRegularExpression(pattern: rule.matchValue))
                .map { $0.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil }
                ?? false
        }
    }
}
