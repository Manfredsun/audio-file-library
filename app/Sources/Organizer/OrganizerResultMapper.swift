import Foundation
import GRDB

/// 把 Organizer 的輸出落成資料庫紀錄。
///
/// 這個型別**只會**寫 `organizer_analysis`、`organizer_suggestions`，
/// 以及 `sounds` 的分析狀態欄位。
/// 它永遠不會碰 `display_name`、`category_id`、`subcategory`——
/// 那些欄位只在使用者明確 Accept 時才由 `ManualMetadataService` 更新（DECISIONS D-007）。
struct OrganizerResultMapper {
    let validator: OrganizerSchemaValidator
    let policy: ConfidencePolicy

    init(validator: OrganizerSchemaValidator, policy: ConfidencePolicy = .default) {
        self.validator = validator
        self.policy = policy
    }

    @discardableResult
    func persist(result: OrganizerResult,
                 soundId: Int64,
                 engine: String,
                 model: String? = nil,
                 modelVersion: String? = nil,
                 startedAt: Date = Date(),
                 in db: Database) throws -> OrganizerAnalysis {

        try validator.validate(result)

        // 舊的建議降級為 superseded，不刪除——保留 AI 的歷史。
        try db.execute(sql: """
            UPDATE organizer_suggestions
               SET status = ?
             WHERE status = ?
               AND analysis_id IN (SELECT id FROM organizer_analysis WHERE sound_id = ?)
            """,
            arguments: [OrganizerSuggestion.Status.superseded.rawValue,
                        OrganizerSuggestion.Status.suggested.rawValue,
                        soundId])

        let needsReview = policy.effectiveNeedsReview(for: result)

        var analysis = OrganizerAnalysis(
            soundId: soundId,
            engine: engine,
            model: model,
            modelVersion: modelVersion,
            status: result.status,
            confidence: result.confidence,
            needsReview: needsReview,
            summary: result.summary,
            startedAt: startedAt,
            completedAt: Date(),
            errorMessage: nil)
        try analysis.insert(db)

        guard let analysisId = analysis.id else {
            throw AppError.databaseError("organizer_analysis 未取得 rowID")
        }

        func addSuggestion(_ field: OrganizerSuggestion.Field, _ value: String, confidence: Double?) throws {
            var suggestion = OrganizerSuggestion(analysisId: analysisId,
                                                 field: field,
                                                 value: value,
                                                 confidence: confidence,
                                                 status: .suggested)
            try suggestion.insert(db)
        }

        if let displayName = result.displayName {
            try addSuggestion(.displayName, displayName, confidence: result.confidence)
        }
        if result.category != Taxonomy.unclassified {
            try addSuggestion(.category, result.category, confidence: result.confidence)
        }
        if let subcategory = result.subcategory {
            try addSuggestion(.subcategory, subcategory, confidence: result.confidence)
        }
        // 材質跟風格同一類：路徑裡字面寫著的字，使用者打開 Finder 就能查核。
        // 直接落到欄位上，側欄才能立刻依材質篩選。人工設定過的永遠不覆寫。
        if let texture = result.texture {
            try db.execute(sql: """
                UPDATE sounds
                   SET texture = ?, texture_source = ?
                 WHERE id = ?
                   AND (texture_source IS NULL OR texture_source <> ?)
                """,
                arguments: [texture, MetadataSource.imported.rawValue,
                            soundId])
        }

        if let style = result.style {
            try addSuggestion(.style, style, confidence: result.confidence)
        }
        if let summary = result.summary {
            try addSuggestion(.summary, summary, confidence: result.confidence)
        }
        for tag in result.tags {
            try addSuggestion(.tag, tag, confidence: result.confidence)
        }
        for alternative in result.alternativeCategories {
            try addSuggestion(.alternativeCategory, alternative, confidence: nil)
        }

        // 只更新分析狀態。人工欄位一個都不碰。
        let analysisStatus: AnalysisStatus = (result.status == .failed) ? .failed : .done
        try db.execute(sql: "UPDATE sounds SET analysis_status = ?, needs_review = ? WHERE id = ?",
                       arguments: [analysisStatus.rawValue, needsReview, soundId])

        // 風格是這條規則的例外，而且是刻意的：它不是對音訊的詮釋，
        // 是路徑裡字面寫著的字，使用者打開 Finder 就能查核。所以直接落到欄位上，
        // 讓側欄可以立刻依風格篩選，不必先一個一個 Accept 八千次。
        //
        // 但**人工設定過的風格永遠不覆寫**——那是 D-007 那條線，沒有例外。
        // 節拍、調性、loop 跟風格同一類：**量測與字面，不是詮釋**。
        // 直接落到欄位上，人工設定過的一律不覆寫。
        if result.bpm != nil || result.musicalKey != nil || result.isLoop != nil {
            try db.execute(sql: """
                UPDATE sounds
                   SET bpm = CASE WHEN bpm_source IN ('manual', 'accepted_ai') THEN bpm ELSE COALESCE(?, bpm) END,
                       bpm_source = CASE WHEN bpm_source IN ('manual', 'accepted_ai') OR ? IS NULL THEN bpm_source ELSE ? END,
                       musical_key = CASE WHEN key_source IN ('manual', 'accepted_ai') THEN musical_key ELSE COALESCE(?, musical_key) END,
                       key_source = CASE WHEN key_source IN ('manual', 'accepted_ai') OR ? IS NULL THEN key_source ELSE ? END,
                       is_loop = CASE WHEN bpm_source IN ('manual', 'accepted_ai') THEN is_loop ELSE COALESCE(?, is_loop) END
                 WHERE id = ?
                """,
                arguments: [result.bpm, result.bpm, MetadataSource.imported.rawValue,
                            result.musicalKey, result.musicalKey, MetadataSource.imported.rawValue,
                            result.isLoop, soundId])
        }

        if let style = result.style {
            try db.execute(sql: """
                UPDATE sounds
                   SET style = ?, style_source = ?
                 WHERE id = ?
                   AND (style_source IS NULL OR style_source NOT IN ('manual', 'accepted_ai'))
                """,
                // 來源標成 imported 而不是 antigravity：這個值是從既有路徑讀來的，
                // 不是任何模型產出的。來源欄位要誠實，日後才追得回它從哪來。
                arguments: [style, MetadataSource.imported.rawValue,
                            soundId])
        }

        AppLog.organizer.info("分析落庫 sound=\(soundId, privacy: .public) status=\(result.status.rawValue, privacy: .public) needsReview=\(needsReview, privacy: .public)")

        return analysis
    }
}
