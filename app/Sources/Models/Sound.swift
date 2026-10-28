import Foundation
import GRDB

/// 一個音效檔在 App 內的紀錄。
///
/// 重要：`displayName` 是 App metadata，與磁碟上的 `filename` 是兩回事。
/// 編輯 `displayName` 絕不可觸發實體檔案改名（CLAUDE.md §15）。
struct Sound: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "sounds"

    var id: Int64?
    var libraryId: Int64

    // --- 來自檔案系統，唯讀 ---
    var filePath: String
    var relativePath: String
    var folderPath: String
    var filename: String
    var fileExtension: String
    var fileSize: Int64
    var fileIdentifier: String?
    var duration: Double?
    var sampleRate: Int?
    var bitDepth: Int?
    var channelCount: Int?
    var fileCreatedAt: Date?
    var fileModifiedAt: Date?

    // --- App metadata，可編輯，帶 provenance ---
    var displayName: String?
    var displayNameSource: MetadataSource?
    var categoryId: Int64?
    var categorySource: MetadataSource?
    var subcategory: String?
    var subcategorySource: MetadataSource?
    /// 音樂風格。NULL 是正常狀態——路徑沒有線索時就該是空的，不猜（D-014）。
    var style: String?
    var styleSource: MetadataSource?
    /// 材質：發出聲音的東西是什麼做的。從路徑字面讀，讀不到就留空。
    var texture: String?
    var textureSource: MetadataSource?
    /// 每分鐘拍數。NULL 是正常狀態——沒有節奏的音效本來就沒有 BPM。
    var bpm: Double?
    var bpmSource: MetadataSource?
    var musicalKey: String?
    var keySource: MetadataSource?
    /// 是不是循環素材。NULL 代表證據不足，不猜。
    var isLoop: Bool?
    var favorite: Bool
    var rating: Int
    var notes: String?

    // --- 狀態 ---
    var status: FileStatus
    var analysisStatus: AnalysisStatus
    /// 獨立欄位，不可由 analysisStatus 推導（DECISIONS D-004）。
    var needsReview: Bool

    var dateIndexed: Date
    var lastSeenAt: Date?
    var lastPlayedAt: Date?
    var playCount: Int

    init(id: Int64? = nil,
         libraryId: Int64,
         filePath: String,
         relativePath: String,
         folderPath: String? = nil,
         filename: String,
         fileExtension: String,
         fileSize: Int64 = 0,
         fileIdentifier: String? = nil,
         duration: Double? = nil,
         sampleRate: Int? = nil,
         bitDepth: Int? = nil,
         channelCount: Int? = nil,
         fileCreatedAt: Date? = nil,
         fileModifiedAt: Date? = nil,
         displayName: String? = nil,
         displayNameSource: MetadataSource? = nil,
         categoryId: Int64? = nil,
         categorySource: MetadataSource? = nil,
         subcategory: String? = nil,
         subcategorySource: MetadataSource? = nil,
         style: String? = nil,
         styleSource: MetadataSource? = nil,
         texture: String? = nil,
         textureSource: MetadataSource? = nil,
         bpm: Double? = nil,
         bpmSource: MetadataSource? = nil,
         musicalKey: String? = nil,
         keySource: MetadataSource? = nil,
         isLoop: Bool? = nil,
         favorite: Bool = false,
         rating: Int = 0,
         notes: String? = nil,
         status: FileStatus = .ok,
         analysisStatus: AnalysisStatus = .none,
         needsReview: Bool = false,
         dateIndexed: Date = Date(),
         lastSeenAt: Date? = nil,
         lastPlayedAt: Date? = nil,
         playCount: Int = 0) {
        self.id = id
        self.libraryId = libraryId
        self.filePath = filePath
        self.relativePath = relativePath
        self.folderPath = folderPath ?? FolderPath.folder(of: relativePath)
        self.filename = filename
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.fileIdentifier = fileIdentifier
        self.duration = duration
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channelCount = channelCount
        self.fileCreatedAt = fileCreatedAt
        self.fileModifiedAt = fileModifiedAt
        self.displayName = displayName
        self.displayNameSource = displayNameSource
        self.categoryId = categoryId
        self.categorySource = categorySource
        self.subcategory = subcategory
        self.subcategorySource = subcategorySource
        self.style = style
        self.styleSource = styleSource
        self.texture = texture
        self.textureSource = textureSource
        self.bpm = bpm
        self.bpmSource = bpmSource
        self.musicalKey = musicalKey
        self.keySource = keySource
        self.isLoop = isLoop
        self.favorite = favorite
        self.rating = rating
        self.notes = notes
        self.status = status
        self.analysisStatus = analysisStatus
        self.needsReview = needsReview
        self.dateIndexed = dateIndexed
        self.lastSeenAt = lastSeenAt
        self.lastPlayedAt = lastPlayedAt
        self.playCount = playCount
    }

    /// 瀏覽器列表顯示用：有 display name 就用它，否則退回檔名。
    var browserTitle: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return filename
    }

    enum CodingKeys: String, CodingKey {
        case id
        case libraryId = "library_id"
        case filePath = "file_path"
        case relativePath = "relative_path"
        case folderPath = "folder_path"
        case filename
        case fileExtension = "file_extension"
        case fileSize = "file_size"
        case fileIdentifier = "file_identifier"
        case duration
        case sampleRate = "sample_rate"
        case bitDepth = "bit_depth"
        case channelCount = "channel_count"
        case fileCreatedAt = "file_created_at"
        case fileModifiedAt = "file_modified_at"
        case displayName = "display_name"
        case displayNameSource = "display_name_source"
        case categoryId = "category_id"
        case categorySource = "category_source"
        case subcategory
        case subcategorySource = "subcategory_source"
        case style
        case styleSource = "style_source"
        case texture
        case textureSource = "texture_source"
        case bpm
        case bpmSource = "bpm_source"
        case musicalKey = "musical_key"
        case keySource = "key_source"
        case isLoop = "is_loop"
        case favorite
        case rating
        case notes
        case status
        case analysisStatus = "analysis_status"
        case needsReview = "needs_review"
        case dateIndexed = "date_indexed"
        case lastSeenAt = "last_seen_at"
        case lastPlayedAt = "last_played_at"
        case playCount = "play_count"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let libraryId = Column(CodingKeys.libraryId)
        static let folderPath = Column(CodingKeys.folderPath)
        static let relativePath = Column(CodingKeys.relativePath)
        static let filename = Column(CodingKeys.filename)
        static let displayName = Column(CodingKeys.displayName)
        static let favorite = Column(CodingKeys.favorite)
        static let needsReview = Column(CodingKeys.needsReview)
        static let analysisStatus = Column(CodingKeys.analysisStatus)
        static let status = Column(CodingKeys.status)
        static let style = Column(CodingKeys.style)
        static let texture = Column(CodingKeys.texture)
        static let bpm = Column(CodingKeys.bpm)
        static let isLoop = Column(CodingKeys.isLoop)
        static let categoryId = Column(CodingKeys.categoryId)
        static let dateIndexed = Column(CodingKeys.dateIndexed)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
