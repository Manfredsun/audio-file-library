import XCTest
@testable import FoleyLibrary

/// 硬連結執行與撤銷。
///
/// **這一組跑真的 `link()`**，在臨時資料夾裡。假的檔案系統測不出硬連結
/// 真正會踩到的東西：同碟限制、大小寫、目標已存在。D-032 的教訓是
/// 測在錯的層級等於沒測，這一層不能重蹈。
final class OrganizeExecutorTests: XCTestCase {

    private var work: URL!
    private var sources: URL!
    private var root: URL!
    private var journal: FakeJournal!

    /// 只記帳，不碰資料庫——執行層的邏輯跟 SQL 無關。
    /// 資料庫那一半由 `OrganizeJournalTests` 顧。
    final class FakeJournal: OrganizeJournalWriting {
        var batches: [Int64: [String]] = [:]
        var counts: [Int64: Int] = [:]
        var undone: Set<Int64> = []
        var next: Int64 = 0
        var failToBegin = false
        var entriesById: [Int64: OrganizeJournalEntry] = [:]
        var roots: [Int64: String] = [:]

        func beginBatch(scope: String, root: String) throws -> Int64 {
            if failToBegin { throw AppError.databaseError("測試：開批次失敗") }
            next += 1
            batches[next] = []
            roots[next] = root
            return next
        }
        func record(batchId: Int64, soundId: Int64, linkPath: String, fileIdentifier: String) throws {
            batches[batchId, default: []].append(linkPath)
            let id = Int64(entriesById.count + 1)
            entriesById[id] = OrganizeJournalEntry(id: id, batchId: batchId, path: linkPath,
                root: roots[batchId] ?? "", fileIdentifier: fileIdentifier, undoState: "pending")
        }
        func entries(batchId: Int64) throws -> [OrganizeJournalEntry] {
            if undone.contains(batchId) { return [] }
            return entriesById.values.filter { $0.batchId == batchId }.sorted { $0.id < $1.id }
        }
        func claimUndo(entryId: Int64) throws -> Bool {
            guard let entry = entriesById[entryId], ["pending", "failed"].contains(entry.undoState) else { return false }
            entriesById[entryId]?.undoState = "removing"
            return true
        }
        func recordUndo(entryId: Int64, state: String, recoveryPath: String? = nil) throws {
            entriesById[entryId]?.undoState = state
            entriesById[entryId]?.recoveryPath = recoveryPath
        }
        func finishBatch(_ batchId: Int64, linkCount: Int) throws { counts[batchId] = linkCount }
        func linkPaths(batchId: Int64) throws -> [String] { batches[batchId] ?? [] }
        func markUndone(_ batchId: Int64) throws {
            if !entriesById.values.contains(where: { $0.batchId == batchId && ["pending", "failed", "removing"].contains($0.undoState) }) {
                undone.insert(batchId)
            }
        }
    }

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory
            .appendingPathComponent("organize-\(UUID().uuidString)")
        sources = work.appendingPathComponent("sources")
        root = work.appendingPathComponent("_Organized")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        journal = FakeJournal()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    @discardableResult
    private func makeSource(_ name: String, contents: String = "audio") throws -> String {
        let url = sources.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func job(_ id: Int64, _ source: String, to destination: String) -> OrganizeExecutor.Job {
        OrganizeExecutor.Job(soundId: id, sourcePath: source, destination: destination)
    }

    private func run(_ jobs: [OrganizeExecutor.Job],
                     shouldContinue: @escaping () -> Bool = { true }) -> OrganizeOutcome {
        OrganizeExecutor.run(jobs,
                             root: root.path,
                             scope: "測試",
                             journal: journal,
                             shouldContinue: shouldContinue)
    }

    // MARK: - 建立連結

    func testLinkAndUndoNeedSearchPermissionWithoutReadingAncestor() throws {
        let source = try makeSource("tone.wav", contents: "original audio")
        // A folder picker authorizes the library, not reading its parent directory.
        // Execute/search permission is sufficient to reach a known child path.
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: work.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: work.path) }
        XCTAssertFalse(FileManager.default.isReadableFile(atPath: work.path))

        let outcome = run([job(1, source, to: "Musical/Tone/Tone 01.wav")])
        XCTAssertEqual(outcome.linked, 1)
        XCTAssertEqual(outcome.failed, 0)
        let batchId = try XCTUnwrap(outcome.batchId)
        let undo = OrganizeExecutor.undo(batchId: batchId, journal: journal)
        XCTAssertEqual(undo.removed, 1)
        XCTAssertEqual(undo.failed, 0)
        XCTAssertEqual(try String(contentsOfFile: source, encoding: .utf8), "original audio")
        XCTAssertTrue(journal.undone.contains(batchId))
    }

    func testLinkPointsAtTheSameDataAsTheOriginal() throws {
        let source = try makeSource("kick.wav", contents: "一樣的資料")
        let outcome = run([job(1, source, to: "Drums/Kick/Kick 01.wav")])

        XCTAssertEqual(outcome.linked, 1)
        let linked = root.appendingPathComponent("Drums/Kick/Kick 01.wav")
        XCTAssertEqual(try String(contentsOf: linked, encoding: .utf8), "一樣的資料")

        // 硬連結的重點：同一個 inode，不是複製。
        let a = try FileManager.default.attributesOfItem(atPath: source)[.systemFileNumber] as? Int
        let b = try FileManager.default.attributesOfItem(atPath: linked.path)[.systemFileNumber] as? Int
        XCTAssertEqual(a, b, "複製一份就失去整個方案的意義了")
    }

    func testTheOriginalIsNeverTouched() throws {
        // 安全模型第一條：永不刪除原始檔案。
        let source = try makeSource("kick.wav")
        run([job(1, source, to: "Drums/Kick/Kick 01.wav")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source))
    }

    func testMissingFoldersAreCreated() throws {
        let source = try makeSource("kick.wav")
        run([job(1, source, to: "a/b/c/Kick 01.wav")])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("a/b/c/Kick 01.wav").path))
    }

    // MARK: - 永不覆蓋

    func testAnExistingDestinationIsSkippedNotOverwritten() throws {
        // 安全模型第二條。目標已存在是**跳過**，不是錯誤，也絕不覆蓋。
        let source = try makeSource("kick.wav", contents: "新的")
        let destination = root.appendingPathComponent("Drums/Kick/Kick 01.wav")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "本來就在這裡的".write(to: destination, atomically: true, encoding: .utf8)

        let outcome = run([job(1, source, to: "Drums/Kick/Kick 01.wav")])

        XCTAssertEqual(outcome.skipped, 1)
        XCTAssertEqual(outcome.linked, 0)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "本來就在這裡的")
    }

    func testOneBadJobDoesNotStopTheRest() throws {
        let good = try makeSource("kick.wav")
        let outcome = run([
            job(1, "/tmp/這個檔案不存在-\(UUID().uuidString).wav", to: "Drums/Kick/Kick 01.wav"),
            job(2, good, to: "Drums/Kick/Kick 02.wav"),
        ])
        XCTAssertEqual(outcome.failed, 1)
        XCTAssertEqual(outcome.linked, 1)
    }

    // MARK: - 碰撞檢查

    func testCaseInsensitiveCollisionsAreCaught() {
        // HFS+ 不分大小寫：Kick 01.wav 與 kick 01.wav 是同一個檔案。
        // 用區分大小寫的比對，第二個會靜默覆蓋第一個。
        let problems = OrganizeExecutor.problems(in: [
            job(1, "/a.wav", to: "Drums/Kick 01.wav"),
            job(2, "/b.wav", to: "Drums/kick 01.WAV"),
        ])
        XCTAssertEqual(problems.count, 2, "兩邊都要標——要決定的是這兩筆哪一個該改")
    }

    func testCollidingJobsAreSkippedButTheRestStillRuns() throws {
        let a = try makeSource("a.wav")
        let b = try makeSource("b.wav")
        let c = try makeSource("c.wav")
        let outcome = run([
            job(1, a, to: "Drums/Kick 01.wav"),
            job(2, b, to: "Drums/KICK 01.wav"),
            job(3, c, to: "Drums/Snare 01.wav"),
        ])
        XCTAssertEqual(outcome.linked, 1, "碰撞的兩筆不跑，沒碰撞的照跑")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Drums/Snare 01.wav").path))
    }

    func testIllegalCharactersAreCaught() {
        let problems = OrganizeExecutor.problems(in: [
            job(1, "/a.wav", to: "Drums/Kick: 01.wav"),
        ])
        XCTAssertEqual(problems.count, 1, "冒號在 Finder 裡會顯示成斜線，檔案會跑到意外的地方")
    }

    // MARK: - 中斷

    func testCancellingLeavesWhatWasAlreadyDoneAndMarksTheOutcome() throws {
        let sources = try (1...5).map { try makeSource("s\($0).wav") }
        var done = 0
        let outcome = run(sources.enumerated().map { index, path in
            job(Int64(index + 1), path, to: "Drums/Kick \(index).wav")
        }, shouldContinue: {
            done += 1
            return done <= 2
        })

        XCTAssertTrue(outcome.cancelled)
        XCTAssertEqual(outcome.linked, 2)
        // 中斷不是回復。已經建立的連結留著，要清掉是走撤銷。
        XCTAssertNotNil(outcome.batchId)
    }

    // MARK: - 撤銷

    func testUndoRemovesOnlyTheLinksThisBatchCreated() throws {
        let source = try makeSource("kick.wav")
        // 別人（或上一批）放在同一棵樹裡的東西，撤銷不准碰。
        let stranger = root.appendingPathComponent("Drums/Kick/別人的.wav")
        try FileManager.default.createDirectory(at: stranger.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "不要動我".write(to: stranger, atomically: true, encoding: .utf8)

        let outcome = run([job(1, source, to: "Drums/Kick/Kick 01.wav")])
        let removed = OrganizeExecutor.undo(batchId: outcome.batchId ?? 0, journal: journal)

        XCTAssertEqual(removed.removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Drums/Kick/Kick 01.wav").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stranger.path),
                      "沒有記錄的東西一個字都不能刪")
    }

    func testUndoDoesNotTouchTheOriginalFile() throws {
        // 刪掉一個硬連結不會刪到資料——只有最後一個連結被刪才會。
        // 原檔還在，所以撤銷是真的乾淨。
        let source = try makeSource("kick.wav", contents: "原始資料")
        let outcome = run([job(1, source, to: "Drums/Kick/Kick 01.wav")])
        OrganizeExecutor.undo(batchId: outcome.batchId ?? 0, journal: journal)

        XCTAssertTrue(FileManager.default.fileExists(atPath: source))
        XCTAssertEqual(try String(contentsOfFile: source, encoding: .utf8), "原始資料")
    }

    func testUndoingTwiceIsHarmless() throws {
        let source = try makeSource("kick.wav")
        let outcome = run([job(1, source, to: "Drums/Kick/Kick 01.wav")])
        OrganizeExecutor.undo(batchId: outcome.batchId ?? 0, journal: journal)
        let again = OrganizeExecutor.undo(batchId: outcome.batchId ?? 0, journal: journal)
        XCTAssertEqual(again.removed, 0)
    }

    func testUndoAfterACancelledRunCleansUpWhatWasCreated() throws {
        let sources = try (1...4).map { try makeSource("s\($0).wav") }
        var done = 0
        let outcome = run(sources.enumerated().map { index, path in
            job(Int64(index + 1), path, to: "Drums/Kick \(index).wav")
        }, shouldContinue: { done += 1; return done <= 2 })

        XCTAssertEqual(OrganizeExecutor.undo(batchId: outcome.batchId ?? 0, journal: journal).removed, 2)
    }

    func testUndoPreservesAReplacementAtTheRecordedPath() throws {
        let source = try makeSource("kick.wav")
        let outcome = run([job(1, source, to: "Kick.wav")])
        let link = root.appendingPathComponent("Kick.wav")
        try FileManager.default.removeItem(at: link)
        try "user replacement".write(to: link, atomically: true, encoding: .utf8)
        let result = OrganizeExecutor.undo(batchId: outcome.batchId ?? 0, journal: journal)
        XCTAssertEqual(result.skippedChanged, 1)
        XCTAssertEqual(try String(contentsOf: link, encoding: .utf8), "user replacement")
    }

    func testRepeatedUndoPreservesANewFileAtTheOldPath() throws {
        let source = try makeSource("kick.wav")
        let outcome = run([job(1, source, to: "Kick.wav")])
        OrganizeExecutor.undo(batchId: outcome.batchId ?? 0, journal: journal)
        let link = root.appendingPathComponent("Kick.wav")
        try "new file".write(to: link, atomically: true, encoding: .utf8)
        XCTAssertEqual(OrganizeExecutor.undo(batchId: outcome.batchId ?? 0, journal: journal).removed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
    }

    func testUndoPreservesTheLastSurvivingHardLink() throws {
        let source = try makeSource("kick.wav")
        let outcome = run([job(1, source, to: "Kick.wav")])
        try FileManager.default.removeItem(atPath: source)
        let result = OrganizeExecutor.undo(batchId: outcome.batchId ?? 0, journal: journal)
        XCTAssertEqual(result.skippedChanged, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Kick.wav").path))
    }

    func testPathTraversalCannotEscapeTheOrganizedRoot() throws {
        let source = try makeSource("kick.wav")
        let outcome = run([job(1, source, to: "../outside.wav")])
        XCTAssertEqual(outcome.linked, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent("outside.wav").path))
    }

    func testSymlinkedDestinationDirectoryIsNeverFollowed() throws {
        let source = try makeSource("kick.wav")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: sources)
        let outcome = run([job(1, source, to: "escape/other.wav")])
        XCTAssertEqual(outcome.linked, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sources.appendingPathComponent("other.wav").path))
    }

    func testUndoNeverRecursivelyDeletesAReplacementDirectory() throws {
        let source = try makeSource("kick.wav")
        let outcome = run([job(1, source, to: "Kick.wav")])
        let link = root.appendingPathComponent("Kick.wav")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createDirectory(at: link, withIntermediateDirectories: true)
        try "keep".write(to: link.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(OrganizeExecutor.undo(batchId: outcome.batchId ?? 0, journal: journal).skippedChanged, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.appendingPathComponent("keep.txt").path))
    }

    func testAnOfflineRootKeepsUndoRetryable() throws {
        let source = try makeSource("kick.wav")
        let outcome = run([job(1, source, to: "Kick.wav")])
        let moved = work.appendingPathComponent("offline")
        try FileManager.default.moveItem(at: root, to: moved)
        XCTAssertEqual(OrganizeExecutor.undo(batchId: outcome.batchId!, journal: journal).failed, 1)
        XCTAssertFalse(journal.undone.contains(outcome.batchId!))
        try FileManager.default.moveItem(at: moved, to: root)
        XCTAssertEqual(OrganizeExecutor.undo(batchId: outcome.batchId!, journal: journal).removed, 1)
    }

    func testPartialUndoRetriesOnlyFailedEntries() throws {
        final class FailOnce: OrganizeFileSystem {
            var failed = false
            let real = RealOrganizeFileSystem()
            func fileExists(at path: String) -> Bool { real.fileExists(at: path) }
            func link(from source: String, to destination: String, root: String) throws -> String {
                try real.link(from: source, to: destination, root: root)
            }
            func removeVerifiedLink(at path: String, root: String, identifier: String, recordRecovery: (String) throws -> Void) throws -> OrganizeFileSafety.Removal {
                if !failed { failed = true; throw AppError.permissionLost(path) }
                return try real.removeVerifiedLink(at: path, root: root, identifier: identifier, recordRecovery: recordRecovery)
            }
        }
        let source = try makeSource("kick.wav")
        let outcome = run([job(1, source, to: "one.wav"), job(2, source, to: "two.wav")])
        let fs = FailOnce()
        let first = OrganizeExecutor.undo(batchId: outcome.batchId!, fileSystem: fs, journal: journal)
        XCTAssertEqual(first.failed, 1)
        XCTAssertEqual(first.removed, 1)
        let replacement = root.appendingPathComponent("two.wav")
        try "keep".write(to: replacement, atomically: true, encoding: .utf8)
        XCTAssertEqual(OrganizeExecutor.undo(batchId: outcome.batchId!, fileSystem: fs, journal: journal).removed, 1)
        XCTAssertEqual(try String(contentsOf: replacement, encoding: .utf8), "keep")
    }


    func testReplacementBetweenPreflightAndClaimIsRestoredWithoutDeletion() throws {
        let source = try makeSource("kick.wav")
        let replacementSource = try makeSource("replacement.wav", contents: "keep me")
        let outcome = run([job(1, source, to: "Kick.wav")])
        let entry = try XCTUnwrap(journal.entriesById.values.first)
        let swap = root.appendingPathComponent("swap.wav")
        try FileManager.default.linkItem(atPath: replacementSource, toPath: swap.path)
        let holding = root.appendingPathComponent("holding.wav")
        let result = try OrganizeFileSafety.remove(path: entry.path, root: entry.root, expected: entry.fileIdentifier!, recordRecovery: { _ in
            try FileManager.default.moveItem(atPath: entry.path, toPath: holding.path)
            try FileManager.default.moveItem(at: swap, to: URL(fileURLWithPath: entry.path))
            try FileManager.default.moveItem(at: holding, to: swap)
        })
        if case .changed = result {} else { XCTFail("replacement must be preserved") }
        XCTAssertEqual(try String(contentsOfFile: entry.path, encoding: .utf8), "keep me")
        XCTAssertEqual(OrganizeExecutor.undo(batchId: outcome.batchId!, journal: journal).removed, 0)
    }

    // MARK: - 記帳失敗

    func testNothingIsLinkedWhenTheBatchCannotBeOpened() throws {
        // 沒有 journal 就沒有撤銷。寧可一個都不建，也不要建了卻記不下來。
        journal.failToBegin = true
        let source = try makeSource("kick.wav")
        let outcome = run([job(1, source, to: "Drums/Kick/Kick 01.wav")])

        XCTAssertEqual(outcome.linked, 0)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Drums/Kick/Kick 01.wav").path))
    }
}
