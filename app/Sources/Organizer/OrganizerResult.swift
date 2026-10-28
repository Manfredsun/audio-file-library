import Foundation

/// Organizer 的辨識狀態。允許值由 `organizer/schemas/organization-result.json` 定義。
enum OrganizerStatus: String, Codable, CaseIterable, Hashable {
    case recognized
    case suggested
    case uncertain
    case unknown
    case failed
}

/// Organizer 的結構化輸出。欄位與 `organization-result.json` 一對一。
///
/// 注意：Codable 會忽略多餘欄位，而 schema 規定 `additionalProperties: false`，
/// 因此「多餘欄位」必須由 `OrganizerSchemaValidator` 從原始 JSON 檢出。
struct OrganizerResult: Codable, Equatable, Hashable {
    var status: OrganizerStatus
    var displayName: String?
    var category: String
    var subcategory: String?
    /// 音樂風格，來自 `style-vocabulary.md` 的白名單。
    ///
    /// 路徑沒有風格線索時是 nil。**不猜。** 錯的風格標籤比沒有標籤更糟，
    /// 因為事後分辨不出哪些是讀到的、哪些是編的。
    var style: String?
    /// 材質：發出聲音的東西是什麼做的（Metal、Wood、Plastic⋯⋯）。
    ///
    /// **只從路徑字面讀，永不從音訊推論。** 塑膠與木頭在頻譜上沒有可靠的分界，
    /// 宣稱聽得出來就是 D-013 記錄的那件事。路徑沒線索時是 nil——不猜。
    var texture: String?
    /// 節拍。來自檔名字面與訊號量測，不是詮釋。
    var bpm: Double?
    /// 調性。只從檔名字面讀，永不從音訊推論。
    var musicalKey: String?
    /// 循環或單擊。nil 代表證據不足。
    var isLoop: Bool?
    var tags: [String]
    /// 對應 JSON 的 `description`。
    var summary: String?
    var confidence: Double
    var needsReview: Bool
    var alternativeCategories: [String]

    init(status: OrganizerStatus,
         displayName: String?,
         category: String,
         subcategory: String? = nil,
         style: String? = nil,
         texture: String? = nil,
         bpm: Double? = nil,
         musicalKey: String? = nil,
         isLoop: Bool? = nil,
         tags: [String] = [],
         summary: String? = nil,
         confidence: Double,
         needsReview: Bool,
         alternativeCategories: [String] = []) {
        self.status = status
        self.displayName = displayName
        self.category = category
        self.subcategory = subcategory
        self.style = style
        self.texture = texture
        self.bpm = bpm
        self.musicalKey = musicalKey
        self.isLoop = isLoop
        self.tags = tags
        self.summary = summary
        self.confidence = confidence
        self.needsReview = needsReview
        self.alternativeCategories = alternativeCategories
    }

    enum CodingKeys: String, CodingKey {
        case status
        case displayName = "display_name"
        case category
        case subcategory
        case style
        case bpm
        case musicalKey = "musical_key"
        case isLoop = "is_loop"
        case tags
        case summary = "description"
        case confidence
        case needsReview = "needs_review"
        case alternativeCategories = "alternative_categories"
    }

    /// 選填欄位。`style` 是本機引擎填的，不是 AI 必須產出的東西——
    /// 把它列為必填會逼既有的所有樣本與提示詞一起改，換不到任何安全性。
    /// 選填欄位。
    ///
    /// 這些是**本機引擎量測或從字面讀到的事實**，不是 AI 該產出的詮釋。
    /// 列為必填會逼既有的所有樣本與提示詞一起改，換不到任何安全性。
    static let optionalKeys: Set<String> = ["style", "bpm", "musical_key", "is_loop"]

    /// schema 的 required 欄位集合。
    static let requiredKeys: Set<String> =
        Set(CodingKeys.allCases.map { $0.rawValue }).subtracting(optionalKeys)

    /// 允許出現的欄位。多出白名單以外的欄位仍然要被擋下來。
    static let allowedKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    /// 技術失敗時的標準結果。不含任何音訊詮釋。
    static func failure(reason: String) -> OrganizerResult {
        OrganizerResult(status: .failed,
                        displayName: nil,
                        category: "Unclassified",
                        subcategory: nil,
                        style: nil,
                        bpm: nil,
                        musicalKey: nil,
                        isLoop: nil,
                        tags: [],
                        summary: nil,
                        confidence: 0,
                        needsReview: true,
                        alternativeCategories: [])
    }
}

extension OrganizerResult.CodingKeys: CaseIterable {}
