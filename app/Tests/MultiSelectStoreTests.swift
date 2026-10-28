import XCTest
@testable import FoleyLibrary

/// 複選接上 store 之後的行為。模型本身的測試在 `SoundSelectionTests`。
///
/// 這裡守的是接線容易出錯的那幾處：`selectedSoundId` 同時是「焦點」也是
/// 單選的來源，一不小心就會在換頁時把整批選取一起洗掉。
@MainActor
final class MultiSelectStoreTests: XCTestCase {

    private struct NoFolderPicker: FolderPicker {
        func pickFolders() -> [URL] { [] }
    }

    /// `services` 在 store 裡是 private，所以測試自己留一份同一個資料庫的 store。
    private struct Harness {
        let store: LibraryStore
        let sounds: [Sound]
        let collections: CollectionStore
        let repository: SoundRepository
    }

    private func makeStore(soundCount: Int) throws -> Harness {
        let taxonomy = try TestSupport.taxonomy()
        let vocabulary = try TestSupport.vocabulary()
        let database = try AppDatabase.makeInMemory(taxonomy: taxonomy)
        let validator = OrganizerSchemaValidator(taxonomy: taxonomy, vocabulary: vocabulary)

        let sounds: [Sound] = try database.writer.write { db in
            var library = Library(name: "Test", rootPath: "/tmp/test")
            try library.insert(db)
            return try (0..<soundCount).map { index in
                let name = String(format: "sound_%03d.wav", index)
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

        let collections = CollectionStore(database: database)
        let repository = SoundRepository(database: database)
        let services = AppEnvironment.Services(
            taxonomy: taxonomy,
            vocabulary: vocabulary,
            styles: try TestSupport.styles(),
            textures: try TestSupport.textures(),
            database: database,
            repository: repository,
            collections: collections,
            metadata: ManualMetadataService(database: database),
            review: ReviewService(database: database),
            mapper: OrganizerResultMapper(validator: validator, policy: .default),
            validator: validator,
            organizer: LocalAnalysisEngine(taxonomy: taxonomy, vocabulary: vocabulary),
            libraryManager: LibraryManager(database: database),
            scanner: LibraryScanner(database: database),
            waveforms: WaveformStore(database: database),
            folderPicker: NoFolderPicker())

        let store = LibraryStore(services: services)
        store.pageSize = 20
        return Harness(store: store, sounds: sounds, collections: collections, repository: repository)
    }

    // MARK: - 焦點與複選的關係

    func testPlainSelectionReplacesTheMultiSelection() {
        let store = try! makeStore(soundCount: 45).store
        store.selectAllOnPage()
        XCTAssertEqual(store.selection.count, 20)
        store.selectOnly(store.pageIds[3])
        XCTAssertEqual(store.selection.count, 1)
    }

    func testSelectionSurvivesPagingAway() throws {
        // 41,293 個檔案、每頁 20 筆。選到一半換頁被清掉的話複選等於沒用。
        let harness = try makeStore(soundCount: 45)
        let store = harness.store
        store.selectAllOnPage()
        let before = store.selection.sortedIds

        store.nextPage()

        XCTAssertEqual(store.selection.sortedIds, before,
                       "換頁清掉焦點是對的，清掉整批選取不是")
        XCTAssertNil(store.selectedSound, "焦點仍然要跟著當前頁")
    }

    func testSelectingAcrossPagesAccumulates() throws {
        let harness = try makeStore(soundCount: 45)
        let store = harness.store
        store.selectAllOnPage()
        store.nextPage()
        store.selectAllOnPage()
        XCTAssertEqual(store.selection.count, 40)
    }

    // MARK: - 批次動作

    func testBatchAddPutsTheWholeSelectionInTheCollection() throws {
        let harness = try makeStore(soundCount: 45)
        let store = harness.store
        let collection = try harness.collections.create(name: "測試分頁")
        store.selectAllOnPage()

        let added = store.addSelectionToCollection(collection.id ?? 0)

        XCTAssertEqual(added, 20)
        XCTAssertEqual(try harness.collections.count(collectionId: collection.id ?? 0), 20)
    }

    func testBatchAddDoesNotDuplicateWhatIsAlreadyThere() throws {
        let harness = try makeStore(soundCount: 45)
        let store = harness.store
        let collection = try harness.collections.create(name: "測試分頁")
        store.selectAllOnPage()
        store.addSelectionToCollection(collection.id ?? 0)

        let addedAgain = store.addSelectionToCollection(collection.id ?? 0)

        XCTAssertEqual(addedAgain, 0)
        XCTAssertEqual(try harness.collections.count(collectionId: collection.id ?? 0), 20)
    }

    func testWithoutMultiSelectionBatchActionsStillCoverTheFocusedRow() throws {
        // 右鍵選單不必分兩套寫法：沒有複選時對象就是焦點那一列。
        let harness = try makeStore(soundCount: 45)
        let store = harness.store
        let collection = try harness.collections.create(name: "測試分頁")
        store.selectOnly(store.pageIds[2])

        XCTAssertEqual(store.actionTargets.count, 1)
        XCTAssertEqual(store.addSelectionToCollection(collection.id ?? 0), 1)
    }

    func testBatchRemoveDoesNotTouchTheFilesThemselves() throws {
        // 文案與行為都是規格的一部分：從分頁移出不是刪除。
        let harness = try makeStore(soundCount: 45)
        let store = harness.store
        let sounds = harness.sounds
        let collection = try harness.collections.create(name: "測試分頁")
        store.selectAllOnPage()
        store.addSelectionToCollection(collection.id ?? 0)

        store.selectCollection(collection.id)
        store.selectAllOnPage()
        store.removeSelectionFromCurrentCollection()

        XCTAssertEqual(try harness.collections.count(collectionId: collection.id ?? 0), 0)
        XCTAssertEqual(try harness.repository.count(filter: .all), sounds.count,
                       "音檔一個都不可以少")
    }

    // MARK: - 拖曳整批進分頁

    func testDraggingARowThatIsInTheSelectionCarriesTheWholeSelection() throws {
        // macOS 的 onDrag 一次只給一個檔案 URL，所以放下的那一端
        // 必須自己判斷「被拖的那一列在不在選取裡」。
        let harness = try makeStore(soundCount: 45)
        let store = harness.store
        let collection = try harness.collections.create(name: "測試分頁")
        store.selectAllOnPage()

        let dragged = URL(fileURLWithPath: harness.sounds[0].filePath)
        let added = store.addToCollection(collection.id ?? 0, urls: [dragged])

        XCTAssertEqual(added, 20, "拖的是選取裡的一列，整批都要進去")
    }

    func testDraggingARowOutsideTheSelectionOnlyCarriesThatRow() throws {
        // 不在選取裡就只是拖那一個，選取不動——Finder 也是這樣。
        let harness = try makeStore(soundCount: 45)
        let store = harness.store
        let collection = try harness.collections.create(name: "測試分頁")
        store.selectOnly(store.pageIds[0])
        store.toggleSelection(store.pageIds[1])

        let dragged = URL(fileURLWithPath: harness.sounds[5].filePath)
        let added = store.addToCollection(collection.id ?? 0, urls: [dragged])

        XCTAssertEqual(added, 1)
        XCTAssertEqual(store.selection.count, 2, "拖別的列不該改變選取")
    }

    func testASingleSelectionDragStillCarriesJustOne() throws {
        let harness = try makeStore(soundCount: 45)
        let store = harness.store
        let collection = try harness.collections.create(name: "測試分頁")
        store.selectOnly(store.pageIds[0])

        let dragged = URL(fileURLWithPath: harness.sounds[0].filePath)

        XCTAssertEqual(store.addToCollection(collection.id ?? 0, urls: [dragged]), 1)
    }

    func testFilesDraggedInFromFinderAlongsideASelectionAreKept() throws {
        let harness = try makeStore(soundCount: 45)
        let store = harness.store
        let collection = try harness.collections.create(name: "測試分頁")
        store.selectOnly(store.pageIds[0])
        store.toggleSelection(store.pageIds[1])

        // 選取裡的一列 + 一個不在選取裡的檔案一起放下。
        let urls = [URL(fileURLWithPath: harness.sounds[0].filePath),
                    URL(fileURLWithPath: harness.sounds[30].filePath)]

        XCTAssertEqual(store.addToCollection(collection.id ?? 0, urls: urls), 3)
    }

    func testAnUnknownFileFromFinderIsIgnoredRatherThanFailing() throws {
        let harness = try makeStore(soundCount: 45)
        let store = harness.store
        let collection = try harness.collections.create(name: "測試分頁")

        let stranger = URL(fileURLWithPath: "/tmp/not-in-the-library.wav")

        XCTAssertEqual(store.addToCollection(collection.id ?? 0, urls: [stranger]), 0)
    }

    // MARK: - ⇧ 方向鍵

    func testShiftArrowGrowsTheRangeFromTheAnchor() throws {
        let harness = try makeStore(soundCount: 45)
        let store = harness.store
        store.selectOnly(store.pageIds[2])

        store.extendSelectionByOneRow(forward: true)
        store.extendSelectionByOneRow(forward: true)

        XCTAssertEqual(store.selection.sortedIds, Array(store.pageIds[2...4]))
        XCTAssertEqual(store.selectedSoundId, store.pageIds[4], "焦點要跟著走到範圍的末端")
    }

    func testShiftArrowStopsAtThePageBoundaryInsteadOfPagingAway() throws {
        // 範圍是從錨點算的。翻頁之後錨點不在畫面上，再擴下去人看不出選到哪裡。
        let harness = try makeStore(soundCount: 45)
        let store = harness.store
        store.selectOnly(store.pageIds[19])

        store.extendSelectionByOneRow(forward: true)

        XCTAssertEqual(store.page, 0)
        XCTAssertEqual(store.selection.count, 1)
    }
}
