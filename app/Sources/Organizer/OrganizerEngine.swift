import Foundation

/// 送給 Organizer 的輸入。只放有用的脈絡，不要灌入無關的應用程式狀態（CLAUDE.md §8）。
struct OrganizerRequest: Equatable {
    var soundId: Int64
    var audioURL: URL
    var filename: String
    var relativePath: String
    var duration: Double?
    var fileFormat: String
    var sampleRate: Int?
    var channelCount: Int?
    var existingCategory: String?
    var existingTags: [String]
    /// 既有 metadata 是否為人工設定。Organizer 不得提議覆寫，應用程式也不會照做。
    var hasManualMetadata: Bool

    init(soundId: Int64,
         audioURL: URL,
         filename: String,
         relativePath: String,
         duration: Double? = nil,
         fileFormat: String,
         sampleRate: Int? = nil,
         channelCount: Int? = nil,
         existingCategory: String? = nil,
         existingTags: [String] = [],
         hasManualMetadata: Bool = false) {
        self.soundId = soundId
        self.audioURL = audioURL
        self.filename = filename
        self.relativePath = relativePath
        self.duration = duration
        self.fileFormat = fileFormat
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.existingCategory = existingCategory
        self.existingTags = existingTags
        self.hasManualMetadata = hasManualMetadata
    }
}

/// 應用程式只認得這個介面。引擎的實作細節不得外洩到其他模組（CLAUDE.md §5）。
/// 目前只有一個實作：`LocalAnalysisEngine`。
protocol OrganizerEngine {
    var engineName: String { get }
    var modelName: String? { get }
    var modelVersion: String? { get }
    func analyze(_ request: OrganizerRequest) async throws -> OrganizerResult
}

/// M8 用的假引擎：讓整條「分析 → 驗證 → 落庫 → UI」的路徑在接上 Antigravity 之前就能跑完。
struct MockOrganizerEngine: OrganizerEngine {
    let engineName = "mock"
    let modelName: String? = "fixture"
    let modelVersion: String? = "1"

    /// 依檔名關鍵字挑一個樣本；都不符合就回 unknown。誠實的不確定優於虛構的信心。
    var fixtures: [OrganizerResult]

    init(fixtures: [OrganizerResult] = MockOrganizerEngine.defaultFixtures) {
        self.fixtures = fixtures
    }

    func analyze(_ request: OrganizerRequest) async throws -> OrganizerResult {
        let name = request.filename.lowercased()
        if name.contains("door") || name.contains("metal") {
            return MockOrganizerEngine.doorSlam
        }
        if name.contains("drawer") || name.contains("wood") {
            return MockOrganizerEngine.drawerClose
        }
        if name.contains("step") || name.contains("foot") {
            return MockOrganizerEngine.footsteps
        }
        if name.contains("impact") || name.contains("rec_") {
            return MockOrganizerEngine.ambiguousImpact
        }
        return MockOrganizerEngine.unknownSound
    }

    // MARK: - 樣本（取自 references/examples.md）

    static let doorSlam = OrganizerResult(
        status: .recognized,
        displayName: "Heavy Metal Door Slam",
        category: "Foley/Doors",
        subcategory: "Metal Door",
        tags: ["metal", "heavy", "slam", "indoor", "short"],
        summary: "Heavy metal door slam with a short resonant tail.",
        confidence: 0.94,
        needsReview: false,
        alternativeCategories: [])

    static let drawerClose = OrganizerResult(
        status: .recognized,
        displayName: "Soft Wooden Drawer Close",
        category: "Foley/Furniture",
        subcategory: "Drawer",
        tags: ["wood", "soft", "close", "indoor", "short"],
        summary: "Soft wooden drawer close with a dry indoor sound.",
        confidence: 0.89,
        needsReview: false,
        alternativeCategories: [])

    /// examples.md 第 4 例：檔名說 door、音訊是腳步聲。
    /// status 是 recognized，但 needs_review 仍為 true —— 這就是 D-004 的依據。
    static let footsteps = OrganizerResult(
        status: .recognized,
        displayName: "Concrete Footsteps",
        category: "Foley/Footsteps",
        subcategory: "Concrete",
        tags: ["concrete", "walking", "hard", "indoor"],
        summary: "Footsteps on a hard concrete surface.",
        confidence: 0.86,
        needsReview: true,
        alternativeCategories: [])

    static let ambiguousImpact = OrganizerResult(
        status: .uncertain,
        displayName: "Short Metallic Mechanical Impact",
        category: "Unclassified",
        subcategory: nil,
        tags: ["metal", "mechanical", "short"],
        summary: "Short metallic mechanical impact; the exact source is unclear.",
        confidence: 0.47,
        needsReview: true,
        alternativeCategories: ["Impacts/Metal", "Machines/Mechanical", "Foley/Doors"])

    static let unknownSound = OrganizerResult(
        status: .unknown,
        displayName: nil,
        category: "Unclassified",
        subcategory: nil,
        tags: [],
        summary: nil,
        confidence: 0.19,
        needsReview: true,
        alternativeCategories: [])

    static let defaultFixtures: [OrganizerResult] = [
        doorSlam, drawerClose, footsteps, ambiguousImpact, unknownSound
    ]
}
