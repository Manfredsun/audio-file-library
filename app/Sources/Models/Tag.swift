import Foundation
import GRDB

struct Tag: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "tags"

    var id: Int64?
    var name: String
    /// 正規化後的名稱，用於同義詞控制（tagging-rules.md §10）。
    var canonicalName: String
    var createdAt: Date

    init(id: Int64? = nil, name: String, canonicalName: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.canonicalName = canonicalName ?? Tag.canonicalize(name)
        self.createdAt = createdAt
    }

    static func canonicalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case canonicalName = "canonical_name"
        case createdAt = "created_at"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let canonicalName = Column(CodingKeys.canonicalName)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct SoundTag: Codable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sound_tags"

    var soundId: Int64
    var tagId: Int64
    var source: MetadataSource
    var confidence: Double?
    /// AI 建議的標籤在使用者接受前為 false。
    var accepted: Bool
    var createdAt: Date

    init(soundId: Int64, tagId: Int64, source: MetadataSource, confidence: Double? = nil, accepted: Bool, createdAt: Date = Date()) {
        self.soundId = soundId
        self.tagId = tagId
        self.source = source
        self.confidence = confidence
        self.accepted = accepted
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case soundId = "sound_id"
        case tagId = "tag_id"
        case source
        case confidence
        case accepted
        case createdAt = "created_at"
    }
}
