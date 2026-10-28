import XCTest
import GRDB
@testable import FoleyLibrary

/// 依分類瀏覽（M41）。
///
/// 側欄的分類區會把「還沒確認的建議」也列出來，所以測試的重點跟批次接受一樣：
/// 它**不會**做什麼——不把已確定的音效拉到建議的分類底下、不被舊分析污染、
/// 不碰人工明確設定的未分類、瀏覽本身不寫任何欄位。
final class CategoryBrowseTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: SoundRepository!
    private var review: ReviewService!
    private var metadata: ManualMetadataService!
    private var mapper: OrganizerResultMapper!
    private var libraryId: Int64 = 0

    override func setUpWithError() throws {
        database = try TestSupport.database()
        repository = SoundRepository(database: database)
        review = ReviewService(database: database)
        metadata = ManualMetadataService(database: database)
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

    private func analyse(_ soundId: Int64, category: String, confidence: Double,
                         startedAt: Date = Date()) throws {
        let result = OrganizerResult(status: confidence >= 0.75 ? .recognized : .suggested,
                                     displayName: nil,
                                     category: category,
                                     tags: [],
                                     confidence: confidence,
                                     needsReview: confidence < 0.7)
        _ = try database.writer.write { db in
            try mapper.persist(result: result, soundId: soundId, engine: "test",
                               startedAt: startedAt, in: db)
        }
    }

    private func ids(in path: String) throws -> Set<Int64> {
        Set(try repository.fetch(filter: .category(path), limit: 500).compactMap(\.id))
    }

    private func categoryPath(of soundId: Int64) throws -> String? {
        try database.writer.read { db in
            try String.fetchOne(db, sql: """
                SELECT c.path FROM sounds s JOIN categories c ON c.id = s.category_id
                 WHERE s.id = ?
                """, arguments: [soundId])
        }
    }

    // MARK: - 篩選

    func testSuggestedAndConfirmedBothAppearInTheCategory() throws {
        let suggested = try sound("kick_a.wav")
        try analyse(suggested, category: "Drums/Kick", confidence: 0.6)
        let confirmed = try sound("kick_b.wav")
        try metadata.setCategory(path: "Drums/Kick", soundId: confirmed)

        XCTAssertEqual(try ids(in: "Drums/Kick"), [suggested, confirmed])
    }

    func testTopLevelIncludesItsChildren() throws {
        let kick = try sound("kick.wav")
        try analyse(kick, category: "Drums/Kick", confidence: 0.9)
        let snare = try sound("snare.wav")
        try metadata.setCategory(path: "Drums/Snare", soundId: snare)
        let door = try sound("door.wav")
        try analyse(door, category: "Foley/Doors", confidence: 0.9)

        XCTAssertEqual(try ids(in: "Drums"), [kick, snare])
        XCTAssertEqual(try repository.count(filter: .category("Drums")), 2,
                       "計數與清單必須用同一個定義")
    }

    func testLeafDoesNotIncludeItsParentOrSiblings() throws {
        let kick = try sound("kick.wav")
        try analyse(kick, category: "Drums/Kick", confidence: 0.9)
        let drums = try sound("drums.wav")
        try metadata.setCategory(path: "Drums", soundId: drums)
        let kickish = try sound("tom.wav")
        try analyse(kickish, category: "Drums/Tom", confidence: 0.9)

        XCTAssertEqual(try ids(in: "Drums/Kick"), [kick])
        XCTAssertEqual(try ids(in: "Drums"), [kick, drums, kickish])
    }

    func testConfirmedCategoryWinsOverADifferentSuggestion() throws {
        let id = try sound("prop.wav")
        try analyse(id, category: "Foley/Doors", confidence: 0.95)
        try metadata.setCategory(path: "Foley/Props", soundId: id)

        XCTAssertEqual(try ids(in: "Foley/Props"), [id])
        XCTAssertEqual(try ids(in: "Foley/Doors"), [],
                       "已確定的分類優先，同一個音效不該同時出現在兩個分類底下")
    }

    func testManuallyUnclassifiedIsNotPulledInBySuggestions() throws {
        let id = try sound("mystery.wav")
        try analyse(id, category: "Drums/Kick", confidence: 0.95)
        try metadata.setCategory(path: nil, soundId: id, source: .manual)

        XCTAssertEqual(try ids(in: "Drums/Kick"), [],
                       "人工明確設成未分類，是一個決定，不是空白")
    }

    func testOnlyTheLatestAnalysisCounts() throws {
        let id = try sound("reanalysed.wav")
        try analyse(id, category: "Drums/Snare", confidence: 0.9,
                    startedAt: Date(timeIntervalSinceNow: -3600))
        try analyse(id, category: "Drums/Kick", confidence: 0.9)

        XCTAssertEqual(try ids(in: "Drums/Kick"), [id])
        XCTAssertEqual(try ids(in: "Drums/Snare"), [], "舊分析的建議不能把音效拉進來")
    }

    func testRejectedSuggestionsDoNotCount() throws {
        let id = try sound("kick.wav")
        try analyse(id, category: "Drums/Kick", confidence: 0.9)
        let suggestionId = try database.writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM organizer_suggestions WHERE field = 'category'")
        }
        try metadata.reject(suggestionId: try XCTUnwrap(suggestionId))

        XCTAssertEqual(try ids(in: "Drums/Kick"), [])
    }

    func testBrowsingWritesNothing() throws {
        let id = try sound("kick.wav")
        try analyse(id, category: "Drums/Kick", confidence: 0.9)

        _ = try ids(in: "Drums/Kick")
        _ = try repository.categoryCounts()

        XCTAssertNil(try categoryPath(of: id), "瀏覽只是檢視，不得套用建議")
        let status = try database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM organizer_suggestions WHERE field = 'category'")
        }
        XCTAssertEqual(status, "suggested")
    }

    // MARK: - 計數

    func testCountsSeparateConfirmedFromSuggested() throws {
        try analyse(try sound("a.wav"), category: "Drums/Kick", confidence: 0.9)
        try analyse(try sound("b.wav"), category: "Drums/Kick", confidence: 0.5)
        try metadata.setCategory(path: "Drums/Kick", soundId: try sound("c.wav"))

        let kick = try XCTUnwrap(try repository.categoryCounts().first { $0.path == "Drums/Kick" })
        XCTAssertEqual(kick.confirmed, 1)
        XCTAssertEqual(kick.suggested, 2)
    }

    func testCountsAgreeWithTheFilter() throws {
        try analyse(try sound("a.wav"), category: "Drums/Kick", confidence: 0.9)
        try analyse(try sound("b.wav"), category: "Drums/Snare", confidence: 0.9)
        let manual = try sound("c.wav")
        try analyse(manual, category: "Drums/Kick", confidence: 0.9)
        try metadata.setCategory(path: "Drums/Snare", soundId: manual)

        for count in try repository.categoryCounts() {
            XCTAssertEqual(try repository.count(filter: .category(count.path)), count.total,
                           "側欄顯示的數字必須等於點進去看到的筆數：\(count.path)")
        }
    }

    // MARK: - 側欄樹

    func testTreeSumsChildrenIntoTheTopLevelAndDropsEmpties() {
        let tree = CategoryTree.build(from: [
            CategoryCount(path: "Drums/Kick", confirmed: 2, suggested: 5),
            CategoryCount(path: "Drums/Snare", confirmed: 0, suggested: 3),
            CategoryCount(path: "Drums", confirmed: 1, suggested: 0),
            CategoryCount(path: "Foley/Doors", confirmed: 0, suggested: 0),
            CategoryCount(path: "Unclassified", confirmed: 4, suggested: 0),
        ])

        XCTAssertEqual(tree.map(\.path), ["Drums"], "空的分類與 Unclassified 不列出")
        XCTAssertEqual(tree.first?.confirmed, 3)
        XCTAssertEqual(tree.first?.suggested, 8)
        XCTAssertEqual(tree.first?.children.map(\.name), ["Kick", "Snare"])
    }

    // MARK: - 接受一個分類的建議

    func testAcceptCategoryAppliesOnlyThatCategoryAboveTheThreshold() throws {
        let strongKick = try sound("kick1.wav")
        try analyse(strongKick, category: "Drums/Kick", confidence: 0.9)
        let weakKick = try sound("kick2.wav")
        try analyse(weakKick, category: "Drums/Kick", confidence: 0.5)
        let snare = try sound("snare.wav")
        try analyse(snare, category: "Drums/Snare", confidence: 0.9)

        XCTAssertEqual(try review.categoryPreview(path: "Drums/Kick", minConfidence: 0.85), 1)
        let applied = try review.acceptCategory(path: "Drums/Kick", minConfidence: 0.85)

        XCTAssertEqual(applied, 1, "預覽說幾筆就必須是幾筆")
        XCTAssertEqual(try categoryPath(of: strongKick), "Drums/Kick")
        XCTAssertNil(try categoryPath(of: weakKick), "低於門檻的不動")
        XCTAssertNil(try categoryPath(of: snare), "別的分類不動")
    }

    func testAcceptCategoryMarksSourceAndClearsReview() throws {
        let id = try sound("kick.wav")
        try analyse(id, category: "Drums/Kick", confidence: 0.6)
        try review.acceptCategory(path: "Drums", minConfidence: 0)

        let row = try database.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT category_source, needs_review FROM sounds WHERE id = ?",
                             arguments: [id])
        }
        XCTAssertEqual(row?["category_source"] as String?, MetadataSource.acceptedAI.rawValue,
                       "是你同意的，不是你打的")
        XCTAssertEqual(row?["needs_review"] as Bool?, false)
        XCTAssertEqual(try review.categoryPreview(path: "Drums", minConfidence: 0), 0,
                       "接受過的不該再出現")
    }

    func testAcceptCategoryNeverTouchesManualDecisions() throws {
        let props = try sound("prop.wav")
        try analyse(props, category: "Drums/Kick", confidence: 0.95)
        try metadata.setCategory(path: "Foley/Props", soundId: props)
        let unclassified = try sound("mystery.wav")
        try analyse(unclassified, category: "Drums/Kick", confidence: 0.95)
        try metadata.setCategory(path: nil, soundId: unclassified, source: .manual)

        XCTAssertEqual(try review.acceptCategory(path: "Drums/Kick", minConfidence: 0), 0)
        XCTAssertEqual(try categoryPath(of: props), "Foley/Props")
        XCTAssertNil(try categoryPath(of: unclassified))
    }
}
