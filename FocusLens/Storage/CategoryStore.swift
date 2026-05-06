import Foundation
import GRDB

enum CategoryStoreError: Error {
    case missingPrimaryKey
}

struct CategoryStore: Sendable {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    // MARK: - Categories

    func fetchAllCategories() throws -> [Category] {
        try dbPool.read { db in
            try Category.order(Category.Columns.name).fetchAll(db)
        }
    }

    func insert(_ category: Category) throws -> Category {
        var mutable = category
        try dbPool.write { db in try mutable.insert(db) }
        return mutable
    }

    func update(_ category: Category) throws {
        guard category.id != nil else { throw CategoryStoreError.missingPrimaryKey }
        try dbPool.write { db in try category.update(db) }
    }

    func deleteCategory(id: Int64) throws {
        try dbPool.write { db in
            try Category.filter(Category.Columns.id == id).deleteAll(db)
        }
    }

    // MARK: - Rules

    func fetchRules(for categoryId: Int64) throws -> [CategoryRule] {
        try dbPool.read { db in
            try CategoryRule
                .filter(CategoryRule.Columns.categoryId == categoryId)
                .order(CategoryRule.Columns.priority.desc)
                .fetchAll(db)
        }
    }

    func fetchAllRulesOrdered() throws -> [CategoryRule] {
        try dbPool.read { db in
            try CategoryRule.order(CategoryRule.Columns.priority.desc).fetchAll(db)
        }
    }

    func insert(_ rule: CategoryRule) throws -> CategoryRule {
        var mutable = rule
        try dbPool.write { db in try mutable.insert(db) }
        return mutable
    }

    func update(_ rule: CategoryRule) throws {
        guard rule.id != nil else { throw CategoryStoreError.missingPrimaryKey }
        try dbPool.write { db in try rule.update(db) }
    }

    func deleteRule(id: Int64) throws {
        try dbPool.write { db in
            try CategoryRule.filter(CategoryRule.Columns.id == id).deleteAll(db)
        }
    }
}
