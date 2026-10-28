import XCTest
import GRDB
@testable import FoleyLibrary

/// 列表左邊的黃點（needs_review）什麼時候該消失（D-043）。
///
/// 使用者回報：在 Inspector 按「接受」之後黃點還在。原因是只有審核列的 A／R 鍵與批次接受
/// 會清旗標，Inspector 的接受、拒絕、人工設定分類都不會。
/// 規則：**人對分類做了決定，就不再待複查。**只接受標籤不算——分類才是審核的主體。
final class ReviewFlagTests: XCTestCase {

    private var database: AppDatabase!
    private var metadata: ManualMetadataService!
    private var mapper: OrganizerResultMapper!
    private var soundId: Int64 = 0

    override func setUpWithError() throws {
        database = try TestSupport.database()
        metadata = ManualMetadataService(database: database)
        mapper = OrganizerResultMapper(validator: try TestSupport.validator(), policy: .default)
        soundId = try TestSupport.insertSound(into: database, filename: "kick.wav").id ?? 0

        // 低信心 → 待複查，同時有分類與標籤兩種建議。
        let result = OrganizerResult(status: .suggested,
                                     displayName: nil,
                                     category: "Drums/Kick",
                                     tags: ["short"],
                                     confidence: 0.5,
                                     needsReview: true)
        _ = try database.writer.write { db in
            try mapper.persist(result: result, soundId: soundId, engine: "test",
                               startedAt: Date(), in: db)
        }
        XCTAssertTrue(try needsReview(), "前提：分析完是待複查")
    }

    private func needsReview() throws -> Bool {
        try database.writer.read { db in
            try Bool.fetchOne(db, sql: "SELECT needs_review FROM sounds WHERE id = ?",
                              arguments: [soundId]) ?? false
        }
    }

    private func suggestionId(_ field: String) throws -> Int64 {
        try XCTUnwrap(try database.writer.read { db in
            try Int64.fetchOne(db, sql: """
                SELECT id FROM organizer_suggestions WHERE field = ? AND status = 'suggested' LIMIT 1
                """, arguments: [field])
        })
    }

    func testAcceptingTheCategoryClearsTheFlag() throws {
        try metadata.accept(suggestionId: try suggestionId("category"))
        XCTAssertFalse(try needsReview())
    }

    func testRejectingTheCategoryClearsTheFlag() throws {
        try metadata.reject(suggestionId: try suggestionId("category"))
        XCTAssertFalse(try needsReview(), "拒絕也是一個決定，跟審核列的 R 鍵一致")
    }

    func testSettingTheCategoryByHandClearsTheFlag() throws {
        try metadata.setCategory(path: "Drums/Snare", soundId: soundId)
        XCTAssertFalse(try needsReview())
    }

    func testAcceptingOnlyATagKeepsTheFlag() throws {
        try metadata.accept(suggestionId: try suggestionId("tag"))
        XCTAssertTrue(try needsReview(), "分類還沒人看過，黃點應該留著")
    }

    func testRejectingATagKeepsTheFlag() throws {
        try metadata.reject(suggestionId: try suggestionId("tag"))
        XCTAssertTrue(try needsReview())
    }
}
