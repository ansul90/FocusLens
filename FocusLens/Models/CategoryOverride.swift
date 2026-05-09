import Foundation
import GRDB

struct CategoryOverride: Codable, Identifiable, Hashable, Sendable {
    var id: Int64?
    let appBundleId: String
    let categoryId: Int64
    var createdAt: Date

    init(id: Int64? = nil, appBundleId: String, categoryId: Int64, createdAt: Date = Date()) {
        self.id = id
        self.appBundleId = appBundleId
        self.categoryId = categoryId
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case appBundleId = "app_bundle_id"
        case categoryId = "category_id"
        case createdAt = "created_at"
    }
}

extension CategoryOverride: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "category_overrides"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let appBundleId = Column(CodingKeys.appBundleId)
        static let categoryId = Column(CodingKeys.categoryId)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
