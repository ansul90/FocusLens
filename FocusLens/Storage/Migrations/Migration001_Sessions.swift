import Foundation
import GRDB

enum Migration001_Sessions {
    static let identifier = "v1_sessions"

    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE activity_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app_bundle_id TEXT NOT NULL,
                app_name TEXT NOT NULL,
                window_title TEXT,
                started_at TEXT NOT NULL,
                ended_at TEXT,
                duration_seconds REAL,
                is_idle INTEGER NOT NULL DEFAULT 0
            )
            """)

        try db.execute(sql: """
            CREATE INDEX activity_sessions_started_at
            ON activity_sessions(started_at)
            """)

        try db.execute(sql: """
            CREATE INDEX activity_sessions_app_bundle_id
            ON activity_sessions(app_bundle_id)
            """)

        try db.execute(sql: """
            CREATE TABLE never_track_apps (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app_bundle_id TEXT UNIQUE NOT NULL,
                added_at TEXT NOT NULL
            )
            """)
    }
}
