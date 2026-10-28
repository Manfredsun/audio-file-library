import Foundation

/// 完全在本機執行的分析引擎。
///
/// D-013 之後的設計前提：**寧可說不知道，也不編造。**
/// 它只有兩種證據來源，兩者都可以被使用者親自查核：
///   1. 聲學量測——數字，任何人拿同一個檔案都會算出同樣的值；
///   2. 路徑字面——資料夾與檔名裡真的寫了那些字。
///
/// 它不會宣稱聽出「生鏽鐵門」這種細節，因為量測支持不了。
struct LocalAnalysisEngine: OrganizerEngine {
    let engineName = "local-acoustic"
    var modelName: String? { nil }
    let modelVersion: String? = "1"

    let taxonomy: Taxonomy
    let vocabulary: TagVocabulary
    /// 風格白名單。nil 代表這一輪不判風格（測試與舊呼叫點用）。
    let styles: StyleVocabulary?
    /// 材質白名單。跟風格一樣只從路徑讀。
    let textures: TextureVocabulary?
    /// 可注入，測試才能用合成訊號而不落地成檔案。
    var measure: (URL) -> AcousticFeatures?

    init(taxonomy: Taxonomy,
         vocabulary: TagVocabulary,
         styles: StyleVocabulary? = nil,
         textures: TextureVocabulary? = nil,
         measure: @escaping (URL) -> AcousticFeatures? = { AcousticAnalyzer.analyze(url: $0) }) {
        self.taxonomy = taxonomy
        self.vocabulary = vocabulary
        self.styles = styles
        self.textures = textures
        self.measure = measure
    }

    func analyze(_ request: OrganizerRequest) async throws -> OrganizerResult {
        let path = PathEvidenceReader.read(relativePath: request.relativePath,
                                           filename: request.filename,
                                           taxonomy: taxonomy,
                                           vocabulary: vocabulary,
                                           styles: styles)

        guard let features = measure(request.audioURL) else {
            // 讀不到音訊是技術失敗。此時即使路徑有線索也不升格成建議——
            // 只靠檔名下判斷，正是 D-013 裡出問題的那種行為。
            return .failure(reason: "無法讀取音訊內容")
        }

        let acoustic = AcousticClassifier.evidence(from: features)
        return combine(path: path, acoustic: acoustic, features: features, request: request)
    }

    // MARK: - 合併

    /// 聲學形狀對某個分類的支持程度。
    enum Support: Equatable {
        case supports
        case contradicts
        case neutral
    }

    /// 每個分類預期的訊號形狀。空集合代表「這個分類對形狀沒有預期」，一律 neutral。
    static let expectedShapes: [String: Set<SoundShape>] = [
        "Impacts": [.impulse, .rhythmic],
        "Impacts/Metal": [.impulse, .rhythmic],
        "Impacts/Wood": [.impulse, .rhythmic],
        "Impacts/Glass": [.impulse, .rhythmic],
        "Impacts/Generic": [.impulse, .rhythmic],
        "Designed/Impact Hit": [.impulse, .rhythmic],
        "Designed/Stinger": [.impulse, .rhythmic],
        "Designed/Whoosh": [.sweep, .noise],
        "Designed/Riser": [.sweep, .noise, .tonal],
        "Designed/Downer": [.sweep, .noise, .tonal],
        "Designed/Sweep": [.sweep, .noise],
        "Designed/Transition": [.sweep, .noise, .impulse],
        "Designed/Texture": [.noise, .tonal],
        "Designed/Drone": [.tonal, .noise],
        "Musical/Drone": [.tonal, .noise],
        "Musical/Instrument": [.tonal],
        "Musical/Tone": [.tonal],
        "Musical/Chord": [.tonal],
        "Ambience": [.noise, .tonal],
        "Ambience/Room Tone": [.noise, .tonal],
        "Nature/Wind": [.noise, .sweep],
        "Nature/Rain": [.noise],
        "Nature/Ocean": [.noise],
        "Nature/Thunder": [.impulse, .noise],
        "Foley/Footsteps": [.rhythmic, .impulse],
        "Foley/Doors": [.impulse, .rhythmic],
        "Foley/Props": [.impulse, .rhythmic],
        "Foley/Furniture": [.impulse, .rhythmic],
        "Foley/Handling": [.impulse, .rhythmic],
        "Drums/Kick": [.impulse],
        "Drums/Snare": [.impulse],
        "Drums/Clap": [.impulse],
        "Drums/Hi-Hat": [.impulse],
        "Drums/Cymbal": [.impulse],
        "Drums/Tom": [.impulse],
        "Drums/808": [.impulse, .tonal],
        "Drums/Percussion": [.impulse, .rhythmic],
        "Drums/Drum Loop": [.rhythmic],
        "Drums/Break": [.rhythmic],
        "Drums/Fill": [.rhythmic, .impulse],
        "Instruments/Melodic Loop": [.tonal, .rhythmic],
        "Instruments/Pad": [.tonal],
        "Instruments/Chord": [.tonal],
        "Instruments/Bass": [.tonal, .impulse],
        "UI/Click": [.impulse],
        "UI/Notification": [.tonal, .impulse],
    ]

    /// 形狀本身不足以指定分類時的候選。只在路徑毫無線索時當作 alternative 提供，
    /// 不會被當成答案寫進 category。
    static let shapeCandidates: [SoundShape: [String]] = [
        .impulse: ["Impacts", "Designed/Impact Hit"],
        .rhythmic: ["Foley/Footsteps", "Impacts"],
        .tonal: ["Designed/Drone", "Musical/Tone"],
        .noise: ["Designed/Texture", "Ambience"],
        .sweep: ["Designed/Whoosh", "Designed/Riser"],
        .silent: [],
        .ambiguous: [],
    ]

    /// 形狀判斷太沒把握時不足以反駁路徑證據。
    private static let contradictionRequiresConfidence = 0.6

    static func support(for category: String, shape: SoundShape, shapeConfidence: Double) -> Support {
        guard let expected = expectedShapes[category], expected.isEmpty == false else { return .neutral }
        if expected.contains(shape) { return .supports }
        // 說不出形狀的時候不該去反駁別人。
        guard shape != .ambiguous, shapeConfidence >= contradictionRequiresConfidence else { return .neutral }
        return .contradicts
    }

    private func combine(path: PathEvidence,
                         acoustic: AcousticEvidence,
                         features: AcousticFeatures,
                         request: OrganizerRequest) -> OrganizerResult {
        let measuredTags = acoustic.tags
        // 風格只來自路徑字面，與音訊量測完全無關——一個 kick 就是一個 kick。
        let style = path.style?.style
        // 材質同理，而且理由更強：塑膠與木頭在頻譜上沒有可靠的分界。
        // 材質**屬於主分析流程**，不是另一顆要記得去按的按鈕——
        // M36 一開始把它做成獨立的一層，結果重新分析十次材質也還是空的。
        let textureMatch = textures.flatMap {
            TextureReader.read(relativePath: request.relativePath,
                               filename: request.filename,
                               vocabulary: $0,
                               category: path.category)
        }
        let texture = textureMatch?.texture
        let musical = musicalFacts(features: features, request: request)
        var summary = acoustic.notes.joined(separator: "、")
        if let match = path.style {
            summary += "；風格線索「\(match.term)」來自\(match.fromFolder ? "資料夾" : "檔名")"
        }
        if let match = textureMatch {
            summary += "；材質線索「\(match.term)」來自\(match.fromFolder ? "資料夾" : "檔名")"
        }
        if let note = musical.note {
            summary += "；" + note
        }

        guard let category = path.category, taxonomy.isValidPath(category) else {
            // 路徑沒有線索。形狀可以提供候選，但不足以當答案——
            // 「持續的寬頻噪聲」可能是雨聲、可能是電風扇、可能是合成 texture。
            let candidates = Self.shapeCandidates[acoustic.shape] ?? []
            return OrganizerResult(status: candidates.isEmpty ? .unknown : .uncertain,
                                   displayName: nil,
                                   category: Taxonomy.unclassified,
                                   subcategory: nil,
                                   style: style,
                                   texture: texture,
                                   bpm: musical.bpm,
                                   musicalKey: musical.key,
                                   isLoop: musical.isLoop,
                                   tags: dedupe(measuredTags + path.tags),
                                   summary: summary,
                                   confidence: candidates.isEmpty ? 0 : 0.3,
                                   needsReview: true,
                                   alternativeCategories: candidates.filter(taxonomy.isValidPath))
        }

        let support = Self.support(for: category,
                                   shape: acoustic.shape,
                                   shapeConfidence: acoustic.confidence)
        let tags = dedupe(measuredTags + path.tags)

        switch support {
        case .supports:
            // 兩條互相獨立的證據指向同一個答案，這是這個引擎能達到的最高把握。
            let confidence = min(0.92, path.confidence + 0.15)
            return OrganizerResult(status: confidence >= 0.75 ? .recognized : .suggested,
                                   displayName: nil,
                                   category: category,
                                   subcategory: nil,
                                   style: style,
                                   texture: texture,
                                   bpm: musical.bpm,
                                   musicalKey: musical.key,
                                   isLoop: musical.isLoop,
                                   tags: tags,
                                   summary: summary,
                                   confidence: confidence,
                                   needsReview: confidence < ConfidencePolicy.default.reviewBelow,
                                   alternativeCategories: [])

        case .neutral:
            // 只有路徑證據。可以建議，但不能說「辨識出來了」。
            return OrganizerResult(status: .suggested,
                                   displayName: nil,
                                   category: category,
                                   subcategory: nil,
                                   style: style,
                                   texture: texture,
                                   bpm: musical.bpm,
                                   musicalKey: musical.key,
                                   isLoop: musical.isLoop,
                                   tags: tags,
                                   summary: summary,
                                   confidence: path.confidence,
                                   needsReview: path.confidence < ConfidencePolicy.default.reviewBelow,
                                   alternativeCategories: [])

        case .contradicts:
            // 檔名說是撞擊，訊號卻是持續噪聲。這正是最該讓人看一眼的情況，
            // 所以保留路徑分類但標記不確定，並把量測支持的候選附上。
            let candidates = (Self.shapeCandidates[acoustic.shape] ?? [])
                .filter { $0 != category && taxonomy.isValidPath($0) }
            return OrganizerResult(status: .uncertain,
                                   displayName: nil,
                                   category: category,
                                   subcategory: nil,
                                   style: style,
                                   texture: texture,
                                   bpm: musical.bpm,
                                   musicalKey: musical.key,
                                   isLoop: musical.isLoop,
                                   tags: tags,
                                   summary: summary + "；與路徑線索不一致",
                                   confidence: min(path.confidence, 0.4),
                                   needsReview: true,
                                   alternativeCategories: candidates)
        }
    }

    struct MusicalFacts: Equatable {
        var bpm: Double?
        var key: String?
        var isLoop: Bool?
        /// 字面與量測對不上。這種檔案最值得人看一眼。
        var conflict: Bool
        var note: String?
    }

    /// 節拍、調性、loop 判定。
    ///
    /// 又是一組互相獨立的雙證據：
    ///
    /// - **字面**：廠商寫在檔名上的 BPM（`LOB_116_Drums`、`75 BPM`）
    /// - **量測**：起音間隔與長度反推（`TempoAnalyzer`）
    ///
    /// 兩者一致 → 採用並提高信心；差距大 → 採用字面（廠商比我們清楚）
    /// 但標記衝突，讓人看一眼。兩者都沒有 → 留空，不猜。
    func musicalFacts(features: AcousticFeatures, request: OrganizerRequest) -> MusicalFacts {
        let text = request.relativePath
        let literal = MusicalMetadata.bpm(in: text)
        let measured = features.tempo

        // loop 判定：字面優先（資料夾叫 One_Shots 就不是 loop），沒有才看聲學。
        let isLoop = MusicalMetadata.loopHint(in: text) ?? (features.isLoopLike ? true : nil)

        var bpm: Double?
        var conflict = false
        var note: String?

        switch (literal, measured) {
        case let (.some(written), .some(heard)):
            // 允許八度差：87 與 174 是同一件事，不算衝突。
            let sameOctave = abs(written.bpm - heard) <= 2
            let octaveApart = abs(written.bpm * 2 - heard) <= 3 || abs(written.bpm - heard * 2) <= 3
            bpm = written.bpm
            if sameOctave {
                note = String(format: "BPM %.0f：檔名與量測一致", written.bpm)
            } else if octaveApart {
                note = String(format: "BPM %.0f：檔名與量測差一個八度", written.bpm)
            } else {
                conflict = true
                note = String(format: "BPM 檔名寫 %.0f，量測是 %.0f", written.bpm, heard)
            }
        case let (.some(written), .none):
            bpm = written.bpm
            note = String(format: "BPM %.0f：只有檔名的證據", written.bpm)
        case let (.none, .some(heard)):
            // 量測值單獨採用的門檻比較高——沒有字面可以對照。
            if features.tempoConfidence >= 0.8 {
                bpm = heard
                note = String(format: "BPM %.0f：只有量測的證據", heard)
            }
        case (.none, .none):
            break
        }

        return MusicalFacts(bpm: bpm,
                            key: MusicalMetadata.key(in: text),
                            isLoop: isLoop,
                            conflict: conflict,
                            note: note)
    }

    /// 保序去重，並套用詞彙表的數量上限。
    private func dedupe(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for tag in tags where seen.insert(tag).inserted {
            output.append(tag)
        }
        return Array(output.prefix(vocabulary.maxTags))
    }
}
