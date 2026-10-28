import Foundation
import GRDB

/// 掃描進度。
struct ScanProgress: Equatable {
    enum Phase: String, Equatable {
        case idle
        case discovering   // 盤點檔案：快
        case extracting    // 讀音訊詮釋資料：慢
        case finished
        case cancelled
        case failed
    }

    var phase: Phase = .idle
    var discovered: Int = 0
    var processed: Int = 0
    var total: Int?
    var currentName: String = ""
    var message: String = ""

    var fraction: Double {
        guard let total, total > 0 else { return 0 }
        return min(1, Double(processed) / Double(total))
    }

    var isRunning: Bool { phase == .discovering || phase == .extracting }
}

struct ScanResult: Equatable {
    var errorMessage: String?
    var discovered = 0
    var inserted = 0
    var extracted = 0
    var unreadable = 0
    var markedMissing = 0
    var cancelled = false
}

/// 兩段式掃描。
///
/// 第一段盤點檔案系統，只寫路徑與大小日期——很快，清單馬上就會出現。
/// 第二段才逐檔開啟音訊讀長度與取樣率——慢，但可以取消，而且中途離開也不會弄壞任何東西。
///
/// 分兩段是刻意的（ROADMAP §31）：把它們塞成一條阻塞管線，
/// 使用者就得盯著空白畫面等上幾分鐘。
struct LibraryScanner {
    let database: AppDatabase

    /// 每批寫入的筆數。批次太小交易成本高，太大則取消反應變慢。
    var batchSize: Int = 300

    init(database: AppDatabase, batchSize: Int = 300) {
        self.database = database
        self.batchSize = batchSize
    }

    // MARK: - 主流程

    func scan(libraryId: Int64,
              root: URL,
              isCancelled: () -> Bool = { false },
              progress: (ScanProgress) -> Void = { _ in }) -> ScanResult {

        let root = BookmarkStore.normalizedURL(root)
        var result = ScanResult()
        let startedAt = Date()
        let scanToken = UUID().uuidString
        var state = ScanProgress(phase: .discovering)
        func checkCancellation() throws {
            if isCancelled() { throw ScanInterrupted.cancelled }
        }
        do {
            try checkCancellation()
            try database.writer.write { db in
                try checkCancellation()
                try db.execute(sql: "UPDATE libraries SET active_scan_token = ? WHERE id = ?", arguments: [scanToken, libraryId])
                guard db.changesCount == 1 else { throw AppError.scanFailed(L10n.tr("音色庫紀錄不存在")) }
            }
            progress(state)

            // --- 第一段：盤點 ---
            var batch: [DiscoveredFile] = []
            var discovered = 0

            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey,
                                          .creationDateKey, .contentModificationDateKey]
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                state.phase = .failed
                state.message = L10n.tr("無法列舉資料夾內容")
                result.errorMessage = state.message
                progress(state)
                return result
            }

            for case let discoveredURL as URL in enumerator {
                // Preserve the scanner's no-follow policy before resolving path aliases.
                guard let raw = try? discoveredURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
                      raw.isSymbolicLink != true else { continue }
                let url = BookmarkStore.normalizedURL(discoveredURL)
                if isCancelled() {
                    result.cancelled = true
                    state.phase = .cancelled
                    progress(state)
                    return result
                }
                if Self.relativePath(of: url, under: root) == OrganizeRun.treeFolder {
                    enumerator.skipDescendants()
                    continue
                }
                guard AudioMetadataExtractor.isSupported(url) else { continue }
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }

                batch.append(DiscoveredFile(
                    url: url,
                    relativePath: Self.relativePath(of: url, under: root),
                    size: Int64(values.fileSize ?? 0),
                    createdAt: values.creationDate,
                    modifiedAt: values.contentModificationDate))

                discovered += 1

                if batch.count >= batchSize {
                    result.inserted += try upsert(batch, libraryId: libraryId, seenAt: startedAt, scanToken: scanToken)
                    batch.removeAll(keepingCapacity: true)
                    state.discovered = discovered
                    state.currentName = url.lastPathComponent
                    progress(state)
                }
            }

            if !batch.isEmpty {
                result.inserted += try upsert(batch, libraryId: libraryId, seenAt: startedAt, scanToken: scanToken)
                batch.removeAll(keepingCapacity: true)
            }

            result.discovered = discovered
            state.discovered = discovered
            state.total = discovered

            // --- 消失的檔案：標記，不刪除 ---
            try checkCancellation()
            result.markedMissing = try markMissing(libraryId: libraryId, scanToken: scanToken)

            // --- 第二段：音訊詮釋資料 ---
            state.phase = .extracting
            state.processed = 0
            progress(state)

            let pending = try soundsNeedingMetadata(libraryId: libraryId, scanToken: scanToken)
            state.total = pending.count

            var updates: [(Int64, AudioMetadata?, String?)] = []
            for (index, sound) in pending.enumerated() {
                if isCancelled() {
                    if !updates.isEmpty { try applyMetadata(updates, libraryId: libraryId, scanToken: scanToken) }
                    result.cancelled = true
                    state.phase = .cancelled
                    progress(state)
                    return result
                }

                let url = URL(fileURLWithPath: sound.filePath)
                let metadata = AudioMetadataExtractor.extract(from: url)
                let identifier = AudioMetadataExtractor.fileIdentifier(for: url)
                if metadata == nil { result.unreadable += 1 } else { result.extracted += 1 }
                updates.append((sound.id ?? 0, metadata, identifier))

                if updates.count >= batchSize {
                    try applyMetadata(updates, libraryId: libraryId, scanToken: scanToken)
                    updates.removeAll(keepingCapacity: true)
                }

                state.processed = index + 1
                state.currentName = sound.filename
                if index % 25 == 0 { progress(state) }
            }
            if !updates.isEmpty { try applyMetadata(updates, libraryId: libraryId, scanToken: scanToken) }

            try checkCancellation()
            try database.writer.write { db in
                try requireActiveScan(libraryId: libraryId, scanToken: scanToken, in: db)
                try db.execute(sql: "UPDATE libraries SET last_scanned_at = ? WHERE id = ?", arguments: [Date(), libraryId])
            }
            state.phase = .finished
            state.processed = pending.count
            progress(state)

            AppLog.library.info("掃描完成 discovered=\(result.discovered, privacy: .public) extracted=\(result.extracted, privacy: .public) unreadable=\(result.unreadable, privacy: .public) missing=\(result.markedMissing, privacy: .public)")
            return result
        } catch let interruption as ScanInterrupted {
            result.cancelled = true
            state.phase = .cancelled
            if case .superseded = interruption { state.message = L10n.tr("較新的掃描已接手") }
            progress(state)
            return result
        } catch {
            result.errorMessage = error.localizedDescription
            state.phase = .failed
            state.message = error.localizedDescription
            progress(state)
            return result
        }
    }

    private enum ScanInterrupted: Error { case cancelled, superseded }

    /// This check runs inside the same transaction as every corresponding write.
    private func requireActiveScan(libraryId: Int64, scanToken: String, in db: Database) throws {
        let active = try String.fetchOne(db, sql: "SELECT active_scan_token FROM libraries WHERE id = ?", arguments: [libraryId])
        guard active == scanToken else { throw ScanInterrupted.superseded }
    }

    // MARK: - 內部

    struct DiscoveredFile {
        let url: URL
        let relativePath: String
        let size: Int64
        let createdAt: Date?
        let modifiedAt: Date?
    }

    static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = BookmarkStore.normalizedURL(root).path
        let filePath = BookmarkStore.normalizedURL(url).path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        var relative = String(filePath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative.isEmpty ? url.lastPathComponent : relative
    }

    /// upsert：已存在的檔案只更新檔案系統事實。
    ///
    /// display_name、category、tags、notes、rating 一個都不碰——
    /// 重新掃描不是重設使用者的整理成果。
    private func upsert(_ files: [DiscoveredFile], libraryId: Int64, seenAt: Date, scanToken: String) throws -> Int {
        return try database.writer.write { db -> Int in
            try requireActiveScan(libraryId: libraryId, scanToken: scanToken, in: db)
            let before = try Sound.filter(Sound.Columns.libraryId == libraryId).fetchCount(db)
            for file in files {
                try db.execute(sql: """
                    INSERT INTO sounds
                        (library_id, file_path, relative_path, folder_path, filename, file_extension,
                         file_size, file_created_at, file_modified_at,
                         favorite, rating, status, analysis_status, needs_review,
                         date_indexed, last_seen_at, last_scan_token, play_count)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 'ok', 'none', 0, ?, ?, ?, 0)
                    ON CONFLICT(library_id, file_path) DO UPDATE SET
                        relative_path    = excluded.relative_path,
                        folder_path      = excluded.folder_path,
                        filename         = excluded.filename,
                        file_extension   = excluded.file_extension,
                        file_size        = excluded.file_size,
                        file_created_at  = excluded.file_created_at,
                        file_modified_at = excluded.file_modified_at,
                        last_seen_at     = excluded.last_seen_at,
                        last_scan_token  = excluded.last_scan_token,
                        status           = 'ok'
                    """,
                    arguments: [libraryId,
                                file.url.path,
                                file.relativePath,
                                FolderPath.folder(of: file.relativePath),
                                file.url.lastPathComponent,
                                file.url.pathExtension.lowercased(),
                                file.size,
                                file.createdAt,
                                file.modifiedAt,
                                seenAt,
                                seenAt,
                                scanToken])
            }
            let after = try Sound.filter(Sound.Columns.libraryId == libraryId).fetchCount(db)
            return after - before
        }
    }

    /// 這次掃描沒看到的檔案：標成 missing，保留全部 metadata。
    private func markMissing(libraryId: Int64, scanToken: String) throws -> Int {
        try database.writer.write { db -> Int in
            try requireActiveScan(libraryId: libraryId, scanToken: scanToken, in: db)
            try db.execute(sql: """
                UPDATE sounds
                   SET status = 'missing'
                 WHERE library_id = ?
                   AND status != 'missing'
                   AND substr(relative_path, 1, 11) <> '_Organized/'
                   AND (last_scan_token IS NULL OR last_scan_token <> ?)
                """, arguments: [libraryId, scanToken])
            return db.changesCount
        }
    }

    private func soundsNeedingMetadata(libraryId: Int64, scanToken: String) throws -> [Sound] {
        try database.writer.read { db in
            try requireActiveScan(libraryId: libraryId, scanToken: scanToken, in: db)
            return try Sound
                .filter(Sound.Columns.libraryId == libraryId)
                .filter(Column(L10n.tr("status")) == FileStatus.ok.rawValue)
                .filter(Column("duration") == nil)
                .filter(sql: "substr(relative_path, 1, 11) <> ?", arguments: ["_Organized/"])
                .fetchAll(db)
        }
    }

    private func applyMetadata(_ updates: [(Int64, AudioMetadata?, String?)], libraryId: Int64, scanToken: String) throws {
        try database.writer.write { db in
            try requireActiveScan(libraryId: libraryId, scanToken: scanToken, in: db)
            for (id, metadata, identifier) in updates {
                if let metadata {
                    try db.execute(sql: """
                        UPDATE sounds
                           SET duration = ?, sample_rate = ?, bit_depth = ?,
                               channel_count = ?, file_identifier = ?
                         WHERE id = ?
                        """,
                        arguments: [metadata.duration, metadata.sampleRate, metadata.bitDepth,
                                    metadata.channelCount, identifier, id])
                } else {
                    // 讀不到音訊：保留紀錄，但誠實標記它讀不動
                    try db.execute(sql: "UPDATE sounds SET file_identifier = ?, status = ? WHERE id = ?",
                                   arguments: [identifier, FileStatus.unreadable.rawValue, id])
                }
            }
        }
    }
}
