import Foundation
import GRDB

struct AppInsight: Sendable {
    let appName: String
    let verdict: String    // "productive" | "neutral" | "distracting"
    let summary: String
    let sources: [String]
    let createdAt: String
    let updatedAt: String
}

// MARK: - Actor

actor AppInsightsStore {
    private let dbPool: DatabasePool
    private var tableReady = false

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    func fetch(appName: String) async throws -> AppInsight? {
        try await ensureTableOnce()
        return try await dbPool.read { db in
            guard let row = try Row.fetchOne(db,
                sql: "SELECT app_name, verdict, summary, sources, created_at, updated_at FROM app_insights WHERE app_name = ? COLLATE NOCASE",
                arguments: [appName]) else { return nil }
            let sourcesStr = row["sources"] as? String ?? "[]"
            let sources = (try? JSONDecoder().decode([String].self, from: Data(sourcesStr.utf8))) ?? []
            return AppInsight(
                appName: row["app_name"] ?? appName,
                verdict: row["verdict"] ?? "neutral",
                summary: row["summary"] ?? "",
                sources: sources,
                createdAt: row["created_at"] ?? "",
                updatedAt: row["updated_at"] ?? ""
            )
        }
    }

    func upsert(appName: String, verdict: String, summary: String, sources: [String] = []) async throws {
        try await ensureTableOnce()
        let now = ISO8601DateFormatter().string(from: Date())
        let sourcesJSON = (try? String(data: JSONEncoder().encode(sources), encoding: .utf8)) ?? "[]"
        try await dbPool.write { db in
            try db.execute(sql: """
                INSERT INTO app_insights (app_name, verdict, summary, sources, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(app_name) DO UPDATE SET
                    verdict    = excluded.verdict,
                    summary    = excluded.summary,
                    sources    = excluded.sources,
                    updated_at = excluded.updated_at
                """, arguments: [appName, verdict, summary, sourcesJSON, now, now])
        }
    }

    // MARK: - Private

    private func ensureTableOnce() async throws {
        guard !tableReady else { return }
        try await dbPool.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS app_insights (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    app_name    TEXT    NOT NULL UNIQUE COLLATE NOCASE,
                    verdict     TEXT    NOT NULL CHECK (verdict IN ('productive','neutral','distracting')),
                    summary     TEXT    NOT NULL DEFAULT '',
                    sources     TEXT    NOT NULL DEFAULT '[]',
                    created_at  TEXT    NOT NULL,
                    updated_at  TEXT    NOT NULL
                )
                """)
        }
        tableReady = true
    }
}
