import Foundation
import GRDB

/// 整理紀錄的寫入介面。抽成協定是為了讓執行層不依賴資料庫，測試跑得快。
protocol OrganizeJournalWriting {
    func beginBatch(scope: String, root: String) throws -> Int64
    func record(batchId: Int64, soundId: Int64, linkPath: String, fileIdentifier: String) throws
    func finishBatch(_ batchId: Int64, linkCount: Int) throws
    func entries(batchId: Int64) throws -> [OrganizeJournalEntry]
    func claimUndo(entryId: Int64) throws -> Bool
    func recordUndo(entryId: Int64, state: String, recoveryPath: String?) throws
    func markUndone(_ batchId: Int64) throws
}

struct OrganizeJournalEntry: Equatable {
    var id: Int64
    var batchId: Int64
    var path: String
    var root: String
    var fileIdentifier: String?
    var undoState: String
    var recoveryPath: String? = nil
}

/// 一個整理批次。撤銷的單位。
struct OrganizeBatch: Equatable, Identifiable {
    var id: Int64
    var createdAt: Date
    /// 這一批是從哪個檢視跑的，例如「分頁：Kick」。撤銷清單要讓人認得出來。
    var scope: String
    var rootPath: String
    var linkCount: Int
    var undoneAt: Date?
    var recoveryPaths: [String] = []

    var isUndone: Bool { undoneAt != nil }
}

struct OrganizeJournal: OrganizeJournalWriting {
    let database: AppDatabase

    func beginBatch(scope: String, root: String) throws -> Int64 {
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO organize_batches (created_at, scope, root_path, link_count)
                VALUES (?, ?, ?, 0)
                """, arguments: [Date(), scope, root])
            return db.lastInsertedRowID
        }
    }

    func record(batchId: Int64, soundId: Int64, linkPath: String, fileIdentifier: String) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO organize_journal
                       (batch_id, sound_id, file_identifier, link_path, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [batchId, soundId, fileIdentifier, linkPath, Date()])
        }
    }

    func finishBatch(_ batchId: Int64, linkCount: Int) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE organize_batches SET link_count = ? WHERE id = ?",
                           arguments: [linkCount, batchId])
        }
    }

    func linkPaths(batchId: Int64) throws -> [String] {
        try database.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT link_path FROM organize_journal WHERE batch_id = ? ORDER BY id
                """, arguments: [batchId])
        }
    }

    func entries(batchId: Int64) throws -> [OrganizeJournalEntry] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT j.*, b.root_path FROM organize_journal j
                JOIN organize_batches b ON b.id = j.batch_id
                WHERE j.batch_id = ? AND b.undone_at IS NULL ORDER BY j.id
                """, arguments: [batchId]).map {
                    OrganizeJournalEntry(id: $0["id"], batchId: $0["batch_id"], path: $0["link_path"],
                        root: $0["root_path"], fileIdentifier: $0["file_identifier"], undoState: $0["undo_state"], recoveryPath: $0["undo_recovery_path"])
                }
        }
    }

    func claimUndo(entryId: Int64) throws -> Bool {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE organize_journal SET undo_state = 'removing'
                WHERE id = ? AND undo_state IN ('pending', 'failed')
                  AND batch_id IN (SELECT id FROM organize_batches WHERE undone_at IS NULL)
                """, arguments: [entryId])
            return db.changesCount == 1
        }
    }

    func recordUndo(entryId: Int64, state: String, recoveryPath: String? = nil) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE organize_journal SET undo_state = ?, undo_recovery_path = ? WHERE id = ? AND undo_state = 'removing'",
                           arguments: [state, recoveryPath, entryId])
            guard db.changesCount == 1 else { throw AppError.databaseError("撤銷紀錄已不存在或狀態改變，已停止檔案操作") }
        }
    }

    func markUndone(_ batchId: Int64) throws {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE organize_batches SET undone_at = ? WHERE id = ?
                    AND NOT EXISTS (SELECT 1 FROM organize_journal WHERE batch_id = organize_batches.id
                                    AND undo_state IN ('pending', 'failed', 'removing'))
                """,
                           arguments: [Date(), batchId])
        }
    }

    /// 撤銷清單。新的在前。
    func batches(limit: Int = 20) throws -> [OrganizeBatch] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, created_at, scope, root_path, link_count, undone_at
                  FROM organize_batches ORDER BY id DESC LIMIT ?
                """, arguments: [limit])
                .map { row in
                    let id: Int64 = row["id"]
                    let recoveryPaths = try String.fetchAll(db, sql: "SELECT undo_recovery_path FROM organize_journal WHERE batch_id = ? AND undo_recovery_path IS NOT NULL ORDER BY id", arguments: [id])
                    return OrganizeBatch(id: id,
                                  createdAt: row["created_at"],
                                  scope: row["scope"] ?? "",
                                  rootPath: row["root_path"] ?? "",
                                  linkCount: row["link_count"] ?? 0,
                                  undoneAt: row["undone_at"], recoveryPaths: recoveryPaths)
                }
        }
    }
}
