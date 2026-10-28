import XCTest
import GRDB
@testable import FoleyLibrary

/// M6：人工標籤。
final class TagEditingTests: XCTestCase {

    private var database: AppDatabase!
    private var metadata: ManualMetadataService!
    private var repository: SoundRepository!
    private var soundId: Int64!

    override func setUpWithError() throws {
        database = try TestSupport.database()
        metadata = ManualMetadataService(database: database)
        repository = SoundRepository(database: database)
        let sound = try TestSupport.insertSound(into: database)
        soundId = try XCTUnwrap(sound.id)
    }

    func testAddingTagCreatesManualLink() throws {
        try metadata.addTag("metal", soundId: soundId)

        let tags = try repository.tags(soundId: soundId)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.name, "metal")
        XCTAssertEqual(tags.first?.source, .manual)
    }

    func testAddingTheSameTagTwiceDoesNotDuplicate() throws {
        try metadata.addTag("metal", soundId: soundId)
        try metadata.addTag("metal", soundId: soundId)

        XCTAssertEqual(try repository.tags(soundId: soundId).count, 1)
    }

    /// "Metal"、"metal"、" METAL " 是同一個標籤。
    /// 不做正規化的話，搜尋會因為大小寫而漏掉檔案。
    func testTagsAreCanonicalisedAcrossCasing() throws {
        try metadata.addTag("Metal", soundId: soundId)
        try metadata.addTag(" METAL ", soundId: soundId)

        let tags = try repository.tags(soundId: soundId)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.canonicalName, "metal")

        let allTags = try database.writer.read { db in try Tag.fetchCount(db) }
        XCTAssertEqual(allTags, 1, "全庫只該有一筆 metal 標籤")
    }

    func testEmptyTagIsIgnored() throws {
        try metadata.addTag("   ", soundId: soundId)
        try metadata.addTag("", soundId: soundId)

        XCTAssertEqual(try repository.tags(soundId: soundId).count, 0)
    }

    /// 移除標籤只解除關聯，標籤本身留著給別的音效用。
    func testRemovingTagKeepsTheTagItself() throws {
        try metadata.addTag("wood", soundId: soundId)
        let tag = try XCTUnwrap(try repository.tags(soundId: soundId).first)

        try metadata.removeTag(tagId: tag.id, soundId: soundId)

        XCTAssertTrue(try repository.tags(soundId: soundId).isEmpty)
        let remaining = try database.writer.read { db in try Tag.fetchCount(db) }
        XCTAssertEqual(remaining, 1, "標籤本身不該被刪除")
    }

    func testTagsAreSharedAcrossSounds() throws {
        let second = try database.writer.write { db -> Sound in
            var sound = Sound(libraryId: 1,
                              filePath: "/tmp/test/other.wav",
                              relativePath: "other.wav",
                              filename: "other.wav",
                              fileExtension: "wav")
            try sound.insert(db)
            return sound
        }
        let secondId = try XCTUnwrap(second.id)

        try metadata.addTag("glass", soundId: soundId)
        try metadata.addTag("glass", soundId: secondId)

        let allTags = try database.writer.read { db in try Tag.fetchCount(db) }
        XCTAssertEqual(allTags, 1, "兩個音效共用同一筆標籤紀錄")
        XCTAssertEqual(try repository.tags(soundId: soundId).count, 1)
        XCTAssertEqual(try repository.tags(soundId: secondId).count, 1)
    }

    /// 接受 AI 標籤與人工標籤來源不同，兩者都要看得出來。
    func testManualAndAcceptedAITagsAreDistinguishable() throws {
        let mapper = OrganizerResultMapper(validator: try TestSupport.validator(), policy: .default)
        try database.writer.write { db in
            try mapper.persist(result: MockOrganizerEngine.doorSlam,
                               soundId: soundId,
                               engine: "mock",
                               in: db)
        }

        let analysis = try XCTUnwrap(repository.latestAnalysis(soundId: soundId))
        let suggestions = try repository.suggestions(analysisId: analysis.id ?? 0)
        let tagSuggestion = try XCTUnwrap(suggestions.first { $0.field == .tag })
        try metadata.accept(suggestionId: tagSuggestion.id ?? 0)

        try metadata.addTag("industrial", soundId: soundId)

        let tags = try repository.tags(soundId: soundId)
        XCTAssertEqual(tags.count, 2)
        XCTAssertEqual(tags.filter { $0.source == .manual }.count, 1)
        XCTAssertEqual(tags.filter { $0.source == .acceptedAI }.count, 1)
    }

    func testCategoryPathsComeFromTaxonomy() throws {
        let paths = try repository.categoryPaths()
        XCTAssertTrue(paths.contains("Foley"))
        XCTAssertTrue(paths.contains("Foley/Doors"))
        XCTAssertTrue(paths.contains("Unclassified"))
        XCTAssertEqual(paths.count, try TestSupport.taxonomy().allPaths.count)
    }

    func testNotesAreStoredAndCleared() throws {
        try metadata.setNotes("適合工業場景", soundId: soundId)
        var sound = try XCTUnwrap(repository.sound(id: soundId))
        XCTAssertEqual(sound.notes, "適合工業場景")

        try metadata.setNotes(nil, soundId: soundId)
        sound = try XCTUnwrap(repository.sound(id: soundId))
        XCTAssertNil(sound.notes)
    }
}
