import Foundation
import GRDB

/// 一次 Organizer 分析的紀錄。AI 的輸出只會落在這裡與 `organizer_suggestions`，
/// 永遠不會直接寫進 `sounds` 的 metadata 欄位（DECISIONS D-007）。
struct OrganizerAnalysis: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "organizer_analysis"

    var id: Int64?
    var soundId: Int64
    var engine: String
    var model: String?
    var modelVersion: String?
    var status: OrganizerStatus
    var confidence: Double
    /// 獨立持久化，不由 status 推導（DECISIONS D-004）。
    var needsReview: Bool
    /// 對應 JSON 的 `description`；避開 Swift 的 `description` 命名。
    var summary: String?
    var startedAt: Date
    var completedAt: Date?
    var errorMessage: String?

    init(id: Int64? = nil,
         soundId: Int64,
         engine: String,
         model: String? = nil,
         modelVersion: String? = nil,
         status: OrganizerStatus,
         confidence: Double,
         needsReview: Bool,
         summary: String? = nil,
         startedAt: Date = Date(),
         completedAt: Date? = nil,
         errorMessage: String? = nil) {
        self.id = id
        self.soundId = soundId
        self.engine = engine
        self.model = model
        self.modelVersion = modelVersion
        self.status = status
        self.confidence = confidence
        self.needsReview = needsReview
        self.summary = summary
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case soundId = "sound_id"
        case engine
        case model
        case modelVersion = "model_version"
        case status
        case confidence
        case needsReview = "needs_review"
        case summary = "description"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case errorMessage = "error_message"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let soundId = Column(CodingKeys.soundId)
        static let startedAt = Column(CodingKeys.startedAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// 單一欄位的 AI 建議。使用者按下 Accept 之前，它不具任何權威。
struct OrganizerSuggestion: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "organizer_suggestions"

    enum Field: String, Codable, CaseIterable, Hashable {
        case displayName = "display_name"
        case category
        case subcategory
        case style
        case summary = "description"
        case tag
        case alternativeCategory = "alternative_category"
    }

    enum Status: String, Codable, CaseIterable, Hashable {
        case suggested
        case accepted
        case edited
        case rejected
        case superseded
    }

    var id: Int64?
    var analysisId: Int64
    var field: Field
    var value: String
    var confidence: Double?
    var status: Status

    init(id: Int64? = nil, analysisId: Int64, field: Field, value: String, confidence: Double? = nil, status: Status = .suggested) {
        self.id = id
        self.analysisId = analysisId
        self.field = field
        self.value = value
        self.confidence = confidence
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id
        case analysisId = "analysis_id"
        case field
        case value
        case confidence
        case status
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let analysisId = Column(CodingKeys.analysisId)
        static let field = Column(CodingKeys.field)
        static let status = Column(CodingKeys.status)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
