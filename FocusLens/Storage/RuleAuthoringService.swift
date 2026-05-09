import Foundation
import GRDB
import os

private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "RuleAuthoringService")

/// Single chokepoint for rule CRUD + session backfill.
/// Every mutation shows how many sessions are affected, then applies atomically.
struct RuleAuthoringService: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    // MARK: - Preview

    /// Returns the count of completed non-idle sessions that match this rule's pattern.
    /// Useful for showing "N sessions will be affected" before committing.
    func previewRule(_ rule: CategoryRule) throws -> Int {
        try dbPool.read { db in
            try candidateSessions(db, for: rule).count
        }
    }

    // MARK: - Apply

    /// Inserts the rule and backfills past sessions where this rule would win over existing rules.
    /// Returns the saved rule (with its new id) and the count of sessions updated.
    @discardableResult
    func applyRule(_ rule: CategoryRule) throws -> (rule: CategoryRule, affectedCount: Int) {
        try dbPool.write { db in
            var inserted = rule
            try inserted.insert(db)

            let allRules = try CategoryRule.order(CategoryRule.Columns.priority.desc).fetchAll(db)
            let candidates = try candidateSessions(db, for: inserted)

            var count = 0
            for session in candidates {
                guard let sessionId = session.id else { continue }
                let winner = CategorizationEngine.bestMatch(
                    rules: allRules, bundleId: session.appBundleId, windowTitle: session.windowTitle
                )
                guard winner?.id == inserted.id else { continue }
                try db.execute(
                    sql: "UPDATE activity_sessions SET category_id = ? WHERE id = ?",
                    arguments: [inserted.categoryId, sessionId]
                )
                count += 1
            }
            logger.info("applyRule '\(inserted.matchValue)' → \(count) sessions updated")
            return (inserted, count)
        }
    }

    // MARK: - Overrides

    /// Returns the count of completed non-idle sessions for this app bundle.
    func previewOverride(appBundleId: String) throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM activity_sessions
                    WHERE app_bundle_id = ? AND is_idle = 0 AND ended_at IS NOT NULL
                    """,
                arguments: [appBundleId]
            ) ?? 0
        }
    }

    /// Upserts an override for the given app and backfills ALL completed sessions for that app.
    /// Returns the saved override and the number of sessions updated.
    @discardableResult
    func applyOverride(appBundleId: String, categoryId: Int64) throws -> (override: CategoryOverride, affectedCount: Int) {
        try dbPool.write { db in
            var override = CategoryOverride(appBundleId: appBundleId, categoryId: categoryId)
            try override.insert(db, onConflict: .replace)

            try db.execute(
                sql: """
                    UPDATE activity_sessions
                    SET category_id = ?
                    WHERE app_bundle_id = ? AND is_idle = 0 AND ended_at IS NOT NULL
                    """,
                arguments: [categoryId, appBundleId]
            )
            let affectedCount = db.changesCount
            logger.info("applyOverride '\(appBundleId)' → \(affectedCount) sessions updated")
            return (override, affectedCount)
        }
    }

    /// Deletes the override and re-evaluates sessions for that app (falling back to rules).
    /// Returns the count of sessions whose category changed.
    @discardableResult
    func deleteOverride(id: Int64) throws -> Int {
        try dbPool.write { db in
            guard let override = try CategoryOverride.fetchOne(db, key: id) else { return 0 }
            try override.delete(db)

            let rules = try CategoryRule.order(CategoryRule.Columns.priority.desc).fetchAll(db)
            let sessions = try ActivitySession
                .filter(ActivitySession.Columns.appBundleId == override.appBundleId)
                .filter(ActivitySession.Columns.isIdle == false)
                .filter(ActivitySession.Columns.endedAt != nil)
                .filter(ActivitySession.Columns.categoryId == override.categoryId)
                .fetchAll(db)

            var count = 0
            for session in sessions {
                guard let sessionId = session.id else { continue }
                let winner = CategorizationEngine.bestMatch(
                    rules: rules, bundleId: session.appBundleId, windowTitle: session.windowTitle
                )
                let newCategoryId: Int64? = winner?.categoryId
                if newCategoryId != override.categoryId {
                    try db.execute(
                        sql: "UPDATE activity_sessions SET category_id = ? WHERE id = ?",
                        arguments: [newCategoryId, sessionId]
                    )
                    count += 1
                }
            }
            logger.info("deleteOverride '\(override.appBundleId)' → \(count) sessions changed")
            return count
        }
    }

    // MARK: - Delete (rules)

    /// Deletes the rule and re-evaluates sessions that were matched by it.
    /// Sessions that had this rule's category and no remaining rule wins get category_id = nil.
    /// Returns the count of sessions whose category changed.
    @discardableResult
    func deleteRule(id: Int64) throws -> Int {
        try dbPool.write { db in
            guard let rule = try CategoryRule.fetchOne(db, key: id) else { return 0 }

            // Only re-evaluate sessions that (a) match this rule's pattern AND
            // (b) currently have this rule's target category — these are the ones at risk.
            let candidates = try candidateSessions(db, for: rule)
                .filter { $0.categoryId == rule.categoryId }

            try rule.delete(db)

            let remaining = try CategoryRule.order(CategoryRule.Columns.priority.desc).fetchAll(db)

            var count = 0
            for session in candidates {
                guard let sessionId = session.id else { continue }
                let winner = CategorizationEngine.bestMatch(
                    rules: remaining, bundleId: session.appBundleId, windowTitle: session.windowTitle
                )
                let newCategoryId: Int64? = winner?.categoryId
                if newCategoryId != rule.categoryId {
                    try db.execute(
                        sql: "UPDATE activity_sessions SET category_id = ? WHERE id = ?",
                        arguments: [newCategoryId, sessionId]
                    )
                    count += 1
                }
            }
            logger.info("deleteRule '\(rule.matchValue)' → \(count) sessions changed")
            return count
        }
    }

    // MARK: - Private

    private func candidateSessions(_ db: Database, for rule: CategoryRule) throws -> [ActivitySession] {
        let base = ActivitySession
            .filter(ActivitySession.Columns.isIdle == false)
            .filter(ActivitySession.Columns.endedAt != nil)

        switch rule.matchType {
        case .appBundle:
            return try base
                .filter(ActivitySession.Columns.appBundleId == rule.matchValue)
                .fetchAll(db)

        case .windowTitleContains:
            let all = try base
                .filter(ActivitySession.Columns.windowTitle != nil)
                .fetchAll(db)
            return all.filter {
                $0.windowTitle?.localizedCaseInsensitiveContains(rule.matchValue) == true
            }

        case .windowTitleRegex:
            guard let regex = try? NSRegularExpression(pattern: rule.matchValue) else { return [] }
            let all = try base
                .filter(ActivitySession.Columns.windowTitle != nil)
                .fetchAll(db)
            return all.filter { session in
                guard let title = session.windowTitle else { return false }
                return regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
            }
        }
    }
}
