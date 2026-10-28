import XCTest
import GRDB
@testable import FoleyLibrary

/// M2：檔案索引。
///
/// 最重要的性質是「重新掃描不是重設」——使用者整理過的 metadata 必須活過每一次掃描。
final class LibraryScannerTests: XCTestCase {

    private var scratch: URL!
    private var database: AppDatabase!
    private var manager: LibraryManager!
    private var scanner: LibraryScanner!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("foley-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        database = try TestSupport.database()
        manager = LibraryManager(database: database)
        scanner = LibraryScanner(database: database, batchSize: 2)
    }

    override func tearDownWithError() throws {
        if let scratch, FileManager.default.fileExists(atPath: scratch.path) {
            try? FileManager.default.removeItem(at: scratch)
        }
    }

    // MARK: - 工具

    /// 產生一個真正能被 AVAudioFile 打開的 WAV：16-bit PCM 靜音。
    @discardableResult
    private func writeWAV(_ relativePath: String,
                          seconds: Double = 0.25,
                          sampleRate: Int = 44_100,
                          channels: Int = 1,
                          bitsPerSample: Int = 16) throws -> URL {
        let url = scratch.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        let bytesPerFrame = channels * bitsPerSample / 8
        let frameCount = Int(Double(sampleRate) * seconds)
        let dataSize = frameCount * bytesPerFrame

        var data = Data()
        func put(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        put("RIFF");  put32(UInt32(36 + dataSize)); put("WAVE")
        put("fmt ");  put32(16)
        put16(1)                              // PCM
        put16(UInt16(channels))
        put32(UInt32(sampleRate))
        put32(UInt32(sampleRate * bytesPerFrame))
        put16(UInt16(bytesPerFrame))
        put16(UInt16(bitsPerSample))
        put("data");  put32(UInt32(dataSize))
        data.append(Data(count: dataSize))    // 靜音

        try data.write(to: url)
        return url
    }

    private func addLibrary() throws -> Library {
        try manager.add(url: scratch)
    }

    private func sounds() throws -> [Sound] {
        try database.writer.read { db in
            try Sound.order(Sound.Columns.filename.asc).fetchAll(db)
        }
    }

    // MARK: - 測試

    func testScanIndexesSupportedFilesOnly() throws {
        try writeWAV("door.wav")
        try writeWAV("Footsteps/concrete.wav")
        try Data("not audio".utf8).write(to: scratch.appendingPathComponent("notes.txt"))

        let library = try addLibrary()
        let result = scanner.scan(libraryId: try XCTUnwrap(library.id), root: scratch)

        XCTAssertEqual(result.discovered, 2, "只有支援的音訊副檔名該被索引")
        let all = try sounds()
        XCTAssertEqual(all.map(\.filename).sorted(), ["concrete.wav", "door.wav"])
    }

    func testRelativePathIncludesSubfolder() throws {
        try writeWAV("Doors/Metal/slam.wav")
        let library = try addLibrary()
        _ = scanner.scan(libraryId: try XCTUnwrap(library.id), root: scratch)

        let sound = try XCTUnwrap(try sounds().first)
        XCTAssertEqual(sound.relativePath, "Doors/Metal/slam.wav")
        XCTAssertEqual(sound.filename, "slam.wav")
        XCTAssertEqual(sound.fileExtension, "wav")
    }

    func testExtractsAudioMetadata() throws {
        try writeWAV("tone.wav", seconds: 0.5, sampleRate: 48_000, channels: 2, bitsPerSample: 16)
        let library = try addLibrary()
        let result = scanner.scan(libraryId: try XCTUnwrap(library.id), root: scratch)

        XCTAssertEqual(result.extracted, 1)
        XCTAssertEqual(result.unreadable, 0)

        let sound = try XCTUnwrap(try sounds().first)
        XCTAssertEqual(sound.sampleRate, 48_000)
        XCTAssertEqual(sound.channelCount, 2)
        XCTAssertEqual(sound.bitDepth, 16)
        XCTAssertEqual(try XCTUnwrap(sound.duration), 0.5, accuracy: 0.01)
        XCTAssertNotNil(sound.fileIdentifier, "應該記下穩定的檔案身分")
        XCTAssertGreaterThan(sound.fileSize, 0)
    }

    func testRescanDoesNotDuplicate() throws {
        try writeWAV("a.wav")
        try writeWAV("b.wav")
        let library = try addLibrary()
        let id = try XCTUnwrap(library.id)

        _ = scanner.scan(libraryId: id, root: scratch)
        _ = scanner.scan(libraryId: id, root: scratch)

        XCTAssertEqual(try sounds().count, 2, "重新掃描不該產生重複紀錄")
    }

    /// 這是 M2 最重要的一條：掃描器不是整理成果的主人。
    func testRescanPreservesManualMetadata() throws {
        try writeWAV("slam.wav")
        let library = try addLibrary()
        let id = try XCTUnwrap(library.id)
        _ = scanner.scan(libraryId: id, root: scratch)

        let sound = try XCTUnwrap(try sounds().first)
        let soundId = try XCTUnwrap(sound.id)
        let metadata = ManualMetadataService(database: database)
        try metadata.setDisplayName("Heavy Security Door", soundId: soundId, source: .manual)
        try metadata.setCategory(path: "Foley/Doors", soundId: soundId, source: .manual)
        try metadata.setRating(5, soundId: soundId)
        try metadata.setNotes("適合工業場景", soundId: soundId)

        _ = scanner.scan(libraryId: id, root: scratch)

        let after = try XCTUnwrap(try sounds().first)
        XCTAssertEqual(after.displayName, "Heavy Security Door")
        XCTAssertEqual(after.displayNameSource, .manual)
        XCTAssertEqual(after.categorySource, .manual)
        XCTAssertNotNil(after.categoryId)
        XCTAssertEqual(after.rating, 5)
        XCTAssertEqual(after.notes, "適合工業場景")
    }

    /// ROADMAP §41：檔案消失只標記，不刪除。
    func testDeletedFileIsMarkedMissingNotRemoved() throws {
        let doomed = try writeWAV("gone.wav")
        try writeWAV("stays.wav")
        let library = try addLibrary()
        let id = try XCTUnwrap(library.id)
        _ = scanner.scan(libraryId: id, root: scratch)

        let soundId = try XCTUnwrap(try sounds().first(where: { $0.filename == "gone.wav" })?.id)
        try ManualMetadataService(database: database)
            .setDisplayName("使用者整理過的名稱", soundId: soundId, source: .manual)

        try FileManager.default.removeItem(at: doomed)
        let result = scanner.scan(libraryId: id, root: scratch)

        XCTAssertEqual(result.markedMissing, 1)
        let all = try sounds()
        XCTAssertEqual(all.count, 2, "消失的檔案不得從資料庫刪除")
        let missing = try XCTUnwrap(all.first(where: { $0.filename == "gone.wav" }))
        XCTAssertEqual(missing.status, .missing)
        XCTAssertEqual(missing.displayName, "使用者整理過的名稱")
    }

    func testMissingFileComesBackAsOkWhenRestored() throws {
        let file = try writeWAV("flaky.wav")
        let library = try addLibrary()
        let id = try XCTUnwrap(library.id)
        _ = scanner.scan(libraryId: id, root: scratch)

        try FileManager.default.removeItem(at: file)
        _ = scanner.scan(libraryId: id, root: scratch)
        XCTAssertEqual(try sounds().first?.status, .missing)

        try writeWAV("flaky.wav")
        _ = scanner.scan(libraryId: id, root: scratch)
        XCTAssertEqual(try sounds().first?.status, .ok)
    }

    /// 一個壞檔案不能弄垮整個掃描（CLAUDE.md §39）。
    func testUnreadableFileDoesNotStopTheScan() throws {
        try writeWAV("good.wav")
        try Data("this is not audio".utf8)
            .write(to: scratch.appendingPathComponent("broken.wav"))

        let library = try addLibrary()
        let result = scanner.scan(libraryId: try XCTUnwrap(library.id), root: scratch)

        XCTAssertEqual(result.discovered, 2)
        XCTAssertEqual(result.extracted, 1)
        XCTAssertEqual(result.unreadable, 1)

        let all = try sounds()
        XCTAssertEqual(all.count, 2, "讀不動的檔案仍然保留紀錄")
        let broken = try XCTUnwrap(all.first(where: { $0.filename == "broken.wav" }))
        XCTAssertEqual(broken.status, .unreadable)
        let good = try XCTUnwrap(all.first(where: { $0.filename == "good.wav" }))
        XCTAssertNotNil(good.duration, "壞檔案不該影響好檔案的處理")
    }

    func testCancellationStopsEarlyWithoutCorruption() throws {
        for index in 0..<6 {
            try writeWAV("file\(index).wav")
        }
        let library = try addLibrary()
        let result = scanner.scan(libraryId: try XCTUnwrap(library.id),
                                  root: scratch,
                                  isCancelled: { true })

        XCTAssertTrue(result.cancelled)
        XCTAssertNoThrow(try sounds(), "取消之後資料庫仍然可讀")
    }

    func testProgressReportsBothPhases() throws {
        try writeWAV("a.wav")
        try writeWAV("b.wav")
        let library = try addLibrary()

        var phases: [ScanProgress.Phase] = []
        _ = scanner.scan(libraryId: try XCTUnwrap(library.id),
                         root: scratch,
                         progress: { phases.append($0.phase) })

        XCTAssertTrue(phases.contains(.discovering))
        XCTAssertTrue(phases.contains(.extracting))
        XCTAssertEqual(phases.last, .finished)
    }

    func testSupportedExtensions() {
        XCTAssertTrue(AudioMetadataExtractor.isSupported(URL(fileURLWithPath: "/x/a.WAV")))
        XCTAssertTrue(AudioMetadataExtractor.isSupported(URL(fileURLWithPath: "/x/a.aiff")))
        XCTAssertTrue(AudioMetadataExtractor.isSupported(URL(fileURLWithPath: "/x/a.m4a")))
        XCTAssertFalse(AudioMetadataExtractor.isSupported(URL(fileURLWithPath: "/x/a.txt")))
        XCTAssertFalse(AudioMetadataExtractor.isSupported(URL(fileURLWithPath: "/x/a.pdf")))
    }
}

// MARK: - 分頁

extension LibraryScannerTests {

    func testPagingReturnsDistinctSlices() throws {
        for index in 0..<25 {
            try writeWAVForPaging(String(format: "f%02d.wav", index))
        }
        let library = try manager.add(url: scratch)
        _ = scanner.scan(libraryId: try XCTUnwrap(library.id), root: scratch)

        let repository = SoundRepository(database: database)
        XCTAssertEqual(try repository.count(filter: .all), 25)

        let first = try repository.fetch(filter: .all, limit: 20, offset: 0)
        let second = try repository.fetch(filter: .all, limit: 20, offset: 20)

        XCTAssertEqual(first.count, 20)
        XCTAssertEqual(second.count, 5, "最後一頁只剩 5 筆")

        let firstIds = Set(first.compactMap(\.id))
        let secondIds = Set(second.compactMap(\.id))
        XCTAssertTrue(firstIds.isDisjoint(with: secondIds), "兩頁不該重疊")
        XCTAssertEqual(firstIds.count + secondIds.count, 25, "兩頁合起來要涵蓋全部")
    }

    func testPagingIsStableAcrossCalls() throws {
        for index in 0..<10 {
            try writeWAVForPaging(String(format: "g%02d.wav", index))
        }
        let library = try manager.add(url: scratch)
        _ = scanner.scan(libraryId: try XCTUnwrap(library.id), root: scratch)

        let repository = SoundRepository(database: database)
        let a = try repository.fetch(filter: .all, limit: 4, offset: 4)
        let b = try repository.fetch(filter: .all, limit: 4, offset: 4)
        XCTAssertEqual(a.map(\.filename), b.map(\.filename), "同一頁重複查詢要得到相同結果")
    }

    private func writeWAVForPaging(_ name: String) throws {
        let url = scratch.appendingPathComponent(name)
        let sampleRate = 44_100, channels = 1, bits = 16
        let bytesPerFrame = channels * bits / 8
        let frames = Int(Double(sampleRate) * 0.05)
        let dataSize = frames * bytesPerFrame

        var data = Data()
        func put(_ t: String) { data.append(contentsOf: Array(t.utf8)) }
        func p32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func p16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        put("RIFF"); p32(UInt32(36 + dataSize)); put("WAVE")
        put("fmt "); p32(16); p16(1); p16(UInt16(channels)); p32(UInt32(sampleRate))
        p32(UInt32(sampleRate * bytesPerFrame)); p16(UInt16(bytesPerFrame)); p16(UInt16(bits))
        put("data"); p32(UInt32(dataSize)); data.append(Data(count: dataSize))
        try data.write(to: url)
    }
    func testRescanSkipsTheGeneratedTreeAndPreservesOriginalRecord() throws {
        let source = try writeWAV("kick.wav")
        let library = try addLibrary()
        let id = try XCTUnwrap(library.id)
        _ = scanner.scan(libraryId: id, root: scratch)
        let soundId = try XCTUnwrap(try sounds().first?.id)
        try ManualMetadataService(database: database).setDisplayName("My kick", soundId: soundId)
        let destination = scratch.appendingPathComponent("_Organized/Drums/Kick.wav")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: source, to: destination)
        // A nested, user-owned folder with the same name is not our generated tree.
        try writeWAV("Pack/_Organized/user.wav")
        let result = scanner.scan(libraryId: id, root: scratch)
        XCTAssertEqual(result.discovered, 2)
        XCTAssertEqual(try sounds().count, 2)
        XCTAssertEqual(try sounds().first(where: { $0.id == soundId })?.displayName, "My kick")
        XCTAssertFalse(try sounds().contains(where: { $0.relativePath.hasPrefix("_Organized/") }))
    }

    func testRescanAfterLibraryRenameKeepsMetadataAndIdentity() throws {
        try writeWAV("kick.wav")
        let library = try addLibrary()
        let id = try XCTUnwrap(library.id)
        _ = scanner.scan(libraryId: id, root: scratch)
        let soundId = try XCTUnwrap(try sounds().first?.id)
        try ManualMetadataService(database: database).setDisplayName("My kick", soundId: soundId)
        let renamed = scratch.deletingLastPathComponent().appendingPathComponent("renamed-" + UUID().uuidString)
        try FileManager.default.moveItem(at: scratch, to: renamed)
        scratch = renamed
        _ = try manager.refreshAvailability()
        _ = scanner.scan(libraryId: id, root: renamed)
        XCTAssertEqual(try sounds().count, 1)
        XCTAssertEqual(try sounds().first?.id, soundId)
        XCTAssertEqual(try sounds().first?.displayName, "My kick")
        XCTAssertEqual(try sounds().first?.status, .ok)
    }

    func testExistingGeneratedRecordsArePreservedForManualRepair() throws {
        try writeWAV("kick.wav")
        let libraryId = try XCTUnwrap(addLibrary().id)
        let duplicateId = try database.writer.write { db in
            var sound = Sound(libraryId: libraryId, filePath: scratch.appendingPathComponent("_Organized/Kick.wav").path,
                relativePath: "_Organized/Kick.wav", filename: "Kick.wav", fileExtension: "wav", displayName: "Keep metadata", displayNameSource: .manual)
            try sound.insert(db)
            return sound.id!
        }
        _ = scanner.scan(libraryId: libraryId, root: scratch)
        let duplicate = try database.writer.read { try Sound.fetchOne($0, key: duplicateId) }
        XCTAssertEqual(duplicate?.displayName, "Keep metadata")
        XCTAssertEqual(duplicate?.status, .ok)
        XCTAssertNil(duplicate?.duration)
    }

    func testExternalAudioSymlinkIsSkippedAndCannotBreakRelinking() throws {
        let external = try writeWAV("outside.wav")
        try writeWAV("Library/inside.wav")
        let folder = scratch.appendingPathComponent("Library")
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("alias.wav"), withDestinationURL: external)
        let libraryId = try XCTUnwrap(manager.add(url: folder).id)
        let first = scanner.scan(libraryId: libraryId, root: folder)
        XCTAssertEqual(first.discovered, 1)
        let soundId = try XCTUnwrap(try sounds().first?.id)
        try ManualMetadataService(database: database).setDisplayName("Keep", soundId: soundId)
        let moved = scratch.appendingPathComponent("RenamedLibrary")
        try FileManager.default.moveItem(at: folder, to: moved)
        _ = try manager.refreshAvailability()
        let second = scanner.scan(libraryId: libraryId, root: moved)
        XCTAssertEqual(second.discovered, 1)
        XCTAssertEqual(try sounds().count, 1)
        XCTAssertEqual(try sounds().first?.id, soundId)
        XCTAssertEqual(try sounds().first?.displayName, "Keep")
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
    }

    func testMissingDetectionUsesScanIdentityInsteadOfTimestampOrder() throws {
        let file = try writeWAV("gone.wav")
        let libraryId = try XCTUnwrap(addLibrary().id)
        _ = scanner.scan(libraryId: libraryId, root: scratch)
        // Even a future timestamp cannot hide an absent file from this scan.
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sounds SET last_seen_at = ? WHERE library_id = ?", arguments: [Date().addingTimeInterval(3600), libraryId])
        }
        try FileManager.default.removeItem(at: file)
        let result = scanner.scan(libraryId: libraryId, root: scratch)
        XCTAssertEqual(result.markedMissing, 1)
        XCTAssertEqual(try sounds().first?.status, .missing)
    }

    func testCancelledOldScanCannotMarkNewScanResultsMissing() throws {
        try writeWAV("tone.wav")
        let id = try XCTUnwrap(addLibrary().id)
        let first = LibraryScanner(database: database, batchSize: 1)
        var startedNew = false
        var cancelled = false
        let old = first.scan(libraryId: id, root: scratch, isCancelled: { cancelled }, progress: { update in
            if update.phase == .discovering && update.discovered == 1 && !startedNew {
                startedNew = true
                cancelled = true
                let newer = LibraryScanner(database: self.database).scan(libraryId: id, root: self.scratch)
                XCTAssertFalse(newer.cancelled)
                XCTAssertEqual(newer.markedMissing, 0)
            }
        })
        XCTAssertTrue(startedNew)
        XCTAssertTrue(old.cancelled)
        XCTAssertEqual(old.markedMissing, 0)
        XCTAssertEqual(try sounds().first?.status, .ok)
    }

    func testSupersededScanCannotWriteLaterDiscoveryBatches() throws {
        for name in ["a.wav", "b.wav", "c.wav"] { try writeWAV(name) }
        let id = try XCTUnwrap(addLibrary().id)
        var restarted = false
        let old = LibraryScanner(database: database, batchSize: 1).scan(libraryId: id, root: scratch, progress: { update in
            if update.phase == .discovering && update.discovered == 1 && !restarted {
                restarted = true
                _ = LibraryScanner(database: self.database).scan(libraryId: id, root: self.scratch)
            }
        })
        XCTAssertTrue(old.cancelled, "跨 Scanner 實例也必須停止舊寫入，不只依賴 Task.cancel")
        let stale = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sounds s JOIN libraries l ON l.id=s.library_id WHERE l.id=? AND (s.last_scan_token <> l.active_scan_token OR s.status <> 'ok')", arguments: [id])
        }
        XCTAssertEqual(stale, 0)
        XCTAssertEqual(try sounds().count, 3)
    }

    func testSupersededMetadataBatchCannotOverwriteNewMeasurements() throws {
        try writeWAV("tone.wav", seconds: 0.25)
        let id = try XCTUnwrap(addLibrary().id)
        var restarted = false
        let old = LibraryScanner(database: database, batchSize: 10).scan(libraryId: id, root: scratch, progress: { update in
            if update.phase == .extracting && update.processed == 1 && !restarted {
                restarted = true
                do { try self.writeWAV("tone.wav", seconds: 0.75) }
                catch { XCTFail("fixture rewrite failed: \(error)") }
                _ = LibraryScanner(database: self.database).scan(libraryId: id, root: self.scratch)
            }
        })
        XCTAssertTrue(restarted)
        XCTAssertTrue(old.cancelled)
        let sound = try XCTUnwrap(try sounds().first)
        XCTAssertEqual(try XCTUnwrap(sound.duration), 0.75, accuracy: 0.01)
        XCTAssertEqual(sound.status, .ok)
    }

    func testDifferentLibrariesDoNotSupersedeEachOther() throws {
        try writeWAV("A/tone.wav")
        try writeWAV("B/tone.wav")
        let a = scratch.appendingPathComponent("A")
        let b = scratch.appendingPathComponent("B")
        let aId = try XCTUnwrap(manager.add(url: a).id)
        let bId = try XCTUnwrap(manager.add(url: b).id)
        var startedB = false
        let result = LibraryScanner(database: database, batchSize: 1).scan(libraryId: aId, root: a, progress: { update in
            if update.phase == .discovering && update.discovered == 1 && !startedB {
                startedB = true
                XCTAssertFalse(LibraryScanner(database: self.database).scan(libraryId: bId, root: b).cancelled)
            }
        })
        XCTAssertTrue(startedB)
        XCTAssertFalse(result.cancelled)
        XCTAssertTrue(try sounds().allSatisfy { $0.status == .ok })
        XCTAssertEqual(try sounds().count, 2)
    }

    func testCancellationAfterLastDiscoveryDoesNotFinalizeMissingFiles() throws {
        let gone = try writeWAV("gone.wav")
        try writeWAV("stay.wav")
        let id = try XCTUnwrap(addLibrary().id)
        _ = scanner.scan(libraryId: id, root: scratch)
        try FileManager.default.removeItem(at: gone)
        var cancelled = false
        let result = LibraryScanner(database: database, batchSize: 1).scan(libraryId: id, root: scratch,
            isCancelled: { cancelled }, progress: { update in
                if update.phase == .discovering && update.discovered == 1 { cancelled = true }
            })
        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.markedMissing, 0)
        XCTAssertEqual(try sounds().first(where: { $0.filename == "gone.wav" })?.status, .ok)
    }

    func testDatabaseWriteFailureDoesNotReportSuccessfulScan() throws {
        try writeWAV("tone.wav")
        let id = try XCTUnwrap(addLibrary().id)
        try database.writer.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_metadata BEFORE UPDATE OF duration ON sounds BEGIN SELECT RAISE(ABORT, 'fixture write failure'); END")
        }
        var last = ScanProgress()
        let result = scanner.scan(libraryId: id, root: scratch, progress: { last = $0 })
        XCTAssertNotNil(result.errorMessage)
        XCTAssertEqual(last.phase, .failed)
        XCTAssertNil(try sounds().first?.duration)
    }

    func testOwnershipIsSharedAcrossIndependentDatabaseConnections() throws {
        try writeWAV("tone.wav")
        let path = scratch.appendingPathComponent("fixture.sqlite").path
        let firstDB = try AppDatabase(DatabaseQueue(path: path), seedTaxonomy: TestSupport.taxonomy())
        let secondDB = try AppDatabase(DatabaseQueue(path: path))
        let id = try XCTUnwrap(LibraryManager(database: firstDB).add(url: scratch).id)
        var restarted = false
        let old = LibraryScanner(database: firstDB, batchSize: 1).scan(libraryId: id, root: scratch, progress: { update in
            if update.phase == .discovering && update.discovered == 1 && !restarted {
                restarted = true
                XCTAssertFalse(LibraryScanner(database: secondDB).scan(libraryId: id, root: self.scratch).cancelled)
            }
        })
        XCTAssertTrue(old.cancelled)
        let statuses = try firstDB.writer.read { try String.fetchAll($0, sql: "SELECT status FROM sounds") }
        XCTAssertEqual(statuses, ["ok"])
    }

    func testRelinkingInvalidatesPendingMetadataFromThePreviousRoot() throws {
        let file = try writeWAV("tone.wav")
        let id = try XCTUnwrap(addLibrary().id)
        let soundId = try database.writer.write { db in
            var sound = Sound(libraryId: id, filePath: BookmarkStore.normalizedURL(file).path,
                relativePath: "tone.wav", filename: "tone.wav", fileExtension: "wav",
                displayName: "Keep", displayNameSource: .manual)
            try sound.insert(db)
            return sound.id!
        }
        var moved = false
        let result = LibraryScanner(database: database, batchSize: 10).scan(libraryId: id, root: scratch, progress: { update in
            if update.phase == .extracting && update.processed == 1 && !moved {
                moved = true
                let destination = self.scratch.deletingLastPathComponent().appendingPathComponent("relocated-" + UUID().uuidString)
                do {
                    try FileManager.default.moveItem(at: self.scratch, to: destination)
                    self.scratch = destination
                    _ = try self.manager.refreshAvailability()
                } catch { XCTFail("relink fixture failed: \(error)") }
            }
        })
        XCTAssertTrue(moved)
        XCTAssertTrue(result.cancelled)
        let sound = try database.writer.read { try Sound.fetchOne($0, key: soundId) }
        XCTAssertEqual(sound?.filePath, BookmarkStore.normalizedURL(scratch.appendingPathComponent("tone.wav")).path)
        XCTAssertEqual(sound?.displayName, "Keep")
        XCTAssertNil(sound?.duration, "舊根目錄的待提交 metadata 必須失效")
    }

}
