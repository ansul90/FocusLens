import Foundation
import GRDB
import os

// @unchecked Sendable: DatabasePool is thread-safe by design (GRDB guarantee).
// dbPool is written once in init and never mutated. checkpointTimer is only
// accessed from the main run loop, so there are no concurrent mutations.
final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    let dbPool: DatabasePool
    private var checkpointTimer: Timer?
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "DatabaseManager")

    private init() {
        do {
            try FileManager.default.createDirectory(
                at: AppConstants.appSupportDirectory,
                withIntermediateDirectories: true
            )
            var config = Configuration()
            config.busyMode = .timeout(5)
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }
            let pool = try DatabasePool(path: AppConstants.databaseURL.path, configuration: config)
            var migrator = DatabaseMigrator()
            migrator.registerMigration(Migration001_Sessions.identifier, migrate: Migration001_Sessions.migrate)
            migrator.registerMigration(Migration002_Categories.identifier, migrate: Migration002_Categories.migrate)
            migrator.registerMigration(Migration003_SeedRules.identifier, migrate: Migration003_SeedRules.migrate)
            migrator.registerMigration(Migration004_FixAITools.identifier, migrate: Migration004_FixAITools.migrate)
            migrator.registerMigration(Migration005_FixBrowserRules.identifier, migrate: Migration005_FixBrowserRules.migrate)
            migrator.registerMigration(Migration006_WindowTitleIndex.identifier, migrate: Migration006_WindowTitleIndex.migrate)
            migrator.registerMigration(Migration007_ConsolidateCategories.identifier, migrate: Migration007_ConsolidateCategories.migrate)
            migrator.registerMigration(Migration008_CategoryOverrides.identifier, migrate: Migration008_CategoryOverrides.migrate)
            migrator.registerMigration(Migration009_BumpLearningScore.identifier, migrate: Migration009_BumpLearningScore.migrate)
            migrator.registerMigration(Migration010_NeverTrackTitlesAndIgnored.identifier, migrate: Migration010_NeverTrackTitlesAndIgnored.migrate)
            try migrator.migrate(pool)
            try pool.write { try $0.execute(sql: "PRAGMA journal_mode=WAL") }
            dbPool = pool
        } catch {
            fatalError("Failed to open database: \(error)")
        }
        scheduleCheckpoint()
    }

    private func scheduleCheckpoint() {
        let timer = Timer(
            timeInterval: AppConstants.walCheckpointIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            self?.checkpoint()
        }
        RunLoop.main.add(timer, forMode: .common)
        checkpointTimer = timer
    }

    private func checkpoint() {
        do {
            try dbPool.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }
            logger.debug("WAL checkpoint completed")
        } catch {
            logger.error("WAL checkpoint failed: \(error.localizedDescription)")
        }
    }
}
