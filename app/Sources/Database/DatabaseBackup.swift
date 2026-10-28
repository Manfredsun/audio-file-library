import Foundation
import GRDB

/// 資料庫備份。
///
/// 這個檔案是使用者人工成果的**唯一一份**：分頁、人工設定的分類與風格、
/// 接受過的建議。而且它在系統碟上，不在他的外接碟上——音色庫還在，
/// 這些東西卻可能沒了。
///
/// **備份的時機比頻率重要。** 每次啟動都複製 84 MB 只是在耗電；
/// 真正會讓人想倒回去的是「一次寫幾千筆」的那幾個動作，
/// 所以備份掛在那些動作前面。
enum DatabaseBackup {

    /// 自動備份保留幾份。
    ///
    /// 三份夠了：要倒回去通常是剛剛那一次做壞了。留太多只是在系統碟上堆 84 MB 的倍數。
    static let keepCount = 3

    enum Trigger: String {
        case batchAccept = "批次接受"
        case pathReread = "重讀路徑"
        case organize = "整理"
        case manual = "手動"

        /// 檔名裡用的安全字串。
        var slug: String {
            switch self {
            case .batchAccept: return "accept"
            case .pathReread: return "reread"
            case .organize: return "organize"
            case .manual: return "manual"
            }
        }
    }

    struct Entry: Equatable, Identifiable {
        var url: URL
        var createdAt: Date
        var bytes: Int64
        var trigger: String

        var id: String { url.path }
    }

    /// 備份放在資料庫旁邊的 `Backups/`。
    static func folder(beside databasePath: String) -> URL {
        URL(fileURLWithPath: databasePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
    }

    /// 做一份備份。
    ///
    /// 用 `VACUUM INTO` 而不是複製檔案：資料庫開著 WAL，直接複製 `.sqlite`
    /// 會漏掉還在 `-wal` 裡的東西，複製出來的是一份**看起來正常但內容較舊**的檔案。
    /// 那種備份最糟——它會讓人以為自己有備份。
    ///
    /// `VACUUM INTO` 由 SQLite 自己把完整狀態寫成一個乾淨的單檔，順便壓掉空洞。
    @discardableResult
    static func make(from database: AppDatabase, to destination: URL) throws -> URL {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // 目標存在時 VACUUM INTO 會失敗，這是 SQLite 刻意的——絕不覆蓋。
        if FileManager.default.fileExists(atPath: destination.path) {
            throw AppError.databaseError("備份檔已經存在：\(destination.lastPathComponent)")
        }
        try database.writer.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [destination.path])
        }
        return destination
    }

    /// 自動備份失敗回 nil；批次寫入的呼叫端必須以 required 守門。
    @discardableResult
    static func automatic(for database: AppDatabase,
                          databasePath: String,
                          trigger: Trigger) -> URL? {
        let directory = folder(beside: databasePath)
        let stamp = filenameFormatter.string(from: Date()) + "-" + UUID().uuidString.lowercased()
        let destination = directory.appendingPathComponent(
            "library-\(trigger.slug)-\(stamp).sqlite")
        do {
            let url = try make(from: database, to: destination)
            prune(in: directory)
            return url
        } catch {
            return nil
        }
    }

    @discardableResult
    static func required(for database: AppDatabase, trigger: Trigger) throws -> URL {
        guard let path = database.path,
              let backup = automatic(for: database, databasePath: path, trigger: trigger) else {
            throw AppError.databaseError("備份失敗，已停止批次動作")
        }
        return backup
    }

    /// 只留最新的幾份。
    ///
    /// 只刪**這個資料夾裡、我們自己命名規則的**檔案。使用者放進來的東西不碰——
    /// 跟 D-032 的撤銷同一條原則：沒有紀錄的東西一個字都不能刪。
    static func prune(in directory: URL, keeping keep: Int = keepCount) {
        let entries = list(in: directory)
        guard entries.count > keep else { return }
        for entry in entries.dropFirst(keep) {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    /// 現有的備份，新的在前。
    static func list(in directory: URL) -> [Entry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names
            .filter { $0.range(of: #"^library-(accept|reread|organize|manual)-[0-9]{8}-[0-9]{6}(-[0-9a-f-]{36})?\.sqlite$"#, options: .regularExpression) != nil }
            .compactMap { name -> Entry? in
                let url = directory.appendingPathComponent(name)
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey,
                                                                    .fileSizeKey]) else { return nil }
                return Entry(url: url,
                             createdAt: values.contentModificationDate ?? .distantPast,
                             bytes: Int64(values.fileSize ?? 0),
                             trigger: triggerName(from: name))
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private static func triggerName(from filename: String) -> String {
        let parts = filename.split(separator: "-")
        guard parts.count >= 2 else { return "" }
        switch parts[1] {
        case "accept": return Trigger.batchAccept.rawValue
        case "reread": return Trigger.pathReread.rawValue
        case "organize": return Trigger.organize.rawValue
        case "manual": return Trigger.manual.rawValue
        default: return ""
        }
    }

    /// 檔名用的時間戳。排序要能直接照字串排，所以是年月日時分秒。
    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
