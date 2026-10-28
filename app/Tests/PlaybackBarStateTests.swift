import XCTest
@testable import FoleyLibrary

/// 播放列在換頁／換篩選時的狀態。
///
/// 這條迴歸測試存在的理由很具體：`reload()` 會把不在當前頁的選取清掉，
/// 而播放列原本綁在選取上，所以使用者一邊聽一邊翻頁，播放列會整條空掉。
@MainActor
final class PlaybackBarStateTests: XCTestCase {

    private struct NoFolderPicker: FolderPicker {
        func pickFolders() -> [URL] { [] }
    }

    private func makeStore(soundCount: Int) throws -> (LibraryStore, [Sound]) {
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

        let services = AppEnvironment.Services(
            taxonomy: taxonomy,
            vocabulary: vocabulary,
            styles: try TestSupport.styles(),
            textures: try TestSupport.textures(),
            database: database,
            repository: SoundRepository(database: database),
            collections: CollectionStore(database: database),
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
        return (store, sounds)
    }

    func testSelectionIsClearedWhenItLeavesTheCurrentPage() throws {
        let (store, sounds) = try makeStore(soundCount: 45)
        store.selectedSoundId = sounds[0].rowId
        XCTAssertNotNil(store.selectedSound)

        store.nextPage()
        XCTAssertNil(store.selectedSound,
                     "選取留在看不見的位置會讓方向鍵行為變得莫名其妙")
    }

    func testPlaybackBarKeepsShowingTheSoundThatIsPlayingAfterPagingAway() throws {
        let (store, sounds) = try makeStore(soundCount: 45)
        let playing = sounds[0]
        store.selectedSoundId = playing.rowId
        store.startPreview(playing)

        store.nextPage()

        XCTAssertNil(store.selectedSound)
        XCTAssertEqual(store.barSound?.rowId, playing.rowId,
                       "換頁時播放列不該空掉——聲音還在響")
    }

    func testPlaybackBarFollowsSelectionWhenNothingIsPlaying() throws {
        let (store, sounds) = try makeStore(soundCount: 45)
        store.selectedSoundId = sounds[3].rowId

        XCTAssertEqual(store.barSound?.rowId, sounds[3].rowId,
                       "什麼都沒在播的時候，播放列預覽你選取的那一個")
    }

    func testSelectingAnotherSoundDoesNotStealThePlaybackBarWhilePlaying() throws {
        // 這條取代了原本「有選取就跟著選取走」的斷言。
        // 原本的行為在實際使用上是錯的：邊聽 A 邊點 B 看細節時，
        // 你聽到的是 A，波形卻在畫 B，播放游標還在 B 的時間軸上跑。
        let (store, sounds) = try makeStore(soundCount: 45)
        store.startPreview(sounds[0])
        store.selectedSoundId = sounds[3].rowId

        XCTAssertEqual(store.barSound?.rowId, sounds[0].rowId,
                       "播放中時，播放列與波形要跟著正在播的那一個")
    }

    func testChangingFilterAlsoKeepsThePlayingSound() throws {
        let (store, sounds) = try makeStore(soundCount: 10)
        let playing = sounds[0]
        store.selectedSoundId = playing.rowId
        store.startPreview(playing)

        // favorites 一個都沒有，清單會變空。
        store.filter = .favorites

        XCTAssertTrue(store.sounds.isEmpty)
        XCTAssertNil(store.selectedSound)
        XCTAssertEqual(store.barSound?.rowId, playing.rowId)
    }

    func testBarIsEmptyBeforeAnythingIsSelectedOrPlayed() throws {
        let (store, _) = try makeStore(soundCount: 5)
        XCTAssertNil(store.barSound)
    }

    func testPlayingSoundUpdatesWhenAnotherSoundIsPlayed() throws {
        let (store, sounds) = try makeStore(soundCount: 45)
        store.startPreview(sounds[0])
        store.startPreview(sounds[1])
        store.nextPage()
        XCTAssertEqual(store.barSound?.rowId, sounds[1].rowId)
    }
}
