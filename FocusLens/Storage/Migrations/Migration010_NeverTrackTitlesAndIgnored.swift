import Foundation
import GRDB

enum Migration010_NeverTrackTitlesAndIgnored {
    static let identifier = "v10_never_track_titles_and_ignored"

    static func migrate(_ db: Database) throws {
        // Recreate never_track_apps: original has UNIQUE on app_bundle_id alone,
        // which prevents multiple title-level rows per app. Drop and rebuild with
        // a composite expression index instead.
        try db.execute(sql: """
            CREATE TABLE never_track_apps_new (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                app_bundle_id TEXT NOT NULL,
                window_title  TEXT,
                added_at      TEXT NOT NULL
            )
            """)
        try db.execute(sql: """
            INSERT INTO never_track_apps_new (id, app_bundle_id, added_at)
            SELECT id, app_bundle_id, added_at FROM never_track_apps
            """)
        try db.execute(sql: "DROP TABLE never_track_apps")
        try db.execute(sql: "ALTER TABLE never_track_apps_new RENAME TO never_track_apps")
        // NULL window_title = app-level block; non-NULL = title-level block.
        try db.execute(sql: """
            CREATE UNIQUE INDEX idx_never_track_apps_bundle_title
            ON never_track_apps(app_bundle_id, COALESCE(window_title, ''))
            """)

        try db.execute(sql: """
            CREATE TABLE ignored_browser_titles (
                app_bundle_id TEXT NOT NULL,
                window_title  TEXT NOT NULL,
                added_at      TEXT NOT NULL,
                PRIMARY KEY (app_bundle_id, window_title)
            )
            """)
    }
}
