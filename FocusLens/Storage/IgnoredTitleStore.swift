import Foundation
import GRDB

struct IgnoredTitleStore {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    func add(bundleId: String, title: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO ignored_browser_titles(app_bundle_id, window_title, added_at) VALUES (?, ?, datetime('now'))",
                arguments: [bundleId, title]
            )
        }
    }

    func remove(bundleId: String, title: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM ignored_browser_titles WHERE app_bundle_id = ? AND window_title = ?",
                arguments: [bundleId, title]
            )
        }
    }

    func fetchAll() throws -> Set<String> {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT app_bundle_id, window_title FROM ignored_browser_titles"
            )
            return Set(rows.compactMap { row -> String? in
                guard let b: String = row["app_bundle_id"], let t: String = row["window_title"] else { return nil }
                return "\(b)|\(t)"
            })
        }
    }
}
