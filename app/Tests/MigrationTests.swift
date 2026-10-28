import XCTest
import GRDB
@testable import FoleyLibrary

final class MigrationTests: XCTestCase {

    func testMigrationCreatesAllTables() throws {
        let database = try TestSupport.database(seeded: false)
        let expected = ["libraries", "categories", "tags", "sounds", "sound_tags",
                        "organizer_analysis", "organizer_suggestions",
                        "waveform_cache", "collections", "collection_sounds"]
        try database.writer.read { db in
            for table in expected {
                XCTAssertTrue(try db.tableExists(table), "缺少資料表：\(table)")
            }
        }
    }

    func testMigrationIsIdempotent() throws {
        let database = try TestSupport.database(seeded: false)
        // 第二次 migrate 不應該失敗，也不應該重建任何東西。
        XCTAssertNoThrow(try AppMigrations.migrator.migrate(database.writer))
    }

    func testSeedingInsertsControlledTaxonomy() throws {
        let database = try TestSupport.database(seeded: true)
        let taxonomy = try TestSupport.taxonomy()
        try database.writer.read { db in
            let count = try Category.fetchCount(db)
            XCTAssertEqual(count, taxonomy.allPaths.count)
            let doors = try Category.filter(Category.Columns.path == "Foley/Doors").fetchOne(db)
            XCTAssertNotNil(doors, "Foley/Doors 應該存在")
            XCTAssertNotNil(doors?.parentId, "子分類應該有 parent")
        }
    }

    func testSeedingIsIdempotent() throws {
        let database = try TestSupport.database(seeded: true)
        let taxonomy = try TestSupport.taxonomy()
        let insertedAgain = try database.writer.write { db in
            try CategorySeeder.seedIfNeeded(taxonomy: taxonomy, in: db)
        }
        XCTAssertEqual(insertedAgain, 0, "重複 seed 不應新增任何分類")
    }

    func testSoundDefaultsAreSafe() throws {
        let database = try TestSupport.database()
        let sound = try TestSupport.insertSound(into: database)
        XCTAssertEqual(sound.status, .ok)
        XCTAssertEqual(sound.analysisStatus, .none)
        XCTAssertFalse(sound.needsReview)
        XCTAssertNil(sound.displayNameSource, "新音效不應該有任何 provenance")
    }

    /// 回歸測試：migration 期間外鍵約束是關閉的，`ON DELETE CASCADE` 不會觸發。
    /// v3 若只刪父表就會留下孤兒列，導致 App 啟動時 migration 失敗。
    func testV3RemovesMockSeedWithoutLeavingOrphans() throws {
        let migrator = AppMigrations.migrator
        let queue = try DatabaseQueue()
        try migrator.migrate(queue, upTo: "v2_last_seen_at")

        // 造出 M0 時期那批假資料，連同它的分析與建議
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO libraries (id, name, root_path, created_at, availability_status)
                VALUES (1, 'Mock Library', '/Volumes/Mock/Foley', '2026-09-17 00:00:00', 'offline')
                """)
            try db.execute(sql: """
                INSERT INTO sounds (id, library_id, file_path, relative_path, filename,
                                    file_extension, file_size, favorite, rating,
                                    status, analysis_status, needs_review, date_indexed, play_count)
                VALUES (1, 1, '/Volumes/Mock/Foley/Doors/metal_door_04.wav',
                        'Doors/metal_door_04.wav', 'metal_door_04.wav', 'wav', 1,
                        0, 0, 'offline', 'none', 0, '2026-09-17 00:00:00', 0)
                """)
            try db.execute(sql: """
                INSERT INTO organizer_analysis (id, sound_id, engine, status, confidence,
                                                needs_review, started_at)
                VALUES (1, 1, 'mock', 'recognized', 0.9, 0, '2026-09-17 00:00:00')
                """)
            try db.execute(sql: """
                INSERT INTO organizer_suggestions (id, analysis_id, field, value, status)
                VALUES (1, 1, 'display_name', 'Heavy Metal Door Slam', 'suggested')
                """)
        }

        try migrator.migrate(queue)

        try queue.read { db in
            XCTAssertEqual(try Library.fetchCount(db), 0, "示範音色庫應該被移除")
            XCTAssertEqual(try Sound.fetchCount(db), 0, "它底下的音效不能變成孤兒")
            XCTAssertEqual(try OrganizerAnalysis.fetchCount(db), 0)
            XCTAssertEqual(try OrganizerSuggestion.fetchCount(db), 0)

            let violations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            XCTAssertTrue(violations.isEmpty, "migration 之後不得留下任何外鍵違規")
        }
    }

    func testMigrationLeavesRealLibrariesAlone() throws {
        let migrator = AppMigrations.migrator
        let queue = try DatabaseQueue()
        try migrator.migrate(queue, upTo: "v2_last_seen_at")

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO libraries (id, name, root_path, created_at, availability_status)
                VALUES (1, 'FX', '/Users/someone/Sound/FX', '2026-09-17 00:00:00', 'available')
                """)
        }

        try migrator.migrate(queue)

        try queue.read { db in
            XCTAssertEqual(try Library.fetchCount(db), 1, "真實的音色庫不可以被清理掉")
        }
    }
    func testV13PreservesLegacyJournalAndDefaultsToPending() throws {
        let queue = try DatabaseQueue()
        try AppMigrations.migrator.migrate(queue, upTo: "v12_clear_review_for_confirmed")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO libraries (id,name,root_path,created_at) VALUES (1,'Test','/tmp/test',?)", arguments: [Date()])
            try db.execute(sql: "INSERT INTO sounds (id,library_id,file_path,relative_path,filename,file_extension,date_indexed) VALUES (1,1,'/tmp/test/a.wav','a.wav','a.wav','wav',?)", arguments: [Date()])
            try db.execute(sql: "INSERT INTO organize_batches (id,created_at,scope,root_path) VALUES (1,?,'legacy','/tmp/test/_Organized')", arguments: [Date()])
            try db.execute(sql: "INSERT INTO organize_journal (batch_id,sound_id,link_path,created_at) VALUES (1,1,'/tmp/test/_Organized/a.wav',?)", arguments: [Date()])
        }
        try AppMigrations.migrator.migrate(queue)
        try queue.read { db in
            let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM organize_journal"))
            XCTAssertEqual(row["undo_state"] as String, "pending")
            XCTAssertNil(row["file_identifier"] as String?)
            XCTAssertEqual(row["link_path"] as String, "/tmp/test/_Organized/a.wav")
            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
        }
    }

    func testV15AddsScanOwnershipWithoutChangingMetadata() throws {
        let queue = try DatabaseQueue()
        try AppMigrations.migrator.migrate(queue, upTo: "v14_scan_identity")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO libraries(id,name,root_path,created_at) VALUES(1,'Keep','/tmp/fixture',?)", arguments: [Date()])
            try db.execute(sql: "INSERT INTO sounds(library_id,file_path,relative_path,filename,file_extension,date_indexed,display_name,display_name_source,last_scan_token) VALUES(1,'/tmp/fixture/a.wav','a.wav','a.wav','wav',?,'Human name','manual','previous-scan')", arguments: [Date()])
        }
        try AppMigrations.migrator.migrate(queue)
        try queue.read { db in
            let library = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM libraries WHERE id=1"))
            XCTAssertNil(library["active_scan_token"] as String?)
            let sound = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM sounds"))
            XCTAssertEqual(sound["display_name"] as String, "Human name")
            XCTAssertEqual(sound["display_name_source"] as String, "manual")
            XCTAssertEqual(sound["last_scan_token"] as String, "previous-scan")
            XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
        }
    }

}
