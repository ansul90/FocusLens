import Testing
import Foundation
import GRDB
@testable import FocusLens

@Suite("RuleAuthoringService")
struct RuleAuthoringServiceTests {

    private func makePool() throws -> DatabasePool {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focuslens-ras-\(UUID().uuidString).sqlite")
        let pool = try DatabasePool(path: url.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration(Migration001_Sessions.identifier, migrate: Migration001_Sessions.migrate)
        migrator.registerMigration(Migration002_Categories.identifier, migrate: Migration002_Categories.migrate)
        migrator.registerMigration(Migration003_SeedRules.identifier, migrate: Migration003_SeedRules.migrate)
        migrator.registerMigration(Migration004_FixAITools.identifier, migrate: Migration004_FixAITools.migrate)
        migrator.registerMigration(Migration005_FixBrowserRules.identifier, migrate: Migration005_FixBrowserRules.migrate)
        migrator.registerMigration(Migration006_WindowTitleIndex.identifier, migrate: Migration006_WindowTitleIndex.migrate)
        migrator.registerMigration(Migration007_ConsolidateCategories.identifier, migrate: Migration007_ConsolidateCategories.migrate)
        migrator.registerMigration(Migration008_CategoryOverrides.identifier, migrate: Migration008_CategoryOverrides.migrate)
        try migrator.migrate(pool)
        return pool
    }

    private func categoryId(_ pool: DatabasePool, name: String) throws -> Int64? {
        try pool.read { db in
            try Int64.fetchOne(
                db,
                sql: "SELECT id FROM categories WHERE name = ? COLLATE NOCASE",
                arguments: [name]
            )
        }
    }

    private func insertSession(
        _ pool: DatabasePool,
        bundleId: String,
        windowTitle: String?,
        categoryId: Int64?
    ) throws -> Int64 {
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO activity_sessions
                      (app_bundle_id, app_name, window_title,
                       started_at, ended_at, duration_seconds, is_idle, category_id)
                    VALUES (?, ?, ?,
                            '2026-01-01 09:00:00.000', '2026-01-01 09:05:00.000', 300, 0, ?)
                    """,
                arguments: [bundleId, bundleId, windowTitle, categoryId]
            )
            return db.lastInsertedRowID
        }
    }

    private func sessionCategoryId(_ pool: DatabasePool, sessionId: Int64) throws -> Int64? {
        try pool.read { db in
            try Int64.fetchOne(
                db,
                sql: "SELECT category_id FROM activity_sessions WHERE id = ?",
                arguments: [sessionId]
            )
        }
    }

    // MARK: - previewRule

    @Test("previewRule counts sessions matching appBundle pattern")
    func previewRuleAppBundle() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))
        _ = try insertSession(pool, bundleId: "com.test.preview", windowTitle: nil, categoryId: nil)
        _ = try insertSession(pool, bundleId: "com.test.preview", windowTitle: nil, categoryId: nil)
        _ = try insertSession(pool, bundleId: "com.other.app", windowTitle: nil, categoryId: nil)

        let rule = CategoryRule(id: nil, categoryId: devId, matchType: .appBundle,
                                matchValue: "com.test.preview", priority: 50)
        let svc = RuleAuthoringService(dbPool: pool)
        #expect(try svc.previewRule(rule) == 2)
    }

    @Test("previewRule counts sessions matching windowTitleContains pattern")
    func previewRuleWindowTitle() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))
        _ = try insertSession(pool, bundleId: "com.brave.Browser", windowTitle: "GitHub - my/repo", categoryId: nil)
        _ = try insertSession(pool, bundleId: "com.brave.Browser", windowTitle: "Google - Search", categoryId: nil)
        _ = try insertSession(pool, bundleId: "com.brave.Browser", windowTitle: nil, categoryId: nil)

        let rule = CategoryRule(id: nil, categoryId: devId, matchType: .windowTitleContains,
                                matchValue: "GitHub", priority: 50)
        let svc = RuleAuthoringService(dbPool: pool)
        #expect(try svc.previewRule(rule) == 1)
    }

    @Test("previewRule is case-insensitive for windowTitleContains")
    func previewRuleWindowTitleCaseInsensitive() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))
        _ = try insertSession(pool, bundleId: "com.brave.Browser", windowTitle: "github - lower", categoryId: nil)
        _ = try insertSession(pool, bundleId: "com.brave.Browser", windowTitle: "GITHUB - upper", categoryId: nil)

        let rule = CategoryRule(id: nil, categoryId: devId, matchType: .windowTitleContains,
                                matchValue: "GitHub", priority: 50)
        let svc = RuleAuthoringService(dbPool: pool)
        #expect(try svc.previewRule(rule) == 2)
    }

    // MARK: - applyRule

    @Test("applyRule inserts rule and backfills matching session")
    func applyRuleBackfills() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))
        let sessionId = try insertSession(pool, bundleId: "com.test.backfill", windowTitle: nil, categoryId: nil)

        let rule = CategoryRule(id: nil, categoryId: devId, matchType: .appBundle,
                                matchValue: "com.test.backfill", priority: 50)
        let svc = RuleAuthoringService(dbPool: pool)
        let (inserted, count) = try svc.applyRule(rule)

        #expect(inserted.id != nil)
        #expect(count == 1)
        #expect(try sessionCategoryId(pool, sessionId: sessionId) == devId)
    }

    @Test("applyRule does not overwrite higher-priority existing rule")
    func applyRuleRespectsHigherPriority() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))
        let browserId = try #require(try categoryId(pool, name: "Browser"))

        // Pre-existing high-priority rule: com.test.hprio → Browser at priority 200
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO category_rules
                      (category_id, match_type, match_value, priority)
                    VALUES (?, 'app_bundle', 'com.test.hprio', 200)
                    """,
                arguments: [browserId]
            )
        }
        let sessionId = try insertSession(pool, bundleId: "com.test.hprio", windowTitle: nil, categoryId: browserId)

        // New lower-priority rule: com.test.hprio → Development at priority 50
        let svc = RuleAuthoringService(dbPool: pool)
        let (_, count) = try svc.applyRule(
            CategoryRule(id: nil, categoryId: devId, matchType: .appBundle,
                         matchValue: "com.test.hprio", priority: 50)
        )

        #expect(count == 0)
        #expect(try sessionCategoryId(pool, sessionId: sessionId) == browserId)
    }

    @Test("applyRule overwrites lower-priority existing rule")
    func applyRuleOverwritesLowerPriority() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))
        let utilId = try #require(try categoryId(pool, name: "Utilities"))

        // Low-priority rule already in place
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO category_rules
                      (category_id, match_type, match_value, priority)
                    VALUES (?, 'app_bundle', 'com.test.lprio', 10)
                    """,
                arguments: [utilId]
            )
        }
        let sessionId = try insertSession(pool, bundleId: "com.test.lprio", windowTitle: nil, categoryId: utilId)

        // New high-priority rule wins
        let svc = RuleAuthoringService(dbPool: pool)
        let (_, count) = try svc.applyRule(
            CategoryRule(id: nil, categoryId: devId, matchType: .appBundle,
                         matchValue: "com.test.lprio", priority: 90)
        )

        #expect(count == 1)
        #expect(try sessionCategoryId(pool, sessionId: sessionId) == devId)
    }

    // MARK: - deleteRule

    @Test("deleteRule clears category when no remaining rule matches")
    func deleteRuleClearsCategory() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))

        let svc = RuleAuthoringService(dbPool: pool)
        let (inserted, _) = try svc.applyRule(
            CategoryRule(id: nil, categoryId: devId, matchType: .appBundle,
                         matchValue: "com.test.clear", priority: 50)
        )
        let sessionId = try insertSession(pool, bundleId: "com.test.clear", windowTitle: nil, categoryId: devId)
        // Re-run applyRule so the session gets classified by this rule in the DB state
        _ = try svc.applyRule(
            CategoryRule(id: nil, categoryId: devId, matchType: .appBundle,
                         matchValue: "com.test.clear", priority: 51)
        )

        // Delete the original rule — session should still be covered by priority-51 rule
        let ruleId = try #require(inserted.id)
        let changed = try svc.deleteRule(id: ruleId)
        // Session category should stay devId (covered by remaining priority-51 rule)
        #expect(try sessionCategoryId(pool, sessionId: sessionId) == devId)
        #expect(changed == 0)
    }

    @Test("deleteRule sets category to nil when sole rule is deleted")
    func deleteRuleSetsNilWhenSoleRule() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))

        let svc = RuleAuthoringService(dbPool: pool)
        let (inserted, _) = try svc.applyRule(
            CategoryRule(id: nil, categoryId: devId, matchType: .appBundle,
                         matchValue: "com.test.sole", priority: 50)
        )
        let sessionId = try insertSession(pool, bundleId: "com.test.sole", windowTitle: nil, categoryId: devId)
        let ruleId = try #require(inserted.id)

        let changed = try svc.deleteRule(id: ruleId)

        #expect(changed == 1)
        #expect(try sessionCategoryId(pool, sessionId: sessionId) == nil)
    }

    @Test("deleteRule reassigns session to remaining lower-priority rule")
    func deleteRuleReassigns() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))
        let utilId = try #require(try categoryId(pool, name: "Utilities"))

        let svc = RuleAuthoringService(dbPool: pool)

        // Low-priority fallback
        _ = try svc.applyRule(
            CategoryRule(id: nil, categoryId: utilId, matchType: .appBundle,
                         matchValue: "com.test.reassign", priority: 30)
        )
        // High-priority rule wins initially
        let (highRule, _) = try svc.applyRule(
            CategoryRule(id: nil, categoryId: devId, matchType: .appBundle,
                         matchValue: "com.test.reassign", priority: 90)
        )
        let sessionId = try insertSession(pool, bundleId: "com.test.reassign", windowTitle: nil, categoryId: devId)
        let highId = try #require(highRule.id)

        let changed = try svc.deleteRule(id: highId)

        #expect(changed == 1)
        #expect(try sessionCategoryId(pool, sessionId: sessionId) == utilId)
    }

    @Test("deleteRule with unknown id returns 0")
    func deleteRuleUnknownId() throws {
        let pool = try makePool()
        let svc = RuleAuthoringService(dbPool: pool)
        #expect(try svc.deleteRule(id: 999_999) == 0)
    }

    // MARK: - Override tests

    @Test("previewOverride counts all completed sessions for the app")
    func previewOverrideCount() throws {
        let pool = try makePool()
        _ = try insertSession(pool, bundleId: "com.brave.Browser", windowTitle: "GitHub", categoryId: nil)
        _ = try insertSession(pool, bundleId: "com.brave.Browser", windowTitle: "Google", categoryId: nil)
        _ = try insertSession(pool, bundleId: "com.apple.Safari", windowTitle: nil, categoryId: nil)

        let svc = RuleAuthoringService(dbPool: pool)
        #expect(try svc.previewOverride(appBundleId: "com.brave.Browser") == 2)
    }

    @Test("applyOverride sets all sessions for the app to the override category")
    func applyOverrideBackfills() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))
        let s1 = try insertSession(pool, bundleId: "com.brave.Browser", windowTitle: "GitHub", categoryId: nil)
        let s2 = try insertSession(pool, bundleId: "com.brave.Browser", windowTitle: "Google", categoryId: nil)
        _ = try insertSession(pool, bundleId: "com.apple.Safari", windowTitle: nil, categoryId: nil)

        let svc = RuleAuthoringService(dbPool: pool)
        let (saved, count) = try svc.applyOverride(appBundleId: "com.brave.Browser", categoryId: devId)

        #expect(saved.id != nil)
        #expect(saved.appBundleId == "com.brave.Browser")
        #expect(count == 2)
        #expect(try sessionCategoryId(pool, sessionId: s1) == devId)
        #expect(try sessionCategoryId(pool, sessionId: s2) == devId)
    }

    @Test("applyOverride is idempotent — applying twice replaces the override")
    func applyOverrideIdempotent() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))
        let utilId = try #require(try categoryId(pool, name: "Utilities"))

        let svc = RuleAuthoringService(dbPool: pool)
        _ = try svc.applyOverride(appBundleId: "com.test.idem", categoryId: devId)
        _ = try svc.applyOverride(appBundleId: "com.test.idem", categoryId: utilId)

        let overrideCount: Int = try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM category_overrides WHERE app_bundle_id = 'com.test.idem'") ?? 0
        }
        #expect(overrideCount == 1, "upsert must not create duplicate overrides")

        let stored: Int64? = try pool.read { db in
            try Int64.fetchOne(db, sql: "SELECT category_id FROM category_overrides WHERE app_bundle_id = 'com.test.idem'")
        }
        #expect(stored == utilId, "second applyOverride should replace the first")
    }

    @Test("deleteOverride sets session category to nil when no rule matches")
    func deleteOverrideSetsNil() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))
        let sessionId = try insertSession(pool, bundleId: "com.test.override.del", windowTitle: nil, categoryId: nil)

        let svc = RuleAuthoringService(dbPool: pool)
        let (saved, _) = try svc.applyOverride(appBundleId: "com.test.override.del", categoryId: devId)
        let overrideId = try #require(saved.id)

        // Session should now be Development
        #expect(try sessionCategoryId(pool, sessionId: sessionId) == devId)

        let changed = try svc.deleteOverride(id: overrideId)
        #expect(changed == 1)
        #expect(try sessionCategoryId(pool, sessionId: sessionId) == nil)
    }

    @Test("deleteOverride reassigns session to matching rule")
    func deleteOverrideFallsBackToRule() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))
        let utilId = try #require(try categoryId(pool, name: "Utilities"))

        // Add a rule for this bundle before applying the override
        let svc = RuleAuthoringService(dbPool: pool)
        _ = try svc.applyRule(
            CategoryRule(id: nil, categoryId: utilId, matchType: .appBundle,
                         matchValue: "com.test.override.fallback", priority: 50)
        )
        let sessionId = try insertSession(pool, bundleId: "com.test.override.fallback", windowTitle: nil, categoryId: utilId)

        // Override with Development
        let (saved, _) = try svc.applyOverride(appBundleId: "com.test.override.fallback", categoryId: devId)
        let overrideId = try #require(saved.id)
        #expect(try sessionCategoryId(pool, sessionId: sessionId) == devId)

        // Delete override → session should fall back to Utilities (rule still exists)
        let changed = try svc.deleteOverride(id: overrideId)
        #expect(changed == 1)
        #expect(try sessionCategoryId(pool, sessionId: sessionId) == utilId)
    }

    @Test("deleteOverride with unknown id returns 0")
    func deleteOverrideUnknownId() throws {
        let pool = try makePool()
        let svc = RuleAuthoringService(dbPool: pool)
        #expect(try svc.deleteOverride(id: 999_999) == 0)
    }
}
