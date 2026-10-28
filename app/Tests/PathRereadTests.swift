import XCTest
import GRDB
@testable import FoleyLibrary

/// 只讀路徑的重算。**一個音檔都不開。**
final class PathRereadTests: XCTestCase {

    private var database: AppDatabase!
    private var libraryId: Int64!

    override func setUpWithError() throws {
        database = try TestSupport.database()
        libraryId = try database.writer.write { db in
            var library = Library(name: "Test", rootPath: "/tmp/test")
            try library.insert(db)
            return library.id ?? 0
        }
    }

    @discardableResult
    private func insert(_ relativePath: String,
                        style: String? = nil,
                        styleSource: MetadataSource? = nil) throws -> Int64 {
        try database.writer.write { db in
            var sound = Sound(libraryId: libraryId,
                              filePath: "/tmp/test/\(relativePath)",
                              relativePath: relativePath,
                              filename: (relativePath as NSString).lastPathComponent,
                              fileExtension: "wav",
                              duration: 1,
                              style: style,
                              styleSource: styleSource)
            try sound.insert(db)
            return sound.id ?? 0
        }
    }

    private func reread() throws -> PathRereadService.Result {
        PathRereadService.run(database: database,
                              taxonomy: try TestSupport.taxonomy(),
                              vocabulary: try TestSupport.vocabulary(),
                              styles: try TestSupport.styles(),
                              textures: try TestSupport.textures())
    }

    private func value(_ column: String, of id: Int64) throws -> String? {
        try database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT \(column) FROM sounds WHERE id = ?", arguments: [id])
        }
    }

    func testItNeverOpensAnAudioFile() throws {
        // 檔案根本不存在也要能重算——這就是為什麼四萬多筆不用重新分析。
        let id = try insert("Foley/Doors/metal_door_slam.wav")
        let result = try reread()
        XCTAssertGreaterThan(result.scanned, 0)
        XCTAssertEqual(try value("texture", of: id), "Metal")
    }

    func testItNeverWritesClassificationSuggestions() throws {
        // D-040：較弱的 path-only 結果不能再進 mapper，否則會蓋掉聲學建議。
        let id = try insert("Foley/Doors/wooden_door_creak.wav")
        try reread()
        let counts = try database.writer.read { db in
            let analyses = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM organizer_analysis") ?? -1
            let suggestions = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM organizer_suggestions") ?? -1
            let categoryId = try Int64.fetchOne(db, sql: "SELECT category_id FROM sounds WHERE id = ?",
                                                arguments: [id])
            return (analyses, suggestions, categoryId)
        }
        XCTAssertEqual(counts.0, 0)
        XCTAssertEqual(counts.1, 0)
        XCTAssertNil(counts.2, "重讀路徑不得直接寫分類")
    }

    func testExistingSuggestionStatusesRemainUnchanged() throws {
        let id = try insert("Foley/Doors/metal_door_slam.wav")
        let mapper = OrganizerResultMapper(validator: try TestSupport.validator())
        try database.writer.write { db in
            try mapper.persist(result: MockOrganizerEngine.doorSlam,
                               soundId: id,
                               engine: "local-acoustic",
                               in: db)
        }
        let before: [String] = try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT field, value, status FROM organizer_suggestions ORDER BY id
                """).map { "\($0["field"] as String)|\($0["value"] as String)|\($0["status"] as String)" }
        }

        try reread()
        let after: [String] = try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT field, value, status FROM organizer_suggestions ORDER BY id
                """).map { "\($0["field"] as String)|\($0["value"] as String)|\($0["status"] as String)" }
        }
        XCTAssertEqual(after, before, "重讀路徑不得新增、降級或改寫任何 Organizer 建議")
    }

    func testAManualStyleIsNeverOverwritten() throws {
        // 手動放的東西程式不准自作聰明去動（CLAUDE.md §57 第三條）。
        let id = try insert("Lo-Fi Pack/Drums/kick_01.wav", style: "Chiptune", styleSource: .manual)
        try reread()
        XCTAssertEqual(try value("style", of: id), "Chiptune")
    }

    func testLiteralTempoIsFilledButOnlyWhenTheFilenameSaysBpm() throws {
        // 黏在字母上的數字是編號不是節拍（D-027）。
        let withBpm = try insert("Loops/Top Loop 04 - 75 BPM.wav")
        let withNumber = try insert("Loops/SND387_hit.wav")
        try reread()

        let bpm = try database.writer.read { db in
            try Double.fetchOne(db, sql: "SELECT bpm FROM sounds WHERE id = ?", arguments: [withBpm])
        }
        XCTAssertEqual(bpm, 75)
        let none = try database.writer.read { db in
            try Double.fetchOne(db, sql: "SELECT bpm FROM sounds WHERE id = ?", arguments: [withNumber])
        }
        XCTAssertNil(none, "387 是編號，不是節拍")
    }

    func testItCanBeStopped() throws {
        for index in 1...600 { try insert("Foley/Doors/door_\(index).wav") }
        var ticks = 0
        let result = PathRereadService.run(database: database,
                                           taxonomy: try TestSupport.taxonomy(),
                                           vocabulary: try TestSupport.vocabulary(),
                                           styles: try TestSupport.styles(),
                                           textures: try TestSupport.textures(),
                                           shouldContinue: { ticks += 1; return ticks <= 1 })
        XCTAssertLessThan(result.scanned, 600)
    }
    func testManualEditsAfterTheInitialReadAreProtected() throws {
        let id = try insert("Lo-Fi Pack/Drums/metal_kick_75bpm.wav")
        var changed = false
        _ = PathRereadService.run(database: database,
            taxonomy: try TestSupport.taxonomy(), vocabulary: try TestSupport.vocabulary(),
            styles: try TestSupport.styles(), textures: try TestSupport.textures(),
            shouldContinue: {
                if !changed {
                    changed = true
                    do {
                        try self.database.writer.write { db in
                            try db.execute(sql: "UPDATE sounds SET style='Chiptune', style_source='manual', texture=NULL, texture_source='manual' WHERE id=?", arguments: [id])
                        }
                    } catch { XCTFail("manual edit failed: \(error)") }
                }
                return true
            })
        XCTAssertEqual(try value("style", of: id), "Chiptune")
        XCTAssertNil(try value("texture", of: id))
        XCTAssertEqual(try value("texture_source", of: id), "manual")
    }

    func testExplicitManualClearSurvivesReread() throws {
        let id = try insert("Lo-Fi Pack/Drums/metal_kick.wav")
        let metadata = ManualMetadataService(database: database)
        try metadata.setStyle(nil, soundId: id)
        try metadata.setTexture(nil, soundId: id)
        try reread()
        XCTAssertNil(try value("style", of: id))
        XCTAssertNil(try value("texture", of: id))
        XCTAssertEqual(try value("style_source", of: id), "manual")
        XCTAssertEqual(try value("texture_source", of: id), "manual")
    }

    func testWriteFailureIsReportedWithoutCountingRolledBackChanges() throws {
        _ = try insert("Lo-Fi Pack/metal_kick.wav")
        try database.writer.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_write BEFORE UPDATE OF style ON sounds BEGIN SELECT RAISE(ABORT, 'test write failure'); END")
        }
        let result = try reread()
        XCTAssertNotNil(result.errorMessage)
        XCTAssertEqual(result.styleFilled, 0)
    }

}
