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

        // Seed: Coding
        try db.execute(sql: """
            INSERT INTO categories (name, color_hex, is_productive) VALUES ('Coding', '#5B8CFF', 2)
            """)
        let codingId = db.lastInsertedRowID
        let codingBundles = [
            ("com.apple.dt.Xcode", 100),
            ("com.microsoft.VSCode", 99),
            ("com.jetbrains.intellij", 98),
            ("com.github.atom", 97),
            ("com.sublimetext.4", 96),
            ("io.cursor.Cursor", 95)
        ]
        for (bundle, priority) in codingBundles {
            try db.execute(
                sql: "INSERT INTO category_rules (category_id, match_type, match_value, priority) VALUES (?, 'app_bundle', ?, ?)",
                arguments: [codingId, bundle, priority]
            )
        }

        // Seed: Communication
        try db.execute(sql: """
            INSERT INTO categories (name, color_hex, is_productive) VALUES ('Communication', '#FF9F40', 0)
            """)
        let communicationId = db.lastInsertedRowID
        let communicationBundles = [
            ("com.tinyspeck.slackmacgap", 100),
            ("com.microsoft.teams2", 99),
            ("com.apple.mail", 98),
            ("us.zoom.xos", 97),
            ("com.apple.FaceTime", 96)
        ]
        for (bundle, priority) in communicationBundles {
            try db.execute(
                sql: "INSERT INTO category_rules (category_id, match_type, match_value, priority) VALUES (?, 'app_bundle', ?, ?)",
                arguments: [communicationId, bundle, priority]
            )
        }

        // Seed: Browsing
        try db.execute(sql: """
            INSERT INTO categories (name, color_hex, is_productive) VALUES ('Browsing', '#4ECDC4', -1)
            """)
        let browsingId = db.lastInsertedRowID
        let browsingBundles = [
            ("com.apple.Safari", 100),
            ("com.google.Chrome", 99),
            ("org.mozilla.firefox", 98),
            ("com.microsoft.edgemac", 97)
        ]
        for (bundle, priority) in browsingBundles {
            try db.execute(
                sql: "INSERT INTO category_rules (category_id, match_type, match_value, priority) VALUES (?, 'app_bundle', ?, ?)",
                arguments: [browsingId, bundle, priority]
            )
        }

        // Seed: Design
        try db.execute(sql: """
            INSERT INTO categories (name, color_hex, is_productive) VALUES ('Design', '#FF6B9D', 1)
            """)
        let designId = db.lastInsertedRowID
        let designBundles = [
            ("com.figma.Desktop", 100),
            ("com.adobe.Photoshop", 99),
            ("com.adobe.illustrator", 98),
            ("com.sketch.app", 97)
        ]
        for (bundle, priority) in designBundles {
            try db.execute(
                sql: "INSERT INTO category_rules (category_id, match_type, match_value, priority) VALUES (?, 'app_bundle', ?, ?)",
                arguments: [designId, bundle, priority]
            )
        }

        // Seed: Learning (no bundle rules — AI assigns contextually)
        try db.execute(sql: """
            INSERT INTO categories (name, color_hex, is_productive) VALUES ('Learning', '#C5A3FF', 1)
            """)

        // Seed: Entertainment
        try db.execute(sql: """
            INSERT INTO categories (name, color_hex, is_productive) VALUES ('Entertainment', '#FF6B6B', -2)
            """)
        let entertainmentId = db.lastInsertedRowID
        let entertainmentBundles = [
            ("com.apple.TV", 100),
            ("com.spotify.client", 99),
            ("com.netflix.Netflix", 98)
        ]
        for (bundle, priority) in entertainmentBundles {
            try db.execute(
                sql: "INSERT INTO category_rules (category_id, match_type, match_value, priority) VALUES (?, 'app_bundle', ?, ?)",
                arguments: [entertainmentId, bundle, priority]
            )
        }

        // Seed: Utilities
        try db.execute(sql: """
            INSERT INTO categories (name, color_hex, is_productive) VALUES ('Utilities', '#95A5A6', 0)
            """)
        let utilitiesId = db.lastInsertedRowID
        let utilitiesBundles = [
            ("com.apple.finder", 100),
            ("com.apple.systempreferences", 99),
            ("com.apple.Terminal", 98),
            ("com.googlecode.iterm2", 97)
        ]
        for (bundle, priority) in utilitiesBundles {
            try db.execute(
                sql: "INSERT INTO category_rules (category_id, match_type, match_value, priority) VALUES (?, 'app_bundle', ?, ?)",
                arguments: [utilitiesId, bundle, priority]
            )
        }
    }
}
