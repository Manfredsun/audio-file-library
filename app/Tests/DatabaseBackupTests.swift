import GRDB
import XCTest
@testable import FoleyLibrary

/// 備份。
///
/// 這個資料庫是使用者人工成果的唯一一份，而且在系統碟上不在他的音色庫碟上。
final class DatabaseBackupTests: XCTestCase {

    private var work: URL!
    private var databasePath: String!
    private var database: AppDatabase!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        databasePath = work.appendingPathComponent("library.sqlite").path

        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: databasePath, configuration: config)
        database = try AppDatabase(queue, path: databasePath, seedTaxonomy: try TestSupport.taxonomy())
        try TestSupport.insertSound(into: database, filename: "kick.wav")
    }

    override func tearDownWithError() throws {
        database = nil
        try? FileManager.default.removeItem(at: work)
    }

    private var folder: URL { DatabaseBackup.folder(beside: databasePath) }

    func testABackupContainsTheData() throws {
        // 備份要能真的打開並讀到東西，不是只產生一個有大小的檔案。
        let destination = work.appendingPathComponent("copy.sqlite")
        try DatabaseBackup.make(from: database, to: destination)

        let restored = try DatabaseQueue(path: destination.path)
        let count = try restored.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sounds")
        }
        XCTAssertEqual(count, 1)
    }

    func testABackupNeverOverwritesAnExistingFile() throws {
        let destination = work.appendingPathComponent("copy.sqlite")
        try DatabaseBackup.make(from: database, to: destination)
        XCTAssertThrowsError(try DatabaseBackup.make(from: database, to: destination),
                             "覆蓋掉上一份備份，等於在需要的時候少了一份")
    }

    func testAutomaticBackupLandsBesideTheDatabase() throws {
        let url = DatabaseBackup.automatic(for: database,
                                           databasePath: databasePath,
                                           trigger: .batchAccept)
        let backup = try XCTUnwrap(url)
        XCTAssertTrue(backup.path.hasPrefix(folder.path))
        XCTAssertTrue(backup.lastPathComponent.contains("accept"), "檔名要看得出是哪個動作觸發的")
    }

    func testListPutsTheNewestFirst() throws {
        DatabaseBackup.automatic(for: database, databasePath: databasePath, trigger: .batchAccept)
        Thread.sleep(forTimeInterval: 1.1)
        DatabaseBackup.automatic(for: database, databasePath: databasePath, trigger: .organize)

        let entries = DatabaseBackup.list(in: folder)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.trigger, "整理")
    }

    func testPruneKeepsOnlyTheNewestFew() throws {
        for index in 0..<5 {
            let stamp = work.appendingPathComponent("x")
            _ = stamp
            let destination = folder.appendingPathComponent("library-manual-2026010\(index)-000000.sqlite")
            try DatabaseBackup.make(from: database, to: destination)
        }
        DatabaseBackup.prune(in: folder, keeping: 2)
        XCTAssertEqual(DatabaseBackup.list(in: folder).count, 2)
    }

    func testPruneNeverTouchesFilesItDidNotCreate() throws {
        // 跟撤銷同一條原則（D-032）：沒有紀錄的東西一個字都不能刪。
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stranger = folder.appendingPathComponent("使用者自己放的.sqlite")
        try "不要動我".write(to: stranger, atomically: true, encoding: .utf8)
        for index in 0..<4 {
            try DatabaseBackup.make(
                from: database,
                to: folder.appendingPathComponent("library-manual-2026010\(index)-000000.sqlite"))
        }

        DatabaseBackup.prune(in: folder, keeping: 1)

        XCTAssertTrue(FileManager.default.fileExists(atPath: stranger.path))
        XCTAssertEqual(DatabaseBackup.list(in: folder).count, 1)
    }

    func testAnInMemoryDatabaseHasNoPathAndIsSimplySkipped() throws {
        // 測試用的 in-memory 資料庫沒有路徑。備份要安靜地跳過，不是當掉。
        let memory = try AppDatabase.makeInMemory(taxonomy: try TestSupport.taxonomy())
        XCTAssertNil(memory.path)
    }
    func testRequiredBackupFailsWhenThereIsNoPersistentDatabase() throws {
        let memory = try TestSupport.database()
        XCTAssertThrowsError(try DatabaseBackup.required(for: memory, trigger: .batchAccept))
    }

    func testPrunePreservesAUserFileThatSharesTheLibraryPrefix() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stranger = folder.appendingPathComponent("library-user.sqlite")
        try Data("keep".utf8).write(to: stranger)
        DatabaseBackup.prune(in: folder, keeping: 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stranger.path))
    }

}
