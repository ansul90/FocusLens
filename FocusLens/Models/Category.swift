import Foundation
import GRDB

struct Category: Codable, Identifiable, Hashable, Sendable {
    var id: Int64?
    let name: String
    let colorHex: String
    let productivityScore: Int  // -2 (very distracting) to +2 (very productive)

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex = "color_hex"
        case productivityScore = "is_productive"
    }
}

extension Category: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "categories"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let colorHex = Column(CodingKeys.colorHex)
        static let productivityScore = Column(CodingKeys.productivityScore)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
