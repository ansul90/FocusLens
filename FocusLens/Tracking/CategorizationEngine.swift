import Foundation
import GRDB

struct CategorizationEngine {
    private let store: CategoryStore

    init(store: CategoryStore = CategoryStore()) {
        self.store = store
    }

    // Returns the best-matching Category for a given session, or nil if no rule matches.
    func categorize(bundleId: String, windowTitle: String?) -> Category? {
        guard let rules = try? store.fetchAllRulesOrdered() else { return nil }
        guard let categories = try? store.fetchAllCategories() else { return nil }
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.compactMap { c -> (Int64, Category)? in
            guard let id = c.id else { return nil }
            return (id, c)
        })

        guard let matchedRule = CategorizationEngine.bestMatch(rules: rules, bundleId: bundleId, windowTitle: windowTitle) else {
            return nil
        }
        return categoryMap[matchedRule.categoryId]
    }

    // Categorizes all completed sessions that have no category yet.
    // Returns the number of sessions updated.
    @discardableResult
    func batchCategorize() throws -> Int {
        let rules = try store.fetchAllRulesOrdered()
        let categories = try store.fetchAllCategories()
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.compactMap { c -> (Int64, Category)? in
            guard let id = c.id else { return nil }
            return (id, c)
        })

        let pool = DatabaseManager.shared.dbPool
        let uncategorized: [ActivitySession] = try pool.read { db in
            try ActivitySession
                .filter(ActivitySession.Columns.endedAt != nil)
                .filter(ActivitySession.Columns.isIdle == false)
                .filter(ActivitySession.Columns.categoryId == nil)
                .fetchAll(db)
        }

        var count = 0
        for session in uncategorized {
            guard let id = session.id else { continue }
            guard let matchedRule = CategorizationEngine.bestMatch(
                rules: rules,
                bundleId: session.appBundleId,
                windowTitle: session.windowTitle
            ) else { continue }
            guard categoryMap[matchedRule.categoryId] != nil else { continue }
            let categoryId = matchedRule.categoryId
            try pool.write { db in
                try db.execute(
                    sql: "UPDATE activity_sessions SET category_id = ? WHERE id = ?",
                    arguments: [categoryId, id]
                )
            }
            count += 1
        }
        return count
    }

    // Recategorizes all sessions (including already-categorized) since a given date.
    // Returns the number of sessions updated.
    @discardableResult
    func recategorizeAll(since date: Date) throws -> Int {
        let rules = try store.fetchAllRulesOrdered()
        let categories = try store.fetchAllCategories()
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.compactMap { c -> (Int64, Category)? in
            guard let id = c.id else { return nil }
            return (id, c)
        })

        let pool = DatabaseManager.shared.dbPool
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        fmt.timeZone = TimeZone(identifier: "UTC")!
        let sinceStr = fmt.string(from: date)

        let sessions: [ActivitySession] = try pool.read { db in
            try ActivitySession
                .filter(ActivitySession.Columns.endedAt != nil)
                .filter(ActivitySession.Columns.isIdle == false)
                .filter(ActivitySession.Columns.startedAt >= sinceStr)
                .fetchAll(db)
        }

        var count = 0
        for session in sessions {
            guard let id = session.id else { continue }
            let matchedRule = CategorizationEngine.bestMatch(
                rules: rules,
                bundleId: session.appBundleId,
                windowTitle: session.windowTitle
            )
            let categoryId: Int64? = matchedRule.flatMap { categoryMap[$0.categoryId] != nil ? $0.categoryId : nil }
            try pool.write { db in
                try db.execute(
                    sql: "UPDATE activity_sessions SET category_id = ? WHERE id = ?",
                    arguments: [categoryId, id]
                )
            }
            count += 1
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
