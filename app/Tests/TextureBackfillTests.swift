import XCTest
import GRDB
@testable import FoleyLibrary

/// 材質要碰得到才算做完（D-026）：能回填、能篩選、能搜尋。
final class TextureBackfillTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: SoundRepository!
    private var vocabulary: TextureVocabulary!
    private var libraryId: Int64!

    override func setUpWithError() throws {
        database = try TestSupport.database()
        repository = SoundRepository(database: database)
        vocabulary = try TestSupport.textures()
        libraryId = try database.writer.write { db in
            var library = Library(name: "Test", rootPath: "/tmp/test")
            try library.insert(db)
            return library.id ?? 0
        }
    }

    @discardableResult
    private func insert(_ relativePath: String,
                        texture: String? = nil,
                        source: MetadataSource? = nil) throws -> Int64 {
        try database.writer.write { db in
            var sound = Sound(libraryId: libraryId,
                              filePath: "/tmp/test/\(relativePath)",
                              relativePath: relativePath,
                              filename: (relativePath as NSString).lastPathComponent,
                              fileExtension: "wav",
                              duration: 1,
                              texture: texture,
                              textureSource: source)
            try sound.insert(db)
            return sound.id ?? 0
        }
    }

    private func texture(of id: Int64) throws -> String? {
        try database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT texture FROM sounds WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - 回填

    func testBackfillReadsTheTextureFromThePath() throws {
        let id = try insert("Foley/metal_door_slam.wav")
        let result = TextureBackfill.run(database: database, vocabulary: vocabulary)

        XCTAssertEqual(result.filled, 1)
        XCTAssertEqual(try texture(of: id), "Metal")
    }

    func testBackfillTouchesNoAudioFiles() throws {
        // 材質是從 relative_path 讀的，那個欄位早就在資料庫裡。
        // 檔案根本不存在也要能回填——這就是為什麼四萬多筆不用重新分析。
        let id = try insert("Foley/wooden_chair_creak.wav")
        TextureBackfill.run(database: database, vocabulary: vocabulary)
        XCTAssertEqual(try texture(of: id), "Wood")
    }

    func testBackfillNeverOverwritesAManualValue() throws {
        // 手動放的東西程式不准自作聰明去動（CLAUDE.md §57 第三條）。
        let id = try insert("Foley/metal_door_slam.wav", texture: "Wood", source: .manual)
        let result = TextureBackfill.run(database: database, vocabulary: vocabulary)

        XCTAssertEqual(result.skippedManual, 1)
        XCTAssertEqual(try texture(of: id), "Wood", "人工設定的值不可以被蓋掉")
    }

    func testBackfillLeavesItEmptyWhenThePathSaysNothing() throws {
        let id = try insert("Ambience/city_street_evening.wav")
        TextureBackfill.run(database: database, vocabulary: vocabulary)
        XCTAssertNil(try texture(of: id), "讀不到就留空，不猜")
    }

    func testBackfillCanBeStopped() throws {
        for index in 1...5 { try insert("Foley/metal_hit_\(index).wav") }
        var seen = 0
        let result = TextureBackfill.run(database: database,
                                         vocabulary: vocabulary,
                                         shouldContinue: { seen += 1; return seen <= 2 })
        XCTAssertLessThan(result.scanned, 5)
    }

    // MARK: - 碰得到（D-026）

    func testFilteringByTextureWorks() throws {
        try insert("Foley/metal_door_slam.wav")
        try insert("Foley/wooden_chair_creak.wav")
        TextureBackfill.run(database: database, vocabulary: vocabulary)

        let metal = try repository.fetch(filter: .texture("Metal"), limit: 50)
        XCTAssertEqual(metal.count, 1)
        XCTAssertEqual(metal.first?.filename, "metal_door_slam.wav")
    }

    func testSearchFindsSoundsByTexture() throws {
        // 搜尋「metal」要找得到，即使檔名裡沒有那個字。
        try insert("Foley/door_slam_heavy.wav", texture: "Metal", source: .imported)
        let found = try repository.fetch(filter: .all, search: "metal", limit: 50)
        XCTAssertEqual(found.count, 1)
    }

    func testTextureCountsPowerTheSidebar() throws {
        try insert("Foley/metal_door_slam.wav")
        try insert("Foley/metal_pipe_hit.wav")
        try insert("Foley/wooden_chair_creak.wav")
        TextureBackfill.run(database: database, vocabulary: vocabulary)

        let counts = try repository.textureCounts()
        XCTAssertEqual(counts.first?.texture, "Metal", "多的在前")
        XCTAssertEqual(counts.first?.count, 2)
    }

    func testSettingATextureByHandMarksItManual() throws {
        let id = try insert("Foley/metal_door_slam.wav")
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sounds SET texture = ?, texture_source = ? WHERE id = ?",
                           arguments: ["Glass", MetadataSource.manual.rawValue, id])
        }
        TextureBackfill.run(database: database, vocabulary: vocabulary)
        XCTAssertEqual(try texture(of: id), "Glass")
    }
    func testAnInterleavedManualEditSurvivesThePendingWrite() throws {
        let id = try insert("Foley/metal_door_slam.wav")
        var edited = false
        _ = TextureBackfill.run(database: database, vocabulary: vocabulary, shouldContinue: {
            if !edited {
                edited = true
                do { try ManualMetadataService(database: self.database).setTexture(nil, soundId: id) }
                catch { XCTFail("manual edit failed: \(error)") }
            }
            return true
        })
        XCTAssertNil(try texture(of: id))
        let source = try database.writer.read { try String.fetchOne($0, sql: "SELECT texture_source FROM sounds WHERE id = ?", arguments: [id]) }
        XCTAssertEqual(source, "manual")
    }

    func testWriteFailureIsReportedWithoutCountingRolledBackChanges() throws {
        _ = try insert("Lo-Fi Pack/metal_kick.wav")
        try database.writer.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_write BEFORE UPDATE OF texture ON sounds BEGIN SELECT RAISE(ABORT, 'test write failure'); END")
        }
        let result = TextureBackfill.run(database: database, vocabulary: vocabulary)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertEqual(result.filled, 0)
    }

}
