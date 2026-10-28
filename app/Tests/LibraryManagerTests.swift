import XCTest
import GRDB
@testable import FoleyLibrary

/// M1：音色庫存取。
/// 最重要的性質是「離線不等於消失」——外接碟拔掉時 metadata 必須原封不動。
final class LibraryManagerTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("foley-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch, FileManager.default.fileExists(atPath: scratch.path) {
            try? FileManager.default.removeItem(at: scratch)
        }
    }

    private func makeFolder(_ name: String) throws -> URL {
        let url = scratch.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 臨時目錄在 macOS 上是 /var → /private/var 的 symlink，
    /// 而書籤解析回來的一律是實體路徑。比較之前兩邊都要解析。
    private func realPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    func testAddCreatesAvailableLibraryWithBookmark() throws {
        let database = try TestSupport.database()
        let manager = LibraryManager(database: database)
        let folder = try makeFolder("Foley SSD")

        let library = try manager.add(url: folder)

        XCTAssertEqual(library.name, "Foley SSD")
        XCTAssertEqual(library.rootPath, realPath(folder))
        XCTAssertEqual(library.availabilityStatus, .available)
        XCTAssertNotNil(library.bookmarkData, "應該要存下書籤，否則資料夾搬走就找不回來")
    }

    func testAddingSamePathTwiceDoesNotDuplicate() throws {
        let database = try TestSupport.database()
        let manager = LibraryManager(database: database)
        let folder = try makeFolder("BBC Archive")

        _ = try manager.add(url: folder)
        _ = try manager.add(url: folder, name: "BBC Archive (renamed)")

        let libraries = try manager.libraries()
        XCTAssertEqual(libraries.count, 1, "同一個根路徑不應該產生兩筆音色庫")
        XCTAssertEqual(libraries.first?.name, "BBC Archive (renamed)")
    }

    func testMissingFolderIsMarkedOfflineNotRejected() throws {
        let database = try TestSupport.database()
        let manager = LibraryManager(database: database)
        let missing = scratch.appendingPathComponent("NotThere", isDirectory: true)

        let library = try manager.add(url: missing)

        XCTAssertEqual(library.availabilityStatus, .offline)
        XCTAssertEqual(try manager.libraries().count, 1, "離線的音色庫仍然要被記錄下來")
    }

    /// ROADMAP §30 第 11 條：外接碟離線絕不摧毀 metadata。
    func testGoingOfflinePreservesSoundMetadata() throws {
        let database = try TestSupport.database()
        let manager = LibraryManager(database: database)
        let folder = try makeFolder("Removable")
        let library = try manager.add(url: folder)
        let libraryId = try XCTUnwrap(library.id)

        try database.writer.write { db in
            var sound = Sound(libraryId: libraryId,
                              filePath: folder.appendingPathComponent("a.wav").path,
                              relativePath: "a.wav",
                              filename: "a.wav",
                              fileExtension: "wav",
                              displayName: "使用者命名的音效",
                              displayNameSource: .manual)
            try sound.insert(db)
        }

        // 模擬拔掉外接碟
        try FileManager.default.removeItem(at: folder)
        let refreshed = try manager.refreshAvailability()

        XCTAssertEqual(refreshed.first?.availabilityStatus, .offline)

        let sounds = try database.writer.read { db in try Sound.fetchAll(db) }
        XCTAssertEqual(sounds.count, 1, "離線不得刪除音效紀錄")
        XCTAssertEqual(sounds.first?.displayName, "使用者命名的音效")
        XCTAssertEqual(sounds.first?.displayNameSource, .manual)
    }

    func testReconnectAfterComingBackOnline() throws {
        let database = try TestSupport.database()
        let manager = LibraryManager(database: database)
        let folder = try makeFolder("Intermittent")
        _ = try manager.add(url: folder)

        try FileManager.default.removeItem(at: folder)
        XCTAssertEqual(try manager.refreshAvailability().first?.availabilityStatus, .offline)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertEqual(try manager.refreshAvailability().first?.availabilityStatus, .available)
    }

    /// 資料夾被改名時，書籤應該找得回來，並且更新記錄的路徑。
    func testRelinksAfterFolderIsRenamed() throws {
        let database = try TestSupport.database()
        let manager = LibraryManager(database: database)
        let original = try makeFolder("Before")
        _ = try manager.add(url: original)

        let renamed = scratch.appendingPathComponent("After", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: renamed)

        let refreshed = try manager.refreshAvailability()
        XCTAssertEqual(refreshed.first?.availabilityStatus, .available)
        XCTAssertEqual(refreshed.first?.rootPath, realPath(renamed),
                       "改名之後應該用書籤重新連結並更新路徑")
    }

    func testRemovingLibraryDeletesRecordsButNotFiles() throws {
        let database = try TestSupport.database()
        let manager = LibraryManager(database: database)
        let folder = try makeFolder("Disposable")
        let file = folder.appendingPathComponent("keep.wav")
        try Data("audio".utf8).write(to: file)

        let library = try manager.add(url: folder)
        let libraryId = try XCTUnwrap(library.id)
        try database.writer.write { db in
            var sound = Sound(libraryId: libraryId,
                              filePath: file.path,
                              relativePath: "keep.wav",
                              filename: "keep.wav",
                              fileExtension: "wav")
            try sound.insert(db)
        }

        try manager.remove(libraryId: libraryId)

        XCTAssertTrue(try manager.libraries().isEmpty)
        let remaining = try database.writer.read { db in try Sound.fetchCount(db) }
        XCTAssertEqual(remaining, 0, "音色庫紀錄移除時，其下的音效紀錄應該一併移除")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                      "磁碟上的原始檔案絕不可以被刪除")
    }

    func testSoundCountPerLibrary() throws {
        let database = try TestSupport.database()
        let manager = LibraryManager(database: database)
        let a = try manager.add(url: try makeFolder("A"))
        let b = try manager.add(url: try makeFolder("B"))
        let aId = try XCTUnwrap(a.id)
        let bId = try XCTUnwrap(b.id)

        try database.writer.write { db in
            for index in 0..<3 {
                var sound = Sound(libraryId: aId,
                                  filePath: "/tmp/a\(index).wav",
                                  relativePath: "a\(index).wav",
                                  filename: "a\(index).wav",
                                  fileExtension: "wav")
                try sound.insert(db)
            }
        }

        XCTAssertEqual(try manager.soundCount(libraryId: aId), 3)
        XCTAssertEqual(try manager.soundCount(libraryId: bId), 0)
    }

    func testBookmarkRoundTrip() throws {
        let folder = try makeFolder("Bookmarked")
        let data = try BookmarkStore.makeBookmark(for: folder)
        let resolved = try BookmarkStore.resolve(data)
        XCTAssertEqual(realPath(resolved.url), realPath(folder))
        XCTAssertTrue(BookmarkStore.isReachableDirectory(resolved.url))
    }
    func testRelinkKeepsSoundIdsCollectionsWaveformsAndJournal() throws {
        let database = try TestSupport.database()
        let manager = LibraryManager(database: database)
        let original = try makeFolder("BeforeWithMetadata")
        let source = original.appendingPathComponent("kick.wav")
        try Data("audio".utf8).write(to: source)
        let libraryId = try XCTUnwrap(manager.add(url: original).id)
        let soundId = try database.writer.write { db in
            var sound = Sound(libraryId: libraryId, filePath: realPath(source), relativePath: "kick.wav", filename: "kick.wav", fileExtension: "wav", displayName: "My kick", displayNameSource: .manual)
            try sound.insert(db)
            try WaveformRecord(soundId: sound.id!, waveformData: Data([1, 2]), resolution: 2, generatedAt: Date()).insert(db)
            return sound.id!
        }
        let collections = CollectionStore(database: database)
        let collectionId = try XCTUnwrap(collections.create(name: "Keep").id)
        try collections.add(soundIds: [soundId], to: collectionId)
        let journal = OrganizeJournal(database: database)
        let root = original.appendingPathComponent("_Organized").path
        let outcome = OrganizeExecutor.run([.init(soundId: soundId, sourcePath: source.path, destination: "Kick.wav")], root: root, scope: "test", journal: journal)
        let renamed = scratch.appendingPathComponent("AfterWithMetadata")
        try FileManager.default.moveItem(at: original, to: renamed)
        _ = try manager.refreshAvailability()
        let sound = try database.writer.read { try Sound.fetchOne($0, key: soundId) }
        XCTAssertEqual(sound?.filePath, realPath(renamed.appendingPathComponent("kick.wav")))
        XCTAssertEqual(sound?.displayName, "My kick")
        XCTAssertEqual(try collections.count(collectionId: collectionId), 1)
        XCTAssertEqual(WaveformStore(database: database).cached(soundId: soundId), [1, 2])
        XCTAssertEqual(OrganizeExecutor.undo(batchId: outcome.batchId!, journal: journal).removed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.appendingPathComponent("kick.wav").path))
    }

    func testRelinkConflictRollsBackAllPathChanges() throws {
        let database = try TestSupport.database()
        let manager = LibraryManager(database: database)
        let original = try makeFolder("ConflictBefore")
        let renamed = scratch.appendingPathComponent("ConflictAfter")
        let id = try XCTUnwrap(manager.add(url: original).id)
        try database.writer.write { db in
            for path in [realPath(original.appendingPathComponent("kick.wav")), realPath(renamed.appendingPathComponent("kick.wav"))] {
                var sound = Sound(libraryId: id, filePath: path, relativePath: "kick.wav", filename: "kick.wav", fileExtension: "wav")
                try sound.insert(db)
            }
        }
        try FileManager.default.moveItem(at: original, to: renamed)
        XCTAssertThrowsError(try manager.refreshAvailability())
        XCTAssertEqual(try manager.library(id: id)?.rootPath, realPath(original))
        XCTAssertEqual(try manager.soundCount(libraryId: id), 2)
    }

}
