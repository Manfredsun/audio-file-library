import Foundation
import GRDB

/// 受控分類。由 `organizer/schemas/taxonomy.json` seed，執行期的 AI 不得新增。
struct Category: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "categories"

    var id: Int64?
    var name: String
    var parentId: Int64?
    /// 完整路徑，例如 "Foley/Doors"。Organizer 輸出用的就是這個格式。
    var path: String
    var sortOrder: Int

    init(id: Int64? = nil, name: String, parentId: Int64? = nil, path: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.path = path
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentId = "parent_id"
        case path
        case sortOrder = "sort_order"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let path = Column(CodingKeys.path)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
