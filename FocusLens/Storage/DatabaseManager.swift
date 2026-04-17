import Foundation
import GRDB

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    let dbPool: DatabasePool

    private init() {
        do {
            try FileManager.default.createDirectory(
                at: AppConstants.appSupportDirectory,
                withIntermediateDirectories: true
            )
            var config = Configuration()
            config.busyMode = .timeout(5)
            let pool = try DatabasePool(path: AppConstants.databaseURL.path, configuration: config)
            var migrator = DatabaseMigrator()
            migrator.registerMigration(Migration001_Sessions.identifier, migrate: Migration001_Sessions.migrate)
            migrator.registerMigration(Migration002_Categories.identifier, migrate: Migration002_Categories.migrate)
            migrator.registerMigration(Migration003_SeedRules.identifier, migrate: Migration003_SeedRules.migrate)
            try migrator.migrate(pool)
            try pool.write { try $0.execute(sql: "PRAGMA journal_mode=WAL") }
            dbPool = pool
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }
}
