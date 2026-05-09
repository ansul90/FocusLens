import Testing
import Foundation
import GRDB
@testable import FocusLens

@Suite("Migration008_CategoryOverrides")
struct Migration008Tests {

    private func makePool() throws -> DatabasePool {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focuslens-mig008-\(UUID().uuidString).sqlite")
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
            try Int64.fetchOne(db, sql: "SELECT id FROM categories WHERE name = ? COLLATE NOCASE", arguments: [name])
        }
    }

    @Test("creates category_overrides table")
    func tableExists() throws {
        let pool = try makePool()
        let exists: Bool = try pool.read { db in
            try db.tableExists("category_overrides")
        }
        #expect(exists)
    }

    @Test("table has expected columns")
    func tableColumns() throws {
        let pool = try makePool()
        let columns = try pool.read { db in
            try db.columns(in: "category_overrides").map { $0.name }
        }
        #expect(columns.contains("id"))
        #expect(columns.contains("app_bundle_id"))
        #expect(columns.contains("category_id"))
        #expect(columns.contains("created_at"))
    }

    @Test("app_bundle_id is unique — second insert replaces first")
    func uniqueAppBundleIdReplaces() throws {
        let pool = try makePool()
        let devId = try #require(try categoryId(pool, name: "Development"))
        let browserId = try #require(try categoryId(pool, name: "Browser"))

        try pool.write { db in
            try db.execute(
                sql: "INSERT INTO category_overrides (app_bundle_id, category_id) VALUES ('com.test.app', ?)",
                arguments: [devId]
            )
            try db.execute(
                sql: "INSERT OR REPLACE INTO category_overrides (app_bundle_id, category_id) VALUES ('com.test.app', ?)",
                arguments: [browserId]
            )
        }

        let count: Int = try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM category_overrides WHERE app_bundle_id = 'com.test.app'") ?? 0
        }
        #expect(count == 1, "UNIQUE constraint should allow only one override per app")

        let storedCategoryId: Int64? = try pool.read { db in
            try Int64.fetchOne(db, sql: "SELECT category_id FROM category_overrides WHERE app_bundle_id = 'com.test.app'")
        }
        #expect(storedCategoryId == browserId, "latest insert should win")
    }

    @Test("running migration twice is idempotent")
    func idempotent() throws {
        let pool = try makePool()
        try pool.write { db in try Migration008_CategoryOverrides.migrate(db) }
        let exists: Bool = try pool.read { db in try db.tableExists("category_overrides") }
        #expect(exists)
    }
}
