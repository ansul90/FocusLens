import Foundation
import GRDB

enum Migration004_FixAITools {
    static let identifier = "v4_fix_ai_tools"

    static func migrate(_ db: Database) throws {
        // Defensive repair for installations where the AI Tools category row (id=10)
        // was absent from the categories table while category_rules still referenced it.
        // This can happen if the user manually edited the database, or if a future schema
        // change shifts autoincrement IDs. On a clean install (Migration003 runs in full)
        // this guard exits immediately because the row already exists.
        let count = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM categories WHERE id = 10"
        ) ?? 0
        guard count == 0 else { return }

        try db.execute(
            sql: "INSERT INTO categories (id, name, color_hex, is_productive) VALUES (10, 'AI Tools', '#2196F3', 2)"
        )
    }
}
