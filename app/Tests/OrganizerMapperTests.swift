import XCTest
import GRDB
@testable import FoleyLibrary

/// 本輪最重要的測試：人工 metadata 在 AI 分析之後必須原封不動。
final class OrganizerMapperTests: XCTestCase {

    private func makeMapper() throws -> OrganizerResultMapper {
        OrganizerResultMapper(validator: try TestSupport.validator(), policy: .default)
    }

    func testPersistWritesAnalysisAndSuggestions() throws {
        let database = try TestSupport.database()
        let sound = try TestSupport.insertSound(into: database)
        let mapper = try makeMapper()

        try database.writer.write { db in
            try mapper.persist(result: MockOrganizerEngine.doorSlam,
                               soundId: sound.id ?? 0,
                               engine: "mock",
                               in: db)
        }

        let repository = SoundRepository(database: database)
        let analysis = try XCTUnwrap(repository.latestAnalysis(soundId: sound.id ?? 0))
        XCTAssertEqual(analysis.status, .recognized)
        XCTAssertEqual(analysis.engine, "mock")

        let suggestions = try repository.suggestions(analysisId: analysis.id ?? 0)
        let fields = Set(suggestions.map { $0.field })
        XCTAssertTrue(fields.contains(.displayName))
        XCTAssertTrue(fields.contains(.category))
        XCTAssertEqual(suggestions.filter { $0.field == .tag }.count, 5)
    }

    /// AI 的輸出絕不直接寫進 sounds 的 metadata 欄位（DECISIONS D-007）。
    func testPersistNeverWritesMetadataFieldsDirectly() throws {
        let database = try TestSupport.database()
        let sound = try TestSupport.insertSound(into: database)
        let mapper = try makeMapper()

        try database.writer.write { db in
            try mapper.persist(result: MockOrganizerEngine.doorSlam,
                               soundId: sound.id ?? 0,
                               engine: "mock",
                               in: db)
        }

        let updated = try XCTUnwrap(SoundRepository(database: database).sound(id: sound.id ?? 0))
        XCTAssertNil(updated.displayName, "分析不得直接設定 display name")
        XCTAssertNil(updated.categoryId, "分析不得直接設定分類")
        XCTAssertEqual(updated.analysisStatus, .done, "但分析狀態應該更新")
    }

    /// ROADMAP §30 第 12 條：重新分析不得靜默覆寫人工修正。
    func testManualCategorySurvivesReanalysis() throws {
        let database = try TestSupport.database()
        let sound = try TestSupport.insertSound(into: database)
        let soundId = sound.id ?? 0
        let metadata = ManualMetadataService(database: database)
        let mapper = try makeMapper()

        // 使用者手動分類為 Foley/Props
        try metadata.setCategory(path: "Foley/Props", soundId: soundId, source: .manual)

        // AI 說是 Foley/Doors，信心 0.94
        try database.writer.write { db in
            try mapper.persist(result: MockOrganizerEngine.doorSlam,
                               soundId: soundId,
                               engine: "mock",
                               in: db)
        }

        let repository = SoundRepository(database: database)
        let updated = try XCTUnwrap(repository.sound(id: soundId))
        let category = try XCTUnwrap(repository.category(id: updated.categoryId ?? 0))
        XCTAssertEqual(category.path, "Foley/Props", "人工分類必須保持不變")
        XCTAssertEqual(updated.categorySource, .manual)
    }

    func testAcceptingSuggestionIsRefusedWhenValueIsManual() throws {
        let database = try TestSupport.database()
        let sound = try TestSupport.insertSound(into: database)
        let soundId = sound.id ?? 0
        let metadata = ManualMetadataService(database: database)
        let mapper = try makeMapper()

        try metadata.setCategory(path: "Foley/Props", soundId: soundId, source: .manual)
        try database.writer.write { db in
            try mapper.persist(result: MockOrganizerEngine.doorSlam, soundId: soundId, engine: "mock", in: db)
        }

        let repository = SoundRepository(database: database)
        let analysis = try XCTUnwrap(repository.latestAnalysis(soundId: soundId))
        let suggestions = try repository.suggestions(analysisId: analysis.id ?? 0)
        let categorySuggestion = try XCTUnwrap(suggestions.first { $0.field == .category })

        XCTAssertThrowsError(try metadata.accept(suggestionId: categorySuggestion.id ?? 0)) { error in
            XCTAssertEqual(error as? MetadataWriteError, .manualValueProtected(field: "category"))
        }

        // 使用者明確選擇覆寫自己的舊值時才放行
        try metadata.accept(suggestionId: categorySuggestion.id ?? 0, force: true)
        let updated = try XCTUnwrap(repository.sound(id: soundId))
        let category = try XCTUnwrap(repository.category(id: updated.categoryId ?? 0))
        XCTAssertEqual(category.path, "Foley/Doors")
        XCTAssertEqual(updated.categorySource, .acceptedAI, "接受 AI 建議不等於人工設定")
    }

    func testAcceptingDisplayNameDoesNotTouchFilename() throws {
        let database = try TestSupport.database()
        let sound = try TestSupport.insertSound(into: database, filename: "BBC_SFX_03942.wav")
        let soundId = sound.id ?? 0
        let metadata = ManualMetadataService(database: database)
        let mapper = try makeMapper()

        try database.writer.write { db in
            try mapper.persist(result: MockOrganizerEngine.doorSlam, soundId: soundId, engine: "mock", in: db)
        }
        let repository = SoundRepository(database: database)
        let analysis = try XCTUnwrap(repository.latestAnalysis(soundId: soundId))
        let suggestions = try repository.suggestions(analysisId: analysis.id ?? 0)
        let nameSuggestion = try XCTUnwrap(suggestions.first { $0.field == .displayName })

        try metadata.accept(suggestionId: nameSuggestion.id ?? 0)

        let updated = try XCTUnwrap(repository.sound(id: soundId))
        XCTAssertEqual(updated.displayName, "Heavy Metal Door Slam")
        XCTAssertEqual(updated.filename, "BBC_SFX_03942.wav", "檔名是實體屬性，不得被改動")
        XCTAssertEqual(updated.filePath, "/tmp/test/BBC_SFX_03942.wav")
    }

    func testReanalysisSupersedesOldSuggestions() throws {
        let database = try TestSupport.database()
        let sound = try TestSupport.insertSound(into: database)
        let soundId = sound.id ?? 0
        let mapper = try makeMapper()

        try database.writer.write { db in
            try mapper.persist(result: MockOrganizerEngine.doorSlam, soundId: soundId, engine: "mock", in: db)
            try mapper.persist(result: MockOrganizerEngine.ambiguousImpact, soundId: soundId, engine: "mock", in: db)
        }

        try database.writer.read { db in
            let superseded = try OrganizerSuggestion
                .filter(OrganizerSuggestion.Columns.status == OrganizerSuggestion.Status.superseded.rawValue)
                .fetchCount(db)
            XCTAssertGreaterThan(superseded, 0, "舊建議應該被標記為 superseded 而不是刪除")
        }
    }

    func testFailedAnalysisKeepsSoundUsable() throws {
        let database = try TestSupport.database()
        let sound = try TestSupport.insertSound(into: database)
        let soundId = sound.id ?? 0
        let mapper = try makeMapper()

        try database.writer.write { db in
            try mapper.persist(result: OrganizerResult.failure(reason: "timeout"),
                               soundId: soundId,
                               engine: "mock",
                               in: db)
        }

        let updated = try XCTUnwrap(SoundRepository(database: database).sound(id: soundId))
        XCTAssertEqual(updated.analysisStatus, .failed)
        XCTAssertTrue(updated.needsReview)
        XCTAssertEqual(updated.status, .ok, "分析失敗不影響檔案本身的可用性")
    }

    func testUnknownResultGoesToNeedsReview() throws {
        let database = try TestSupport.database()
        let sound = try TestSupport.insertSound(into: database)
        let soundId = sound.id ?? 0
        let mapper = try makeMapper()

        try database.writer.write { db in
            try mapper.persist(result: MockOrganizerEngine.unknownSound, soundId: soundId, engine: "mock", in: db)
        }

        let repository = SoundRepository(database: database)
        let updated = try XCTUnwrap(repository.sound(id: soundId))
        XCTAssertTrue(updated.needsReview)
        XCTAssertNil(updated.categoryId, "unknown 不應該被硬塞進任何分類")
        let needsReview = try repository.fetch(filter: .needsReview)
        XCTAssertEqual(needsReview.count, 1)
    }
    func testReanalysisProtectsManualKeyIndependentlyOfBpm() throws {
        let database = try TestSupport.database()
        let soundId = try XCTUnwrap(TestSupport.insertSound(into: database).id)
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sounds SET musical_key='Cm', key_source='manual', bpm=90, bpm_source='imported' WHERE id=?", arguments: [soundId])
            var result = MockOrganizerEngine.doorSlam
            result.bpm = 120
            result.musicalKey = "Gm"
            let mapper = OrganizerResultMapper(validator: try TestSupport.validator())
            try mapper.persist(result: result, soundId: soundId, engine: "test", in: db)
        }
        try database.writer.read { db in
            let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT bpm,musical_key,key_source FROM sounds WHERE id=?", arguments: [soundId]))
            XCTAssertEqual(row["bpm"] as Double, 120)
            XCTAssertEqual(row["musical_key"] as String, "Cm")
            XCTAssertEqual(row["key_source"] as String, "manual")
        }
    }

}
