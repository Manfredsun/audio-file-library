import XCTest
@testable import FoleyLibrary

/// 批次分析的取件條件與進度模型。
///
/// 整條 UI 流程沒辦法在單元測試裡跑，但「該分析哪些檔案」與
/// 「進度怎麼呈現」都是純資料邏輯，這兩件事出錯的代價最高。
final class BatchAnalysisTests: XCTestCase {

    private func database() throws -> AppDatabase {
        try TestSupport.database()
    }

    @discardableResult
    private func insert(into database: AppDatabase,
                        filename: String,
                        status: FileStatus = .ok,
                        analysis: AnalysisStatus = .none,
                        libraryId: Int64? = nil) throws -> Sound {
        try database.writer.write { db in
            let libId: Int64
            if let libraryId {
                libId = libraryId
            } else {
                var library = Library(name: "Test", rootPath: "/tmp/test-\(UUID().uuidString)")
                try library.insert(db)
                libId = library.id ?? 0
            }
            var sound = Sound(libraryId: libId,
                              filePath: "/tmp/test/\(filename)",
                              relativePath: filename,
                              filename: filename,
                              fileExtension: "wav",
                              duration: 1)
            sound.status = status
            sound.analysisStatus = analysis
            try sound.insert(db)
            return sound
        }
    }

    func testPendingIncludesUnanalysedAndQueued() throws {
        let db = try database()
        let repository = SoundRepository(database: db)
        try insert(into: db, filename: "a.wav", analysis: .none)
        try insert(into: db, filename: "b.wav", analysis: .queued)

        let pending = try repository.soundsPendingAnalysis()
        XCTAssertEqual(Set(pending.map(\.filename)), ["a.wav", "b.wav"])
    }

    func testPendingExcludesAlreadyAnalysed() throws {
        let db = try database()
        let repository = SoundRepository(database: db)
        try insert(into: db, filename: "done.wav", analysis: .done)
        try insert(into: db, filename: "failed.wav", analysis: .failed)
        try insert(into: db, filename: "todo.wav", analysis: .none)

        let pending = try repository.soundsPendingAnalysis()
        XCTAssertEqual(pending.map(\.filename), ["todo.wav"],
                       "已經分析過的不該被重跑——重跑會覆蓋掉使用者已經審核過的結果")
    }

    func testPendingExcludesUnavailableFiles() throws {
        let db = try database()
        let repository = SoundRepository(database: db)
        try insert(into: db, filename: "offline.wav", status: .missing)
        try insert(into: db, filename: "broken.wav", status: .unreadable)
        try insert(into: db, filename: "ok.wav", status: .ok)

        let pending = try repository.soundsPendingAnalysis()
        XCTAssertEqual(pending.map(\.filename), ["ok.wav"],
                       "讀不到的檔案送進引擎只會一路寫 failed，把真正的失敗淹沒掉")
    }

    func testPendingCanBeScopedToOneLibrary() throws {
        let db = try database()
        let repository = SoundRepository(database: db)
        let first = try insert(into: db, filename: "one.wav")
        try insert(into: db, filename: "two.wav")

        let pending = try repository.soundsPendingAnalysis(libraryId: first.libraryId)
        XCTAssertEqual(pending.map(\.filename), ["one.wav"])
    }

    func testPendingRespectsLimit() throws {
        let db = try database()
        let repository = SoundRepository(database: db)
        for index in 0..<5 {
            try insert(into: db, filename: "f\(index).wav")
        }
        XCTAssertEqual(try repository.soundsPendingAnalysis(limit: 2).count, 2)
    }

    // MARK: - 進度模型

    func testFractionIsZeroBeforeAnythingIsKnown() {
        XCTAssertEqual(BatchAnalysisProgress().fraction, 0)
    }

    func testFractionNeverExceedsOne() {
        var progress = BatchAnalysisProgress(phase: .running, total: 3, completed: 5)
        XCTAssertEqual(progress.fraction, 1)
        progress.completed = 3
        XCTAssertEqual(progress.fraction, 1)
    }

    func testSummarySeparatesReviewFromFailure() {
        let progress = BatchAnalysisProgress(phase: .finished,
                                             total: 10,
                                             completed: 10,
                                             failed: 2,
                                             needsReview: 6)
        XCTAssertTrue(progress.summary.contains("6"))
        XCTAssertTrue(progress.summary(locale: "zh-Hant").contains("待複查"))
        XCTAssertTrue(progress.summary.contains("2"))
        XCTAssertTrue(progress.summary(locale: "zh-Hant").contains("失敗"))
    }

    func testSummaryIsEmptyWhileIdle() {
        XCTAssertTrue(BatchAnalysisProgress().summary.isEmpty)
    }

    func testCancelledSummaryReportsPartialProgress() {
        let progress = BatchAnalysisProgress(phase: .cancelled, total: 100, completed: 37)
        XCTAssertTrue(progress.summary.contains("37"))
        XCTAssertTrue(progress.summary.contains("100"))
    }
}
