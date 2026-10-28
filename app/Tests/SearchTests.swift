import XCTest
import GRDB
@testable import FoleyLibrary

/// M7：搜尋與篩選。
///
/// 重點不是「找得到東西」，而是「找得到你自己整理過的東西」——
/// 分類、標籤、備註都必須是可搜尋的，否則整理就沒有回報。
final class SearchTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: SoundRepository!
    private var metadata: ManualMetadataService!
    private var libraryId: Int64!

    override func setUpWithError() throws {
        database = try TestSupport.database()
        repository = SoundRepository(database: database)
        metadata = ManualMetadataService(database: database)

        let library = try database.writer.write { db -> Library in
            var library = Library(name: "FX", rootPath: "/tmp/fx")
            try library.insert(db)
            return library
        }
        libraryId = try XCTUnwrap(library.id)
    }

    @discardableResult
    private func insert(_ filename: String,
                        folder: String = "",
                        duration: Double? = 2,
                        ext: String = "wav",
                        favorite: Bool = false,
                        rating: Int = 0) throws -> Int64 {
        let relative = folder.isEmpty ? filename : "\(folder)/\(filename)"
        let sound = try database.writer.write { db -> Sound in
            var sound = Sound(libraryId: libraryId,
                              filePath: "/tmp/fx/\(relative)",
                              relativePath: relative,
                              filename: filename,
                              fileExtension: ext,
                              duration: duration,
                              favorite: favorite,
                              rating: rating)
            try sound.insert(db)
            return sound
        }
        return try XCTUnwrap(sound.id)
    }

    private func names(_ search: String = "", filters: SoundFilters = SoundFilters()) throws -> [String] {
        try repository.fetch(filter: .all, search: search, filters: filters, limit: 100)
            .map(\.filename)
            .sorted()
    }

    // MARK: - 搜尋

    func testSearchMatchesFilename() throws {
        try insert("metal_door.wav")
        try insert("cloth_rustle.wav")

        XCTAssertEqual(try names("door"), ["metal_door.wav"])
    }

    func testSearchIsCaseInsensitive() throws {
        try insert("Metal_Door.wav")
        XCTAssertEqual(try names("metal").count, 1)
        XCTAssertEqual(try names("METAL").count, 1)
    }

    func testSearchMatchesDisplayName() throws {
        let id = try insert("REC_0384.wav")
        try metadata.setDisplayName("Heavy Metal Door Slam", soundId: id, source: .manual)

        XCTAssertEqual(try names("slam"), ["REC_0384.wav"])
    }

    func testSearchMatchesFolderPath() throws {
        try insert("a.wav", folder: "Whoosh To Hit")
        try insert("b.wav", folder: "Noise")

        XCTAssertEqual(try names("whoosh"), ["a.wav"])
    }

    /// 使用者手動分類之後，分類本身必須可搜尋。
    func testSearchMatchesCategory() throws {
        let id = try insert("REC_001.wav")
        try metadata.setCategory(path: "Foley/Doors", soundId: id, source: .manual)
        try insert("REC_002.wav")

        XCTAssertEqual(try names("doors"), ["REC_001.wav"])
    }

    func testSearchMatchesTags() throws {
        let id = try insert("unnamed.wav")
        try metadata.addTag("ceramic", soundId: id)
        try insert("other.wav")

        XCTAssertEqual(try names("ceramic"), ["unnamed.wav"])
    }

    func testSearchMatchesNotes() throws {
        let id = try insert("x.wav")
        try metadata.setNotes("適合工業場景", soundId: id)

        XCTAssertEqual(try names("工業"), ["x.wav"])
    }

    /// 多個詞之間是 AND：「metal door」只找同時符合兩者的。
    func testMultipleTermsAreCombinedWithAnd() throws {
        let both = try insert("slam_01.wav")
        try metadata.setDisplayName("Metal Door Slam", soundId: both, source: .manual)

        let onlyMetal = try insert("slam_02.wav")
        try metadata.setDisplayName("Metal Impact", soundId: onlyMetal, source: .manual)

        XCTAssertEqual(try names("metal door"), ["slam_01.wav"])
        XCTAssertEqual(try names("metal").count, 2)
    }

    func testTermsCanMatchDifferentFields() throws {
        let id = try insert("REC_77.wav", folder: "Impacts")
        try metadata.addTag("metal", soundId: id)
        try insert("REC_78.wav", folder: "Impacts")

        // 一個詞來自資料夾、一個來自標籤
        XCTAssertEqual(try names("impacts metal"), ["REC_77.wav"])
    }

    func testEmptySearchReturnsEverything() throws {
        try insert("a.wav")
        try insert("b.wav")
        XCTAssertEqual(try names("").count, 2)
    }

    // MARK: - 篩選

    func testFavouritesFilter() throws {
        try insert("kept.wav", favorite: true)
        try insert("plain.wav")

        var filters = SoundFilters()
        filters.favoritesOnly = true
        XCTAssertEqual(try names(filters: filters), ["kept.wav"])
    }

    func testRatingFilter() throws {
        try insert("four.wav", rating: 4)
        try insert("two.wav", rating: 2)

        var filters = SoundFilters()
        filters.minRating = 3
        XCTAssertEqual(try names(filters: filters), ["four.wav"])
    }

    func testDurationBands() throws {
        try insert("tick.wav", duration: 0.4)
        try insert("hit.wav", duration: 2.5)
        try insert("drone.wav", duration: 30)

        var filters = SoundFilters()
        filters.duration = .short
        XCTAssertEqual(try names(filters: filters), ["tick.wav"])

        filters.duration = .medium
        XCTAssertEqual(try names(filters: filters), ["hit.wav"])

        filters.duration = .long
        XCTAssertEqual(try names(filters: filters), ["drone.wav"])
    }

    func testDurationFilterSkipsSoundsWithoutDuration() throws {
        try insert("unknown.wav", duration: nil)
        try insert("known.wav", duration: 2)

        var filters = SoundFilters()
        filters.duration = .medium
        XCTAssertEqual(try names(filters: filters), ["known.wav"])
    }

    func testFileTypeFilter() throws {
        try insert("a.wav", ext: "wav")
        try insert("b.aiff", ext: "aiff")
        try insert("c.mp3", ext: "mp3")

        var filters = SoundFilters()
        filters.fileTypes = ["aiff", "mp3"]
        XCTAssertEqual(try names(filters: filters), ["b.aiff", "c.mp3"])
    }

    func testFiltersCombineWithSearch() throws {
        let id = try insert("metal_hit.wav", favorite: true)
        try metadata.addTag("metal", soundId: id)
        try insert("metal_miss.wav")

        var filters = SoundFilters()
        filters.favoritesOnly = true
        XCTAssertEqual(try names("metal", filters: filters), ["metal_hit.wav"])
    }

    func testCountMatchesFetchUnderSearch() throws {
        for index in 0..<7 { try insert("door_\(index).wav") }
        try insert("cloth.wav")

        XCTAssertEqual(try repository.count(filter: .all, search: "door"), 7)
        XCTAssertEqual(try repository.fetch(filter: .all, search: "door", limit: 100).count, 7)
    }

    func testAvailableFileTypes() throws {
        try insert("a.wav", ext: "wav")
        try insert("b.aiff", ext: "aiff")
        try insert("c.wav", ext: "wav")

        XCTAssertEqual(try repository.availableFileTypes(), ["aiff", "wav"])
    }

    func testFiltersAreInactiveByDefault() {
        XCTAssertFalse(SoundFilters().isActive)
        var filters = SoundFilters()
        filters.minRating = 1
        XCTAssertTrue(filters.isActive)
        filters.clear()
        XCTAssertFalse(filters.isActive)
    }
}
