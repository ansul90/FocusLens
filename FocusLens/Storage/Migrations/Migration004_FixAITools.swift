import Foundation
import GRDB

enum Migration004_FixAITools {
    static let identifier = "v4_fix_ai_tools"

    static func migrate(_ db: Database) throws {
        // Migration003 inserted rules pointing to category_id = 10 (AI Tools)
        // but the categories row was never committed, leaving a dangling FK reference.
        // Re-insert the missing row with an explicit id so existing rules still resolve.
        let count = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM categories WHERE id = 10"
        ) ?? 0
        guard count == 0 else { return }

        try db.execute(
            sql: "INSERT INTO categories (id, name, color_hex, is_productive) VALUES (10, 'AI Tools', '#2196F3', 2)"
        )
    }
}
