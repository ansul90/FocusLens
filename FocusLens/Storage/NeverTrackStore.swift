import Foundation
import GRDB

struct NeverTrackStore {
    struct NeverTrackApp: Codable, FetchableRecord, MutablePersistableRecord {
        var id: Int64?
        let appBundleId: String
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

    func add(bundleId: String) throws {
        var record = NeverTrackApp(id: nil, appBundleId: bundleId, addedAt: Date())
        try dbPool.write { db in
            try record.insert(db)
        }
    }

    func remove(bundleId: String) throws {
        try dbPool.write { db in
            try NeverTrackApp
                .filter(Column("app_bundle_id") == bundleId)
                .deleteAll(db)
        }
    }

    func fetchAll() throws -> [String] {
        try dbPool.read { db in
            try NeverTrackApp.fetchAll(db).map(\.appBundleId)
        }
    }

    func contains(bundleId: String) throws -> Bool {
        try dbPool.read { db in
            try NeverTrackApp
                .filter(Column("app_bundle_id") == bundleId)
                .fetchCount(db) > 0
        }
    }
}
