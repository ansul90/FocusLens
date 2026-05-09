import GRDB

struct Migration008_CategoryOverrides {
    static let identifier = "008_category_overrides"

    static func migrate(_ db: Database) throws {
        try db.create(table: "category_overrides", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("app_bundle_id", .text).notNull().unique()
            t.column("category_id", .integer).notNull().references("categories", onDelete: .cascade)
            t.column("created_at", .text).notNull()
                .defaults(sql: "(strftime('%Y-%m-%d %H:%M:%f', 'now'))")
        }
    }
}
