import Foundation
import GRDB

/// 音色庫的新增、解析與可用性維護。
///
/// 三條不可違反的規則（ROADMAP §30）：
///   1. 外接碟離線只標記 offline，絕不刪除任何紀錄
///   2. 同一個路徑重複加入時更新既有紀錄，不製造重複的音色庫
///   3. 資料夾被搬移時用書籤重新連結，並更新路徑
struct LibraryManager {
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - 讀取

    func libraries() throws -> [Library] {
        try database.writer.read { db in
            try Library.order(Column("created_at")).fetchAll(db)
        }
    }

    func library(id: Int64) throws -> Library? {
        try database.writer.read { db in try Library.fetchOne(db, key: id) }
    }

    // MARK: - 新增

    /// 加入音色庫。已存在同一個根路徑時更新既有紀錄而不新增。
    @discardableResult
    func add(url: URL, name: String? = nil) throws -> Library {
        // 解析 symlink：/var 與 /private/var 指向同一個地方，
        // 但書籤解析回來的一定是後者。不統一的話每次重新整理都會誤判成「被搬移」。
        let standardized = BookmarkStore.normalizedURL(url)
        let bookmark = try? BookmarkStore.makeBookmark(for: standardized)
        let displayName = name ?? standardized.lastPathComponent
        let available: Library.Availability =
            BookmarkStore.isReachableDirectory(standardized) ? .available : .offline

        return try database.writer.write { db in
            if var existing = try Library
                .filter(Column("root_path") == standardized.path)
                .fetchOne(db) {
                existing.name = displayName
                existing.bookmarkData = bookmark ?? existing.bookmarkData
                existing.availabilityStatus = available
                try existing.update(db)
                AppLog.library.info("更新既有音色庫 \(displayName, privacy: .public)")
                return existing
            }

            var library = Library(name: displayName,
                                  rootPath: standardized.path,
                                  bookmarkData: bookmark,
                                  availabilityStatus: available)
            try library.insert(db)
            AppLog.library.info("加入音色庫 \(displayName, privacy: .public)")
            return library
        }
    }

    // MARK: - 可用性

    /// 解析單一音色庫的實際位置。
    ///
    /// 優先用書籤——資料夾被搬移或改名時，只有書籤找得回來。
    /// 書籤失效才退回已記錄的路徑。
    func resolveURL(for library: Library) -> URL? {
        if let data = library.bookmarkData,
           let resolved = try? BookmarkStore.resolve(data),
           BookmarkStore.isReachableDirectory(resolved.url) {
            return BookmarkStore.normalizedURL(resolved.url)
        }
        let url = URL(fileURLWithPath: library.rootPath)
        return BookmarkStore.isReachableDirectory(url)
            ? BookmarkStore.normalizedURL(url)
            : nil
    }

    /// 重新檢查所有音色庫的可用性，並在必要時重新連結。
    /// 離線的音色庫保留全部 metadata，只改狀態。
    @discardableResult
    func refreshAvailability() throws -> [Library] {
        try database.writer.write { db in
            var updated: [Library] = []
            for var library in try Library.fetchAll(db) {
                let resolved = resolveURL(for: library)
                let newStatus: Library.Availability = resolved == nil ? .offline : .available
                var didRelink = false

                // 資料夾被搬移過：更新路徑並重新產生書籤
                if let resolved, resolved.path != library.rootPath {
                    AppLog.library.info("重新連結音色庫 \(library.name, privacy: .public)")
                    try Self.rebaseSoundPaths(libraryId: library.id ?? 0, from: library.rootPath, to: resolved.path, in: db)
                    library.rootPath = resolved.path
                    library.bookmarkData = (try? BookmarkStore.makeBookmark(for: resolved)) ?? library.bookmarkData
                    didRelink = true
                }

                if didRelink || library.availabilityStatus != newStatus {
                    library.availabilityStatus = newStatus
                    try library.update(db)
                }
                updated.append(library)
            }
            return updated
        }
    }

    /// Rebase references in the same transaction as the bookmark. Never merge rows:
    /// a collision could silently discard a person's metadata or collection membership.
    private static func rebaseSoundPaths(libraryId: Int64, from oldRoot: String,
                                         to newRoot: String, in db: Database) throws {
        let rows = try Row.fetchAll(db, sql: "SELECT id, relative_path, file_path, file_identifier FROM sounds WHERE library_id = ?", arguments: [libraryId])
        var destinations = Set<String>()
        var changes: [(Int64, String)] = []
        for row in rows {
            let id: Int64 = row["id"]
            let relative: String = row["relative_path"]
            let oldPath: String = row["file_path"]
            guard OrganizeFileSafety.validRelativePath(relative),
                  BookmarkStore.normalizedURL(URL(fileURLWithPath: oldPath)).path ==
                    BookmarkStore.normalizedURL(URL(fileURLWithPath: oldRoot).appendingPathComponent(relative)).path else {
                throw AppError.fileConflict(L10n.tr("音效路徑與音色庫不一致；已保留全部紀錄"))
            }
            let path = (newRoot as NSString).appendingPathComponent(relative)
            guard destinations.insert(path).inserted else { throw AppError.fileConflict(path) }
            let collision = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sounds WHERE library_id = ? AND file_path = ? AND id <> ?", arguments: [libraryId, path, id]) ?? 0
            guard collision == 0 else { throw AppError.fileConflict(path) }
            let identifier: String? = row["file_identifier"]
            if FileManager.default.fileExists(atPath: path), let identifier,
               AudioMetadataExtractor.fileIdentifier(for: URL(fileURLWithPath: path)) != identifier {
                throw AppError.fileConflict(L10n.tr("重新連結的檔案身分不同：") + relative)
            }
            changes.append((id, path))
        }
        // A scan still holding the previous root must not recreate its old paths.
        try db.execute(sql: "UPDATE libraries SET active_scan_token = NULL WHERE id = ?", arguments: [libraryId])
        for (id, path) in changes {
            try db.execute(sql: "UPDATE sounds SET file_path = ? WHERE id = ?", arguments: [path, id])
        }
        let entries = try Row.fetchAll(db, sql: """
            SELECT j.id, j.link_path, j.batch_id, b.root_path FROM organize_journal j
            JOIN sounds s ON s.id = j.sound_id JOIN organize_batches b ON b.id = j.batch_id
            WHERE s.library_id = ?
            """, arguments: [libraryId])
        for row in entries {
            let path = BookmarkStore.normalizedURL(URL(fileURLWithPath: row["link_path"] as String)).path
            let root = BookmarkStore.normalizedURL(URL(fileURLWithPath: row["root_path"] as String)).path
            let prefix = BookmarkStore.normalizedURL(URL(fileURLWithPath: oldRoot)).path
            guard path.hasPrefix(prefix + "/"), root.hasPrefix(prefix + "/") else { continue }
            let rebasedPath = newRoot + String(path.dropFirst(prefix.count))
            let rebasedRoot = newRoot + String(root.dropFirst(prefix.count))
            try db.execute(sql: "UPDATE organize_journal SET link_path = ? WHERE id = ?", arguments: [rebasedPath, row["id"] as Int64])
            try db.execute(sql: "UPDATE organize_batches SET root_path = ? WHERE id = ?", arguments: [rebasedRoot, row["batch_id"] as Int64])
        }
    }

    /// 移除音色庫紀錄。這會一併移除它底下的音效 metadata，
    /// 但**不會動到磁碟上的任何檔案**。
    func remove(libraryId: Int64) throws {
        try database.writer.write { db in
            _ = try Library.deleteOne(db, key: libraryId)
            AppLog.library.info("移除音色庫紀錄 id=\(libraryId, privacy: .public)")
        }
    }

    func soundCount(libraryId: Int64) throws -> Int {
        try database.writer.read { db in
            try Sound.filter(Sound.Columns.libraryId == libraryId).fetchCount(db)
        }
    }
}
