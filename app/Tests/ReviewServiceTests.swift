import XCTest
@testable import FoleyLibrary

/// 批次接受。
///
/// 這個功能一次動幾千筆真實資料，所以測試的重點是**它不會做什麼**：
/// 不覆寫人工設定、不套用低於門檻的、不被舊的分析結果污染。
final class ReviewServiceTests: XCTestCase {

    private var database: AppDatabase!
    private var review: ReviewService!
    private var mapper: OrganizerResultMapper!
    private var libraryId: Int64 = 0

    override func setUpWithError() throws {
        database = try TestSupport.database()
        review = ReviewService(database: database)
        mapper = OrganizerResultMapper(validator: try TestSupport.validator(), policy: .default)
        libraryId = try database.writer.write { db in
            var library = Library(name: "Test", rootPath: "/tmp/test")
            try library.insert(db)
            return library.id ?? 0
        }
    }

    @discardableResult
    private func sound(_ name: String) throws -> Int64 {
        try database.writer.write { db in
            var sound = Sound(libraryId: libraryId,
                              filePath: "/tmp/test/\(name)",
                              relativePath: name,
                              filename: name,
                              fileExtension: "wav",
                              duration: 1)
            try sound.insert(db)
            return sound.id ?? 0
        }
    }

    private func analyse(_ soundId: Int64,
                         category: String,
                         confidence: Double,
                         tags: [String] = [],
                         startedAt: Date = Date()) throws {
        let result = OrganizerResult(status: confidence >= 0.75 ? .recognized : .suggested,
                                     displayName: nil,
                                     category: category,
                                     tags: tags,
                                     confidence: confidence,
                                     needsReview: confidence < 0.7)
        _ = try database.writer.write { db in
            try mapper.persist(result: result, soundId: soundId, engine: "test",
                               startedAt: startedAt, in: db)
        }
    }

    private func categoryPath(of soundId: Int64) throws -> String? {
        try database.writer.read { db in
            try String.fetchOne(db, sql: """
                SELECT c.path FROM sounds s JOIN categories c ON c.id = s.category_id
                 WHERE s.id = ?
                """, arguments: [soundId])
        }
    }

    private func source(of soundId: Int64) throws -> String? {
        try database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT category_source FROM sounds WHERE id = ?",
                                arguments: [soundId])
        }
    }

    // MARK: - 預覽

    func testPreviewCountsOnlySuggestionsAboveTheThreshold() throws {
        let strong = try sound("strong.wav")
        let weak = try sound("weak.wav")
        try analyse(strong, category: "Drums/Kick", confidence: 0.92)
        try analyse(weak, category: "Drums/Snare", confidence: 0.45)

        XCTAssertEqual(try review.preview(minConfidence: 0.85, includeTags: false).categories, 1)
        XCTAssertEqual(try review.preview(minConfidence: 0.40, includeTags: false).categories, 2)
        XCTAssertEqual(try review.preview(minConfidence: 0.95, includeTags: false).categories, 0)
    }

    func testPreviewMatchesWhatIsActuallyApplied() throws {
        for index in 0..<5 {
            let id = try sound("s\(index).wav")
            try analyse(id, category: "Drums/Kick", confidence: 0.9)
        }
        let preview = try review.preview(minConfidence: 0.85, includeTags: false)
        let applied = try review.acceptAll(minConfidence: 0.85, includeTags: false)
        XCTAssertEqual(preview.categories, applied.categories,
                       "預覽說幾筆就必須是幾筆，否則那個數字沒有意義")
    }

    // MARK: - 套用

    func testAcceptingAppliesTheCategoryAndMarksTheSource() throws {
        let id = try sound("kick.wav")
        try analyse(id, category: "Drums/Kick", confidence: 0.9)

        try review.acceptAll(minConfidence: 0.85, includeTags: false)

        XCTAssertEqual(try categoryPath(of: id), "Drums/Kick")
        XCTAssertEqual(try source(of: id), MetadataSource.acceptedAI.rawValue,
                       "來源是 accepted_ai 不是 manual——是你同意的，不是你打的")
    }

    func testBelowThresholdIsLeftAlone() throws {
        let id = try sound("weak.wav")
        try analyse(id, category: "Drums/Snare", confidence: 0.45)

        try review.acceptAll(minConfidence: 0.85, includeTags: false)

        XCTAssertNil(try categoryPath(of: id))
    }

    func testAcceptedSuggestionsAreNoLongerPending() throws {
        let id = try sound("kick.wav")
        try analyse(id, category: "Drums/Kick", confidence: 0.9)
        try review.acceptAll(minConfidence: 0.85, includeTags: false)

        XCTAssertEqual(try review.preview(minConfidence: 0.85, includeTags: false).categories, 0,
                       "接受過的不該再出現在下一次的預覽裡")
    }

    func testNeedsReviewIsClearedForAcceptedSounds() throws {
        let id = try sound("kick.wav")
        try analyse(id, category: "Drums/Kick", confidence: 0.9)
        try review.acceptAll(minConfidence: 0.85, includeTags: false)

        let needsReview = try database.writer.read { db in
            try Bool.fetchOne(db, sql: "SELECT needs_review FROM sounds WHERE id = ?", arguments: [id])
        }
        XCTAssertEqual(needsReview, false, "人已經決定了，就不該再留在待複查裡")
    }

    // MARK: - 不變量：人工設定永遠優先

    func testManualCategoryIsNeverOverwritten() throws {
        let id = try sound("kick.wav")
        try database.writer.write { db in
            let categoryId = try Int64.fetchOne(db, sql: "SELECT id FROM categories WHERE path = ?",
                                                arguments: ["Foley/Doors"])
            try db.execute(sql: "UPDATE sounds SET category_id = ?, category_source = ? WHERE id = ?",
                           arguments: [categoryId, MetadataSource.manual.rawValue, id])
        }
        try analyse(id, category: "Drums/Kick", confidence: 0.99)

        try review.acceptAll(minConfidence: 0.85, includeTags: false)

        XCTAssertEqual(try categoryPath(of: id), "Foley/Doors",
                       "人工設定的分類，批次接受一次都不准動")
        XCTAssertEqual(try source(of: id), MetadataSource.manual.rawValue)
    }

    func testManualSoundsAreReportedAsSkippedInThePreview() throws {
        let id = try sound("kick.wav")
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sounds SET category_source = ? WHERE id = ?",
                           arguments: [MetadataSource.manual.rawValue, id])
        }
        try analyse(id, category: "Drums/Kick", confidence: 0.99)

        let preview = try review.preview(minConfidence: 0.85, includeTags: false)
        XCTAssertEqual(preview.categories, 0)
        XCTAssertEqual(preview.skippedManual, 1, "跳過幾筆、為什麼跳過，使用者要看得到")
    }

    // MARK: - 不變量：只看最新的那一次分析

    func testOnlyTheLatestAnalysisCounts() throws {
        let id = try sound("kick.wav")
        // 舊的分析說是 Snare，重跑之後說是 Kick。
        try analyse(id, category: "Drums/Snare", confidence: 0.9,
                    startedAt: Date(timeIntervalSince1970: 1000))
        try analyse(id, category: "Drums/Kick", confidence: 0.9,
                    startedAt: Date(timeIntervalSince1970: 2000))

        XCTAssertEqual(try review.preview(minConfidence: 0.85, includeTags: false).categories, 1,
                       "同一個音效不該被算兩次")

        try review.acceptAll(minConfidence: 0.85, includeTags: false)
        XCTAssertEqual(try categoryPath(of: id), "Drums/Kick",
                       "舊的分析結果不得蓋掉新的")
    }

    // MARK: - 標籤

    func testTagsAreAppliedOnlyWhenAskedFor() throws {
        let id = try sound("kick.wav")
        try analyse(id, category: "Drums/Kick", confidence: 0.9, tags: ["short", "bright"])

        try review.acceptAll(minConfidence: 0.85, includeTags: false)
        var count = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sound_tags WHERE sound_id = ?",
                             arguments: [id]) ?? 0
        }
        XCTAssertEqual(count, 0)

        try analyse(id, category: "Drums/Kick", confidence: 0.9, tags: ["short", "bright"])
        try review.acceptAll(minConfidence: 0.85, includeTags: true)
        count = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sound_tags WHERE sound_id = ?",
                             arguments: [id]) ?? 0
        }
        XCTAssertEqual(count, 2)
    }

    func testApplyingTwiceDoesNotDuplicateTags() throws {
        let id = try sound("kick.wav")
        try analyse(id, category: "Drums/Kick", confidence: 0.9, tags: ["short"])
        try review.acceptAll(minConfidence: 0.85, includeTags: true)
        try analyse(id, category: "Drums/Kick", confidence: 0.9, tags: ["short"])
        try review.acceptAll(minConfidence: 0.85, includeTags: true)

        let count = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sound_tags WHERE sound_id = ?",
                             arguments: [id]) ?? 0
        }
        XCTAssertEqual(count, 1)
    }

    // MARK: - 不變量：不碰檔案

    func testBatchAcceptNeverTouchesFilePaths() throws {
        var ids: [Int64] = []
        for index in 0..<10 {
            let id = try sound("s\(index).wav")
            try analyse(id, category: "Drums/Kick", confidence: 0.9)
            ids.append(id)
        }
        let before = try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT file_path FROM sounds ORDER BY id")
        }

        try review.acceptAll(minConfidence: 0.85, includeTags: true)

        let after = try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT file_path FROM sounds ORDER BY id")
        }
        XCTAssertEqual(before, after, "批次接受只動 metadata，檔案路徑一個字都不准變")
        XCTAssertEqual(after.count, ids.count, "也不准少掉任何一筆")
    }
}
