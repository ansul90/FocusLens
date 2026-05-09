import Foundation
import GRDB

enum Migration002_Categories {
    static let identifier = "v2_categories"

    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                color_hex TEXT NOT NULL,
                is_productive INTEGER NOT NULL DEFAULT 0
            )
            """)

        try db.execute(sql: """
            CREATE TABLE category_rules (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
                match_type TEXT NOT NULL,
                match_value TEXT NOT NULL,
                priority INTEGER NOT NULL DEFAULT 0
            )
            """)

        try db.execute(sql: """
            CREATE INDEX category_rules_category_id ON category_rules(category_id)
            """)

        try db.execute(sql: """
            ALTER TABLE activity_sessions ADD COLUMN category_id INTEGER REFERENCES categories(id)
            """)

        try db.execute(sql: """
            CREATE INDEX activity_sessions_category_id
            ON activity_sessions(category_id)
            """)
        // Seeding is intentionally absent: Migration003 unconditionally replaces all
        // categories and rules, so any rows inserted here would be immediately deleted.
        // Canonical seeds live entirely in Migration003_SeedRules.
    }
}
