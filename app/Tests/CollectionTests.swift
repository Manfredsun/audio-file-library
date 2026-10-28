import XCTest
@testable import FoleyLibrary

/// 虛擬資料夾的資料層。
///
/// 最重要的不是「能不能加進去」，是**不變量**：
/// 從分頁移除不等於刪除檔案，手動排的順序不會被程式動到。
final class CollectionTests: XCTestCase {

    private var database: AppDatabase!
    private var store: CollectionStore!
    private var repository: SoundRepository!
    private var sounds: [Sound] = []

    override func setUpWithError() throws {
        database = try TestSupport.database()
        store = CollectionStore(database: database)
        repository = SoundRepository(database: database)
        sounds = try database.writer.write { db in
            var library = Library(name: "Test", rootPath: "/tmp/test")
            try library.insert(db)
            return try (0..<8).map { index in
                let name = String(format: "sound_%02d.wav", index)
                var sound = Sound(libraryId: library.id ?? 0,
                                  filePath: "/tmp/test/\(name)",
                                  relativePath: name,
                                  filename: name,
                                  fileExtension: "wav",
                                  duration: 1)
                try sound.insert(db)
                return sound
            }
        }
    }

    private func id(_ index: Int) -> Int64 { sounds[index].id ?? 0 }

    private func soundCount() throws -> Int {
        try database.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sounds") ?? 0 }
    }

    // MARK: - 分頁本身

    func testNewCollectionsAreAppendedInOrder() throws {
        try store.create(name: "第一個")
        try store.create(name: "第二個")
        try store.create(name: "第三個")
        XCTAssertEqual(try store.all().map(\.name), ["第一個", "第二個", "第三個"])
    }

    func testRenaming() throws {
        let collection = try store.create(name: "暫定")
        try store.rename(id: collection.id ?? 0, to: "今天的專案")
        XCTAssertEqual(try store.all().first?.name, "今天的專案")
    }

    func testRenamingToBlankIsIgnored() throws {
        // 空字串的分頁在分頁列上是一個看不見的缺口，點不到也找不回來。
        let collection = try store.create(name: "有名字")
        try store.rename(id: collection.id ?? 0, to: "   ")
        XCTAssertEqual(try store.all().first?.name, "有名字")
    }

    func testReorderingCollections() throws {
        let a = try store.create(name: "A")
        let b = try store.create(name: "B")
        let c = try store.create(name: "C")
        try store.reorder(ids: [c.id ?? 0, a.id ?? 0, b.id ?? 0])
        XCTAssertEqual(try store.all().map(\.name), ["C", "A", "B"])
    }

    // MARK: - 成員

    func testAddingSounds() throws {
        let collection = try store.create(name: "分頁")
        let added = try store.add(soundIds: [id(0), id(1), id(2)], to: collection.id ?? 0)
        XCTAssertEqual(added, 3)
        XCTAssertEqual(try store.soundIds(in: collection.id ?? 0), [id(0), id(1), id(2)])
    }

    func testAddingTheSameSoundTwiceDoesNotDuplicateIt() throws {
        let collection = try store.create(name: "分頁")
        try store.add(soundIds: [id(0)], to: collection.id ?? 0)
        let again = try store.add(soundIds: [id(0)], to: collection.id ?? 0)
        XCTAssertEqual(again, 0)
        XCTAssertEqual(try store.count(collectionId: collection.id ?? 0), 1)
    }

    func testReaddingAnExistingSoundDoesNotMoveIt() throws {
        // 拖第二次不該把它甩到最後面——那會毀掉使用者手動排好的順序。
        let collection = try store.create(name: "分頁")
        try store.add(soundIds: [id(0), id(1), id(2)], to: collection.id ?? 0)
        try store.add(soundIds: [id(0)], to: collection.id ?? 0)
        XCTAssertEqual(try store.soundIds(in: collection.id ?? 0), [id(0), id(1), id(2)])
    }

    func testOneSoundCanLiveInManyCollections() throws {
        let a = try store.create(name: "A")
        let b = try store.create(name: "B")
        let c = try store.create(name: "C")
        for collection in [a, b, c] {
            try store.add(soundIds: [id(0)], to: collection.id ?? 0)
        }
        XCTAssertTrue(try store.contains(soundId: id(0), in: a.id ?? 0))
        XCTAssertTrue(try store.contains(soundId: id(0), in: b.id ?? 0))
        XCTAssertTrue(try store.contains(soundId: id(0), in: c.id ?? 0))
    }

    // MARK: - 不變量：絕不碰檔案

    func testRemovingFromACollectionDoesNotDeleteTheSound() throws {
        let collection = try store.create(name: "分頁")
        try store.add(soundIds: [id(0), id(1)], to: collection.id ?? 0)
        let before = try soundCount()

        try store.remove(soundIds: [id(0)], from: collection.id ?? 0)

        XCTAssertEqual(try soundCount(), before, "從分頁移除不是刪除音效")
        XCTAssertNotNil(try repository.sound(id: id(0)))
        XCTAssertEqual(try repository.sound(id: id(0))?.filePath, sounds[0].filePath,
                       "檔案路徑也不該被動到")
    }

    func testDeletingACollectionDoesNotDeleteAnySound() throws {
        let collection = try store.create(name: "分頁")
        try store.add(soundIds: sounds.compactMap(\.id), to: collection.id ?? 0)
        let before = try soundCount()

        try store.delete(id: collection.id ?? 0)

        XCTAssertEqual(try soundCount(), before, "刪除分頁只刪那份名單")
        XCTAssertTrue(try store.all().isEmpty)
    }

    // MARK: - 不變量：手動排的順序不會被程式動到

    func testManualOrderSurvivesRemovingAnotherItem() throws {
        let collection = try store.create(name: "分頁")
        let cid = collection.id ?? 0
        try store.add(soundIds: [id(0), id(1), id(2), id(3)], to: cid)
        try store.reorderSounds([id(3), id(1), id(0), id(2)], in: cid)

        try store.remove(soundIds: [id(1)], from: cid)

        XCTAssertEqual(try store.soundIds(in: cid), [id(3), id(0), id(2)],
                       "移除一筆不該讓其餘的順序被重排")
    }

    func testManualOrderSurvivesAddingMore() throws {
        let collection = try store.create(name: "分頁")
        let cid = collection.id ?? 0
        try store.add(soundIds: [id(0), id(1)], to: cid)
        try store.reorderSounds([id(1), id(0)], in: cid)

        try store.add(soundIds: [id(2)], to: cid)

        XCTAssertEqual(try store.soundIds(in: cid), [id(1), id(0), id(2)],
                       "新加的排在最後，既有順序不動")
    }

    // MARK: - 篩選與翻頁

    func testFilteringByCollectionReturnsMembersInManualOrder() throws {
        let collection = try store.create(name: "分頁")
        let cid = collection.id ?? 0
        try store.add(soundIds: [id(0), id(1), id(2)], to: cid)
        try store.reorderSounds([id(2), id(0), id(1)], in: cid)

        let fetched = try repository.fetch(filter: .collection(cid), limit: 100)
        XCTAssertEqual(fetched.compactMap(\.id), [id(2), id(0), id(1)],
                       "分頁必須照手動順序，不是照路徑")
    }

    func testCollectionCountMatchesMembership() throws {
        let collection = try store.create(name: "分頁")
        let cid = collection.id ?? 0
        try store.add(soundIds: [id(0), id(1), id(2), id(3), id(4)], to: cid)
        XCTAssertEqual(try repository.count(filter: .collection(cid)), 5)
    }

    func testCollectionPagination() throws {
        let collection = try store.create(name: "分頁")
        let cid = collection.id ?? 0
        try store.add(soundIds: sounds.compactMap(\.id), to: cid)   // 8 筆

        let firstPage = try repository.fetch(filter: .collection(cid), limit: 3, offset: 0)
        let secondPage = try repository.fetch(filter: .collection(cid), limit: 3, offset: 3)
        let lastPage = try repository.fetch(filter: .collection(cid), limit: 3, offset: 6)

        XCTAssertEqual(firstPage.compactMap(\.id), [id(0), id(1), id(2)])
        XCTAssertEqual(secondPage.compactMap(\.id), [id(3), id(4), id(5)])
        XCTAssertEqual(lastPage.count, 2, "最後一頁不滿是正常的")
        XCTAssertTrue(try repository.fetch(filter: .collection(cid), limit: 3, offset: 9).isEmpty)
    }

    func testEmptyCollection() throws {
        let collection = try store.create(name: "空的")
        let cid = collection.id ?? 0
        XCTAssertEqual(try repository.count(filter: .collection(cid)), 0)
        XCTAssertTrue(try repository.fetch(filter: .collection(cid), limit: 20).isEmpty)
    }

    func testSearchStillWorksInsideACollection() throws {
        let collection = try store.create(name: "分頁")
        let cid = collection.id ?? 0
        try store.add(soundIds: [id(0), id(1), id(2)], to: cid)
        let hits = try repository.fetch(filter: .collection(cid), search: "sound_01", limit: 20)
        XCTAssertEqual(hits.compactMap(\.id), [id(1)])
    }

    // MARK: - 刪除音效時的連帶

    func testDeletingASoundRemovesItFromCollections() throws {
        // 音色庫被移除時，成員列要跟著消失，不能留下指向不存在音效的孤兒列。
        let collection = try store.create(name: "分頁")
        let cid = collection.id ?? 0
        try store.add(soundIds: [id(0), id(1)], to: cid)

        try database.writer.write { db in
            _ = try Sound.deleteOne(db, key: id(0))
        }

        XCTAssertEqual(try store.soundIds(in: cid), [id(1)])
    }
}

/// 分頁內重排的純邏輯。
///
/// 用「搬到某一筆前面」而不是索引，是因為索引會被翻頁弄亂——
/// 當前頁的第 3 列在整個分頁裡可能是第 63 筆。
final class CollectionReorderTests: XCTestCase {

    private let list: [Int64] = [10, 20, 30, 40, 50]

    private func move(_ moving: [Int64], before target: Int64, in all: [Int64]? = nil) -> [Int64]? {
        CollectionStore.reordering(all: all ?? list, moving: moving, before: target)
    }

    func testMovingOneItemForward() {
        XCTAssertEqual(move([40], before: 20), [10, 40, 20, 30, 50])
    }

    func testMovingOneItemBackward() {
        XCTAssertEqual(move([20], before: 50), [10, 30, 40, 20, 50])
    }

    func testMovingToTheVeryFront() {
        XCTAssertEqual(move([50], before: 10), [50, 10, 20, 30, 40])
    }

    func testMovingSeveralKeepsTheirRelativeOrder() {
        // 一次拖多筆時，它們之間的順序也是使用者排的，不能被打散。
        XCTAssertEqual(move([40, 10], before: 30), [20, 40, 10, 30, 50])
    }

    func testDroppingOntoItselfDoesNothing() {
        XCTAssertNil(move([30], before: 30))
    }

    func testTargetNotInTheListIsRefused() {
        // 寧可什麼都不做，也不要猜一個位置塞進去。
        XCTAssertNil(move([10], before: 999))
    }

    func testEmptyMoveIsRefused() {
        XCTAssertNil(move([], before: 30))
    }

    func testNewcomerIsInsertedAtTheTargetPosition() {
        // 從 LIBRARY 拖一個還不在分頁裡的音檔進來。
        XCTAssertEqual(move([99], before: 30), [10, 20, 99, 30, 40, 50])
    }

    func testEveryOriginalItemSurvivesAMove() {
        for target in list {
            for moving in list where moving != target {
                let result = move([moving], before: target)
                XCTAssertEqual(result.map(Set.init), Set(list),
                               "搬動 \(moving) 到 \(target) 前面時掉了東西")
                XCTAssertEqual(result?.count, list.count)
            }
        }
    }
}

/// 依分類自動建立分頁。
final class AutoFillTests: XCTestCase {

    private var database: AppDatabase!
    private var store: CollectionStore!
    private var libraryId: Int64 = 0

    override func setUpWithError() throws {
        database = try TestSupport.database()
        store = CollectionStore(database: database)
        libraryId = try database.writer.write { db in
            var library = Library(name: "Test", rootPath: "/tmp/test")
            try library.insert(db)
            return library.id ?? 0
        }
    }

    /// 建立 `count` 個屬於 `path` 分類的音效。
    private func sounds(_ count: Int, category path: String?, prefix: String) throws {
        try database.writer.write { db in
            let categoryId = path.flatMap { p in
                try? Int64.fetchOne(db, sql: "SELECT id FROM categories WHERE path = ?", arguments: [p])
            }
            for index in 0..<count {
                let name = String(format: "%@_%03d.wav", prefix, index)
                var sound = Sound(libraryId: libraryId,
                                  filePath: "/tmp/test/\(name)",
                                  relativePath: name,
                                  filename: name,
                                  fileExtension: "wav",
                                  duration: 1)
                sound.categoryId = categoryId
                sound.categorySource = categoryId == nil ? nil : .acceptedAI
                try sound.insert(db)
            }
        }
    }

    func testCandidatesRespectTheMinimum() throws {
        try sounds(30, category: "Drums/Kick", prefix: "kick")
        try sounds(5, category: "Drums/Snare", prefix: "snare")

        XCTAssertEqual(try store.autoFillCandidates(minCount: 20).map(\.path), ["Drums/Kick"])
        XCTAssertEqual(try store.autoFillCandidates(minCount: 100), [])
        XCTAssertEqual(Set(try store.autoFillCandidates(minCount: 5).map(\.path)),
                       ["Drums/Kick", "Drums/Snare"])
    }

    func testUnclassifiedSoundsAreIgnored() throws {
        // 分頁是從已經接受的分類來的，沒有分類的音效不該憑空生出分頁。
        try sounds(50, category: nil, prefix: "unknown")
        XCTAssertEqual(try store.autoFillCandidates(minCount: 10), [])
    }

    func testAutoFillCreatesOneCollectionPerCategory() throws {
        try sounds(30, category: "Drums/Kick", prefix: "kick")
        try sounds(25, category: "Drums/Snare", prefix: "snare")

        let result = try store.autoFillByCategory(minCount: 20)

        XCTAssertEqual(result.collectionsCreated, 2)
        XCTAssertEqual(result.soundsAdded, 55)
        XCTAssertEqual(Set(try store.all().map(\.name)), ["Drums/Kick", "Drums/Snare"])
    }

    func testMembersAreOrderedByPath() throws {
        try sounds(3, category: "Drums/Kick", prefix: "kick")
        try store.autoFillByCategory(minCount: 1)
        let collection = try XCTUnwrap(try store.all().first)
        let names = try database.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT s.filename FROM collection_sounds cs
                  JOIN sounds s ON s.id = cs.sound_id
                 WHERE cs.collection_id = ? ORDER BY cs.sort_order
                """, arguments: [collection.id ?? 0])
        }
        XCTAssertEqual(names, ["kick_000.wav", "kick_001.wav", "kick_002.wav"])
    }

    func testRunningTwiceDoesNotCreateDuplicateCollectionsOrMembers() throws {
        // 重跑一次不該產生「Drums/Kick 2」這種東西，也不該讓成員變兩倍。
        try sounds(30, category: "Drums/Kick", prefix: "kick")
        try store.autoFillByCategory(minCount: 20)
        let second = try store.autoFillByCategory(minCount: 20)

        XCTAssertEqual(second.collectionsCreated, 0)
        XCTAssertEqual(second.soundsAdded, 0)
        XCTAssertEqual(try store.all().count, 1)
        XCTAssertEqual(try store.count(collectionId: try XCTUnwrap(store.all().first?.id)), 30)
    }

    func testNewSoundsAreAppendedToAnExistingCollection() throws {
        try sounds(30, category: "Drums/Kick", prefix: "kick")
        try store.autoFillByCategory(minCount: 20)
        try sounds(5, category: "Drums/Kick", prefix: "later")

        let second = try store.autoFillByCategory(minCount: 20)

        XCTAssertEqual(second.collectionsCreated, 0)
        XCTAssertEqual(second.soundsAdded, 5)
    }

    func testManualOrderIsNotRewrittenByASecondRun() throws {
        // 快照不是動態查詢：填進去之後就是使用者的，程式不准回頭重排。
        try sounds(3, category: "Drums/Kick", prefix: "kick")
        try store.autoFillByCategory(minCount: 1)
        let collectionId = try XCTUnwrap(store.all().first?.id)
        let ids = try store.soundIds(in: collectionId)
        try store.reorderSounds(ids.reversed(), in: collectionId)

        try store.autoFillByCategory(minCount: 1)

        XCTAssertEqual(try store.soundIds(in: collectionId), ids.reversed(),
                       "使用者排過的順序，第二次執行不得動到")
    }

    func testAutoFillNeverTouchesSounds() throws {
        try sounds(30, category: "Drums/Kick", prefix: "kick")
        let before = try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT file_path FROM sounds ORDER BY id")
        }
        try store.autoFillByCategory(minCount: 20)
        let after = try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT file_path FROM sounds ORDER BY id")
        }
        XCTAssertEqual(before, after)
    }
}
