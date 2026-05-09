import Testing
import Foundation
import GRDB
@testable import FocusLens

@Suite("Migration007_ConsolidateCategories")
struct Migration007Tests {

    private func makePool() throws -> DatabasePool {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focuslens-mig007-\(UUID().uuidString).sqlite")
        let pool = try DatabasePool(path: url.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration(Migration001_Sessions.identifier, migrate: Migration001_Sessions.migrate)
        migrator.registerMigration(Migration002_Categories.identifier, migrate: Migration002_Categories.migrate)
        migrator.registerMigration(Migration003_SeedRules.identifier, migrate: Migration003_SeedRules.migrate)
        migrator.registerMigration(Migration004_FixAITools.identifier, migrate: Migration004_FixAITools.migrate)
        migrator.registerMigration(Migration005_FixBrowserRules.identifier, migrate: Migration005_FixBrowserRules.migrate)
        migrator.registerMigration(Migration006_WindowTitleIndex.identifier, migrate: Migration006_WindowTitleIndex.migrate)
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

    @Test("merges Dev Tools and AI Tools into Development")
    func mergesDevToolsAndAITools() throws {
        let pool = try makePool()
        let devToolsId = try #require(try categoryId(pool, name: "Dev Tools"))
        let aiToolsId = try #require(try categoryId(pool, name: "AI Tools"))
        let devId = try #require(try categoryId(pool, name: "Development"))

        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO activity_sessions
                      (app_bundle_id, app_name, window_title, started_at, ended_at, duration_seconds, is_idle, category_id)
                    VALUES ('com.docker.docker', 'Docker', 'Docker', '2026-01-01 09:00:00.000', '2026-01-01 09:05:00.000', 300, 0, ?)
                    """,
                arguments: [devToolsId]
            )
            try db.execute(
                sql: """
                    INSERT INTO activity_sessions
                      (app_bundle_id, app_name, window_title, started_at, ended_at, duration_seconds, is_idle, category_id)
                    VALUES ('com.electron.ollama', 'Ollama', 'Ollama', '2026-01-01 09:00:00.000', '2026-01-01 09:05:00.000', 300, 0, ?)
                    """,
                arguments: [aiToolsId]
            )
        }

        try pool.write { db in
            try Migration007_ConsolidateCategories.migrate(db)
        }

        #expect(try categoryId(pool, name: "Dev Tools") == nil)
        #expect(try categoryId(pool, name: "AI Tools") == nil)
        #expect(try categoryId(pool, name: "Development") == devId)

        let sessionsInDev: Int = try pool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM activity_sessions WHERE category_id = ?",
                arguments: [devId]
            ) ?? 0
        }
        #expect(sessionsInDev == 2)

        let dockerRulesInDev: Int = try pool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM category_rules
                    WHERE category_id = ? AND match_value = 'com.docker.docker'
                    """,
                arguments: [devId]
            ) ?? 0
        }
        #expect(dockerRulesInDev == 1)
    }

    @Test("renames Media to Entertainment when Entertainment does not exist")
    func renamesMediaToEntertainment() throws {
        let pool = try makePool()
        let mediaId = try #require(try categoryId(pool, name: "Media"))

        try pool.write { db in try Migration007_ConsolidateCategories.migrate(db) }

        #expect(try categoryId(pool, name: "Media") == nil)
        #expect(try categoryId(pool, name: "Entertainment") == mediaId)
    }

    @Test("inserts the 5 new categories")
    func insertsNewCategories() throws {
        let pool = try makePool()
        try pool.write { db in try Migration007_ConsolidateCategories.migrate(db) }

        for name in ["News", "Social", "Shopping", "Finance", "Learning"] {
            #expect(try categoryId(pool, name: name) != nil, "expected category \(name) to exist")
        }
    }

    @Test("inserts meeting title rules at priority 110 routed to Communication")
    func insertsMeetingTitleRules() throws {
        let pool = try makePool()
        try pool.write { db in try Migration007_ConsolidateCategories.migrate(db) }

        let commId = try #require(try categoryId(pool, name: "Communication"))

        let rules: [Row] = try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT match_value, priority FROM category_rules
                    WHERE category_id = ? AND match_type = 'window_title_contains'
                    """,
                arguments: [commId]
            )
        }
        let values = Set(rules.compactMap { $0["match_value"] as String? })
        #expect(values.contains("Google Meet"))
        #expect(values.contains("Zoom Meeting"))
        #expect(values.contains("Microsoft Teams Meeting"))
        for row in rules {
            #expect(row["priority"] as Int? == 110)
        }
    }

    @Test("running migration twice is idempotent")
    func idempotent() throws {
        let pool = try makePool()
        try pool.write { db in try Migration007_ConsolidateCategories.migrate(db) }
        try pool.write { db in try Migration007_ConsolidateCategories.migrate(db) }

        let categoryNames: [String] = try pool.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM categories ORDER BY name")
        }
        #expect(categoryNames.filter { $0.caseInsensitiveCompare("Development") == .orderedSame }.count == 1)
        #expect(categoryNames.filter { $0.caseInsensitiveCompare("Entertainment") == .orderedSame }.count == 1)
        #expect(categoryNames.filter { $0.caseInsensitiveCompare("News") == .orderedSame }.count == 1)

        // Meeting rules should not duplicate either.
        let commId = try #require(try categoryId(pool, name: "Communication"))
        let meetCount: Int = try pool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM category_rules
                    WHERE category_id = ? AND match_type = 'window_title_contains' AND match_value = 'Google Meet'
                    """,
                arguments: [commId]
            ) ?? 0
        }
        #expect(meetCount == 1)
    }
}
