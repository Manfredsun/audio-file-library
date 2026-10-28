import XCTest
import GRDB
@testable import FoleyLibrary

final class LocalizedSearchTests: XCTestCase {
    private var database: AppDatabase!
    private var repository: SoundRepository!
    private var soundId: Int64!

    override func setUpWithError() throws {
        database = try TestSupport.database()
        repository = SoundRepository(database: database)
        var sound = try TestSupport.insertSound(into: database, filename: "fixture.wav")
        try database.writer.write { db in
            sound.categoryId = try Category.filter(Column("path") == "Foley/Doors").fetchOne(db)?.id
            sound.categorySource = .manual
            sound.style = "Hip Hop"
            sound.styleSource = .manual
            sound.texture = "Metal"
            sound.textureSource = .manual
            sound.displayName = "My unchanged name"
            sound.notes = "personal note"
            sound.favorite = true
            try sound.update(db)
        }
        soundId = sound.id
        _ = try TestSupport.insertSound(into: database, filename: "unrelated.wav")
    }
    private func ids(_ query: String, filters: SoundFilters = SoundFilters()) throws -> [Int64] {
        try repository.fetch(filter: .all, search: query, filters: filters, limit: 50).map(\.rowId)
    }
    func testChineseAndEnglishBuiltInNamesFindTheSameRecord() throws {
        for query in ["門", "Doors", "擬音", "嘻哈", "Hip Hop", "金屬", "Metal"] {
            XCTAssertEqual(try ids(query), [soundId], query)
        }
    }
    func testAliasesKeepAndAcrossWordsAndOrAcrossFields() throws {
        XCTAssertEqual(try ids("門 personal"), [soundId])
        XCTAssertEqual(try ids("門 missing-evidence"), [])
        XCTAssertEqual(try ids("金屬 嘻哈"), [soundId])
    }
    func testAliasesRemainParameterizedAndRespectFilters() throws {
        XCTAssertEqual(try ids("' OR 1=1 --"), [])
        var filter = SoundFilters()
        filter.minRating = 5
        XCTAssertEqual(try ids("門", filters: filter), [])
    }
    func testTranslationAndSearchNeverRewriteMetadataOrIdentity() throws {
        let before = try database.writer.read { try Sound.fetchAll($0).sorted { $0.id! < $1.id! } }
        _ = BuiltinNames.category("Foley/Doors", locale: "zh-Hant")
        _ = try ids("門 嘻哈")
        let after = try database.writer.read { try Sound.fetchAll($0).sorted { $0.id! < $1.id! } }
        XCTAssertEqual(before, after)
        XCTAssertEqual(after.first?.categorySource, .manual)
        XCTAssertEqual(after.first?.displayName, "My unchanged name")
    }
}
