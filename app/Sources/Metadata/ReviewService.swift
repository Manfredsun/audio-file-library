import Foundation
import GRDB

/// 批次審核。
///
/// D-007 沒有被放寬：AI 仍然只寫進 `organizer_suggestions`，人工欄位仍然只在
/// 使用者明確接受時才更新。改變的只是**按一次按鈕算幾千次**。
///
/// 這跟「高信心就自動套用」是兩件事。後者是程式替使用者決定，而且事後分不出
/// 哪些是使用者同意的、哪些是程式自己寫的——那正是 provenance 要防的事。
struct ReviewService {
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// 批次動作的預覽。執行前一定要先給使用者看這個。
    struct Preview: Equatable {
        /// 會被套用分類的音效數。
        var categories: Int
        /// 會被加上的標籤列數。
        var tags: Int
        /// 因為已經是人工設定而被跳過的音效數。
        var skippedManual: Int

        var isEmpty: Bool { categories == 0 && tags == 0 }
    }

    /// 只看每個音效**最新**的那一次分析。
    ///
    /// 重跑過的音效在 organizer_analysis 裡有多列，全部算進去的話，
    /// 同一個音效會被舊分析的建議蓋掉新的。
    private static let latestAnalysis = """
        SELECT a.id AS analysis_id, a.sound_id AS sound_id, a.confidence AS confidence
          FROM organizer_analysis a
         WHERE a.id = (SELECT b.id FROM organizer_analysis b
                        WHERE b.sound_id = a.sound_id
                        ORDER BY b.started_at DESC, b.id DESC LIMIT 1)
        """

    func preview(minConfidence: Double, includeTags: Bool) throws -> Preview {
        try database.writer.read { db in
            let categories = try Int.fetchOne(db, sql: """
                WITH latest AS (\(Self.latestAnalysis))
                SELECT COUNT(*) FROM latest x
                  JOIN organizer_suggestions g ON g.analysis_id = x.analysis_id
                   AND g.field = 'category' AND g.status = 'suggested'
                  JOIN categories c ON c.path = g.value
                  JOIN sounds s ON s.id = x.sound_id
                 WHERE x.confidence >= ?
                   AND (s.category_source IS NULL OR s.category_source <> 'manual')
                """, arguments: [minConfidence]) ?? 0

            let skipped = try Int.fetchOne(db, sql: """
                WITH latest AS (\(Self.latestAnalysis))
                SELECT COUNT(*) FROM latest x
                  JOIN organizer_suggestions g ON g.analysis_id = x.analysis_id
                   AND g.field = 'category' AND g.status = 'suggested'
                  JOIN sounds s ON s.id = x.sound_id
                 WHERE x.confidence >= ? AND s.category_source = 'manual'
                """, arguments: [minConfidence]) ?? 0

            var tags = 0
            if includeTags {
                tags = try Int.fetchOne(db, sql: """
                    WITH latest AS (\(Self.latestAnalysis))
                    SELECT COUNT(*) FROM latest x
                      JOIN organizer_suggestions g ON g.analysis_id = x.analysis_id
                       AND g.field = 'tag' AND g.status = 'suggested'
                     WHERE x.confidence >= ?
                    """, arguments: [minConfidence]) ?? 0
            }

            return Preview(categories: categories, tags: tags, skippedManual: skipped)
        }
    }

    /// 套用。回傳實際套用的筆數。
    ///
    /// 用一次 SQL 完成而不是逐筆 4,847 次寫入：逐筆的話是四千多次交易，
    /// 而且中途失敗會留下一半套用一半沒套用的狀態。
    @discardableResult
    func acceptAll(minConfidence: Double, includeTags: Bool) throws -> Preview {
        try database.writer.write { db in
            // --- 分類 ---
            try db.execute(sql: """
                UPDATE sounds
                   SET category_id = (
                         SELECT c.id FROM categories c
                           JOIN organizer_suggestions g ON g.value = c.path
                           JOIN organizer_analysis a ON a.id = g.analysis_id
                          WHERE a.sound_id = sounds.id
                            AND g.field = 'category' AND g.status = 'suggested'
                            AND a.id = (SELECT b.id FROM organizer_analysis b
                                         WHERE b.sound_id = sounds.id
                                         ORDER BY b.started_at DESC, b.id DESC LIMIT 1)
                            AND a.confidence >= :minConfidence
                          LIMIT 1),
                       category_source = :source,
                       needs_review = 0
                 WHERE (category_source IS NULL OR category_source <> :manual)
                   AND EXISTS (
                         SELECT 1 FROM organizer_suggestions g
                           JOIN organizer_analysis a ON a.id = g.analysis_id
                           JOIN categories c ON c.path = g.value
                          WHERE a.sound_id = sounds.id
                            AND g.field = 'category' AND g.status = 'suggested'
                            AND a.id = (SELECT b.id FROM organizer_analysis b
                                         WHERE b.sound_id = sounds.id
                                         ORDER BY b.started_at DESC, b.id DESC LIMIT 1)
                            AND a.confidence >= :minConfidence)
                """, arguments: ["minConfidence": minConfidence,
                                 "source": MetadataSource.acceptedAI.rawValue,
                                 "manual": MetadataSource.manual.rawValue])
            let categories = db.changesCount

            // --- 標籤 ---
            var tags = 0
            if includeTags {
                // 沒見過的標籤先建起來。
                //
                // 用 ON CONFLICT 指名衝突欄位，不用 INSERT OR IGNORE：
                // OR IGNORE 會把**所有**約束違反都吞掉，包括「忘了給 created_at」
                // 這種真正的錯誤，結果是零筆寫入而且完全沒有錯誤訊息。
                // 第一版就是這樣寫的，測試抓到之前看起來一切正常。
                try db.execute(sql: """
                    INSERT INTO tags (name, canonical_name, created_at)
                    SELECT DISTINCT g.value, LOWER(TRIM(g.value)), :now
                      FROM organizer_suggestions g
                      JOIN organizer_analysis a ON a.id = g.analysis_id
                     WHERE g.field = 'tag' AND g.status = 'suggested'
                       AND a.id = (SELECT b.id FROM organizer_analysis b
                                    WHERE b.sound_id = a.sound_id
                                    ORDER BY b.started_at DESC, b.id DESC LIMIT 1)
                       AND a.confidence >= :minConfidence
                    ON CONFLICT (canonical_name) DO NOTHING
                    """, arguments: ["now": Date(), "minConfidence": minConfidence])

                try db.execute(sql: """
                    INSERT INTO sound_tags (sound_id, tag_id, source, confidence, accepted, created_at)
                    SELECT a.sound_id, t.id, :source, g.confidence, 1, :now
                      FROM organizer_suggestions g
                      JOIN organizer_analysis a ON a.id = g.analysis_id
                      JOIN tags t ON t.canonical_name = LOWER(TRIM(g.value))
                     WHERE g.field = 'tag' AND g.status = 'suggested'
                       AND a.id = (SELECT b.id FROM organizer_analysis b
                                    WHERE b.sound_id = a.sound_id
                                    ORDER BY b.started_at DESC, b.id DESC LIMIT 1)
                       AND a.confidence >= :minConfidence
                    ON CONFLICT (sound_id, tag_id, source) DO NOTHING
                    """, arguments: ["source": MetadataSource.acceptedAI.rawValue,
                                     "now": Date(),
                                     "minConfidence": minConfidence])
                tags = db.changesCount
            }

            // --- 建議標記為已接受 ---
            var fields = "'category'"
            if includeTags { fields += ", 'tag'" }
            try db.execute(sql: """
                UPDATE organizer_suggestions
                   SET status = :accepted
                 WHERE status = :suggested
                   AND field IN (\(fields))
                   AND analysis_id IN (
                         SELECT a.id FROM organizer_analysis a
                          WHERE a.confidence >= :minConfidence
                            AND a.id = (SELECT b.id FROM organizer_analysis b
                                         WHERE b.sound_id = a.sound_id
                                         ORDER BY b.started_at DESC, b.id DESC LIMIT 1))
                """, arguments: ["accepted": OrganizerSuggestion.Status.accepted.rawValue,
                                 "suggested": OrganizerSuggestion.Status.suggested.rawValue,
                                 "minConfidence": minConfidence])

            AppLog.organizer.info("批次接受 分類=\(categories, privacy: .public) 標籤=\(tags, privacy: .public) 門檻=\(minConfidence, privacy: .public)")
            return Preview(categories: categories, tags: tags, skippedManual: 0)
        }
    }

    // MARK: - 單一分類（M41）

    /// 一筆可以被接受的分類建議。
    private struct CategoryCandidate {
        let soundId: Int64
        let suggestionId: Int64
        let categoryId: Int64
    }

    /// 某個分類（含子分類）底下，還沒有已確定分類、而且信心達門檻的待處理建議。
    ///
    /// 跟側欄 `.category` 篩選的「建議」那一半是同一個集合，再加上信心門檻：
    /// 最新一次分析、沒有已確定分類、不是人工設成未分類的。
    private func categoryCandidates(path: String, minConfidence: Double,
                                    in db: Database) throws -> [CategoryCandidate] {
        try Row.fetchAll(db, sql: """
            SELECT a.sound_id AS sound_id, g.id AS suggestion_id, c.id AS category_id
              FROM organizer_suggestions g
              JOIN organizer_analysis a ON a.id = g.analysis_id
              JOIN categories c ON c.path = g.value
              JOIN sounds s ON s.id = a.sound_id
             WHERE g.field = 'category' AND g.status = 'suggested'
               AND (g.value = :path OR (g.value >= :lower AND g.value < :upper))
               AND a.confidence >= :minConfidence
               AND s.category_id IS NULL
               AND (s.category_source IS NULL OR s.category_source <> :manual)
               AND a.id = (SELECT b.id FROM organizer_analysis b
                            WHERE b.sound_id = a.sound_id
                            ORDER BY b.started_at DESC, b.id DESC LIMIT 1)
            """, arguments: ["path": path,
                             "lower": path + "/",
                             "upper": path + "0",
                             "minConfidence": minConfidence,
                             "manual": MetadataSource.manual.rawValue])
            .map { CategoryCandidate(soundId: $0["sound_id"],
                                     suggestionId: $0["suggestion_id"],
                                     categoryId: $0["category_id"]) }
    }

    /// 預覽：接受這個分類的建議會套用幾筆。執行前一定要先給使用者看。
    func categoryPreview(path: String, minConfidence: Double) throws -> Int {
        try database.writer.read { db in
            try categoryCandidates(path: path, minConfidence: minConfidence, in: db).count
        }
    }

    /// 接受一個分類（含子分類）底下的分類建議。回傳實際套用的音效數。
    ///
    /// 只動分類，不動標籤：使用者是在「Kick 這一類」的檢視裡按下去的，
    /// 他確認的是「這些是 Kick」，不是這些音效的每一個標籤。
    /// 已有已確定分類的（人工或先前接受的）一律不碰；來源標成 accepted_ai（D-024）。
    @discardableResult
    func acceptCategory(path: String, minConfidence: Double) throws -> Int {
        try database.writer.write { db in
            let candidates = try categoryCandidates(path: path, minConfidence: minConfidence, in: db)
            for candidate in candidates {
                try db.execute(sql: """
                    UPDATE sounds
                       SET category_id = ?, category_source = ?, needs_review = 0
                     WHERE id = ? AND category_id IS NULL
                    """, arguments: [candidate.categoryId,
                                     MetadataSource.acceptedAI.rawValue,
                                     candidate.soundId])
                try db.execute(sql: "UPDATE organizer_suggestions SET status = ? WHERE id = ?",
                               arguments: [OrganizerSuggestion.Status.accepted.rawValue,
                                           candidate.suggestionId])
            }
            AppLog.organizer.info("分類接受 \(path, privacy: .public) 筆數=\(candidates.count, privacy: .public) 門檻=\(minConfidence, privacy: .public)")
            return candidates.count
        }
    }
}
