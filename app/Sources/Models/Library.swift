import Foundation
import GRDB

struct Library: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "libraries"

    enum Availability: String, Codable, CaseIterable {
        case available
        case offline
    }

    var id: Int64?
    var name: String
    var rootPath: String
    var bookmarkData: Data?
    var createdAt: Date
    var lastScannedAt: Date?
    var availabilityStatus: Availability

    init(id: Int64? = nil,
         name: String,
         rootPath: String,
         bookmarkData: Data? = nil,
         createdAt: Date = Date(),
         lastScannedAt: Date? = nil,
         availabilityStatus: Availability = .available) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.bookmarkData = bookmarkData
        self.createdAt = createdAt
        self.lastScannedAt = lastScannedAt
        self.availabilityStatus = availabilityStatus
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case rootPath = "root_path"
        case bookmarkData = "bookmark_data"
        case createdAt = "created_at"
        case lastScannedAt = "last_scanned_at"
        case availabilityStatus = "availability_status"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
