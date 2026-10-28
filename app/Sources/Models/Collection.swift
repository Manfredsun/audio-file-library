import Foundation
import GRDB

/// 虛擬資料夾。磁碟上什麼都不會變——這是一份名單，不是一個目錄。
struct Collection: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Hashable {
    static let databaseTableName = "collections"

    var id: Int64?
    var name: String
    var createdAt: Date
    /// 分頁列上的左右順序。
    var position: Int
    var updatedAt: Date?

    init(id: Int64? = nil,
         name: String,
         createdAt: Date = Date(),
         position: Int = 0,
         updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.position = position
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
        case position
        case updatedAt = "updated_at"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let position = Column(CodingKeys.position)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// 分頁的成員。
///
/// `sortOrder` 是使用者手動排出來的順序，程式不得自作聰明重排。
struct CollectionSound: Codable, FetchableRecord, PersistableRecord, Equatable, Hashable {
    static let databaseTableName = "collection_sounds"

    var collectionId: Int64
    var soundId: Int64
    var sortOrder: Int
    var addedAt: Date?

    init(collectionId: Int64, soundId: Int64, sortOrder: Int, addedAt: Date? = Date()) {
        self.collectionId = collectionId
        self.soundId = soundId
        self.sortOrder = sortOrder
        self.addedAt = addedAt
    }

    enum CodingKeys: String, CodingKey {
        case collectionId = "collection_id"
        case soundId = "sound_id"
        case sortOrder = "sort_order"
        case addedAt = "added_at"
    }

    enum Columns {
        static let collectionId = Column(CodingKeys.collectionId)
        static let soundId = Column(CodingKeys.soundId)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }
}
