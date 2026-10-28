import XCTest
import GRDB
@testable import FoleyLibrary

/// 整理紀錄的資料庫那一半（migration v8）。
///
/// 執行層的邏輯由 `OrganizeExecutorTests` 顧，這裡只驗 SQL：
/// **沒有正確的 journal 就沒有撤銷**，這張表是整個安全模型的地基。
final class OrganizeJournalTests: XCTestCase {

    private var database: AppDatabase!
    private var journal: OrganizeJournal!
    private var soundId: Int64!

    override func setUpWithError() throws {
        database = try TestSupport.database()
        journal = OrganizeJournal(database: database)
        soundId = try TestSupport.insertSound(into: database).id
    }

    func testABatchRecordsItsScopeSoItCanBeRecognisedLater() throws {
        let id = try journal.beginBatch(scope: "分頁：Kick", root: "/Volumes/XD/_Organized")
        try journal.finishBatch(id, linkCount: 3)

        let batch = try XCTUnwrap(journal.batches().first)
        XCTAssertEqual(batch.scope, "分頁：Kick", "撤銷清單要讓人認得出這是哪一批")
        XCTAssertEqual(batch.linkCount, 3)
        XCTAssertFalse(batch.isUndone)
    }

    func testLinkPathsComeBackInTheOrderTheyWereCreated() throws {
        let id = try journal.beginBatch(scope: "測試", root: "/tmp")
        for index in 1...3 {
            try journal.record(batchId: id, soundId: soundId, linkPath: "/tmp/\(index).wav", fileIdentifier: "1:2")
        }
        XCTAssertEqual(try journal.linkPaths(batchId: id),
                       ["/tmp/1.wav", "/tmp/2.wav", "/tmp/3.wav"])
    }

    func testEachBatchOnlySeesItsOwnLinks() throws {
        // 撤銷只能刪自己這一批的。這條在 SQL 層就要成立。
        let first = try journal.beginBatch(scope: "第一批", root: "/tmp")
        try journal.record(batchId: first, soundId: soundId, linkPath: "/tmp/a.wav", fileIdentifier: "1:2")
        let second = try journal.beginBatch(scope: "第二批", root: "/tmp")
        try journal.record(batchId: second, soundId: soundId, linkPath: "/tmp/b.wav", fileIdentifier: "1:3")

        XCTAssertEqual(try journal.linkPaths(batchId: first), ["/tmp/a.wav"])
        XCTAssertEqual(try journal.linkPaths(batchId: second), ["/tmp/b.wav"])
    }

    func testAnUndoneBatchStaysInTheHistory() throws {
        // 撤銷過的批次不刪掉：做過什麼、撤銷過什麼，都要看得見。
        let id = try journal.beginBatch(scope: "測試", root: "/tmp")
        try journal.markUndone(id)

        let batch = try XCTUnwrap(journal.batches().first)
        XCTAssertTrue(batch.isUndone)
        XCTAssertNotNil(batch.undoneAt)
    }

    func testTheNewestBatchIsFirst() throws {
        _ = try journal.beginBatch(scope: "舊的", root: "/tmp")
        _ = try journal.beginBatch(scope: "新的", root: "/tmp")
        XCTAssertEqual(try journal.batches().first?.scope, "新的")
    }

    func testTheActualLinkedFileIdentifierIsStored() throws {
        // device id + inode 改名搬移都不變，是對得回原檔的唯一依據。
        let id = try journal.beginBatch(scope: "測試", root: "/tmp")
        try journal.record(batchId: id, soundId: soundId, linkPath: "/tmp/a.wav", fileIdentifier: "1:2")

        let stored = try database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT COALESCE(file_identifier, '') FROM organize_journal")
        }
        XCTAssertEqual(stored, "1:2", "必須記錄實際連結身分，不能採用可能過期的 sounds 快照")
    }
    func testFailedUndoCanBeRetriedAndCompletedEntriesCannotBeClaimedAgain() throws {
        let id = try journal.beginBatch(scope: "retry", root: "/tmp")
        try journal.record(batchId: id, soundId: soundId, linkPath: "/tmp/retry.wav", fileIdentifier: "1:2")
        let entry = try XCTUnwrap(journal.entries(batchId: id).first)
        XCTAssertTrue(try journal.claimUndo(entryId: entry.id))
        XCTAssertFalse(try journal.claimUndo(entryId: entry.id))
        try journal.recordUndo(entryId: entry.id, state: "failed")
        try journal.markUndone(id)
        XCTAssertFalse(try XCTUnwrap(journal.batches().first).isUndone)
        XCTAssertTrue(try journal.claimUndo(entryId: entry.id))
        try journal.recordUndo(entryId: entry.id, state: "removed")
        try journal.markUndone(id)
        XCTAssertTrue(try XCTUnwrap(journal.batches().first).isUndone)
        XCTAssertTrue(try journal.entries(batchId: id).isEmpty)
        XCTAssertFalse(try journal.claimUndo(entryId: entry.id))
    }
    func testRecoveryLocationRemainsVisibleAfterBatchCompletes() throws {
        let id = try journal.beginBatch(scope: "recover", root: "/tmp")
        try journal.record(batchId: id, soundId: soundId, linkPath: "/tmp/a.wav", fileIdentifier: "1:2")
        let entry = try XCTUnwrap(journal.entries(batchId: id).first)
        XCTAssertTrue(try journal.claimUndo(entryId: entry.id))
        try journal.recordUndo(entryId: entry.id, state: "preserved", recoveryPath: "/tmp/recovery/item")
        try journal.markUndone(id)
        XCTAssertEqual(try journal.batches().first?.recoveryPaths, ["/tmp/recovery/item"])
        XCTAssertThrowsError(try journal.recordUndo(entryId: entry.id, state: "removed"))
    }

}
