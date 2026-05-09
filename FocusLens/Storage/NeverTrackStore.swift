import Foundation
import GRDB

struct NeverTrackStore {
    struct NeverTrackApp: Codable, FetchableRecord, MutablePersistableRecord {
        var id: Int64?
        let appBundleId: String
        let windowTitle: String?
        let addedAt: Date

        static let databaseTableName = "never_track_apps"

        mutating func didInsert(_ inserted: InsertionSuccess) {
            id = inserted.rowID
        }
    }

    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    // MARK: - App-level (existing behaviour, window_title = NULL)

    func add(bundleId: String) throws {
        var record = NeverTrackApp(id: nil, appBundleId: bundleId, windowTitle: nil, addedAt: Date())
        try dbPool.write { db in
            try record.insert(db)
        }
    }

    func remove(bundleId: String) throws {
        try dbPool.write { db in
            try NeverTrackApp
                .filter(Column("app_bundle_id") == bundleId && Column("window_title") == nil)
                .deleteAll(db)
        }
    }

    func fetchAll() throws -> [String] {
        try dbPool.read { db in
            try NeverTrackApp
                .filter(Column("window_title") == nil)
                .fetchAll(db)
                .map(\.appBundleId)
        }
    }

    func contains(bundleId: String) throws -> Bool {
        try dbPool.read { db in
            try NeverTrackApp
                .filter(Column("app_bundle_id") == bundleId && Column("window_title") == nil)
                .fetchCount(db) > 0
        }
    }

    // MARK: - Title-level (window_title IS NOT NULL)

    func addTitle(bundleId: String, title: String) throws {
        var record = NeverTrackApp(id: nil, appBundleId: bundleId, windowTitle: title, addedAt: Date())
        try dbPool.write { db in
            try record.insert(db)
        }
    }

    func removeTitle(bundleId: String, title: String) throws {
        try dbPool.write { db in
            try NeverTrackApp
                .filter(Column("app_bundle_id") == bundleId && Column("window_title") == title)
                .deleteAll(db)
        }
    }

    func containsTitle(bundleId: String, title: String) throws -> Bool {
        try dbPool.read { db in
            try NeverTrackApp
                .filter(Column("app_bundle_id") == bundleId && Column("window_title") == title)
                .fetchCount(db) > 0
        }
    }

    func fetchAllTitles() throws -> [(appBundleId: String, windowTitle: String)] {
        try dbPool.read { db in
            try NeverTrackApp
                .filter(Column("window_title") != nil)
                .fetchAll(db)
                .compactMap { app in
                    guard let t = app.windowTitle else { return nil }
                    return (app.appBundleId, t)
                }
        }
    }
}
