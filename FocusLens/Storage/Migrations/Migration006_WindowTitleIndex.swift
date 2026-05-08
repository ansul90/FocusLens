import GRDB

enum Migration006_WindowTitleIndex {
    static let identifier = "v6_window_title_index"

    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_sessions_app_window
            ON activity_sessions(started_at, app_bundle_id, window_title)
            """)
    }
}
