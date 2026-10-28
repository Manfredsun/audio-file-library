import Foundation
import GRDB

/// 虛擬資料夾的讀寫。
///
/// **這個型別永遠不會刪除、移動或改名任何檔案。** 它只動 `collections` 與
/// `collection_sounds` 兩張表。從分頁移除一個音效，`sounds` 一列都不會少，
/// 磁碟上一個位元組都不會變。這是整個功能最容易被誤解的地方，所以寫在最上面。
struct CollectionStore {
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - 分頁本身

    func all() throws -> [Collection] {
        try database.writer.read { db in
            try Collection
                .order(Collection.Columns.position.asc, Collection.Columns.id.asc)
                .fetchAll(db)
        }
    }

    /// 新分頁排在最後。
    @discardableResult
    func create(name: String) throws -> Collection {
        try database.writer.write { db in
            let next = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM collections") ?? 0
            var collection = Collection(name: name, position: next)
            try collection.insert(db)
            return collection
        }
    }

    func rename(id: Int64, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空字串的分頁在分頁列上會變成一個看不見的缺口，找不回來也點不到。
        guard trimmed.isEmpty == false else { return }
        try database.writer.write { db in
            try db.execute(sql: "UPDATE collections SET name = ?, updated_at = ? WHERE id = ?",
                           arguments: [trimmed, Date(), id])
        }
    }

    /// 刪除分頁。**音效與檔案完全不受影響**——只有那份名單消失。
    func delete(id: Int64) throws {
        try database.writer.write { db in
            _ = try Collection.deleteOne(db, key: id)
        }
    }

    /// 依照給定的順序重新指派 position。分頁列拖曳之後呼叫。
    func reorder(ids: [Int64]) throws {
        try database.writer.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE collections SET position = ? WHERE id = ?",
                               arguments: [index, id])
            }
        }
    }

    func count(collectionId: Int64) throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db,
                             sql: "SELECT COUNT(*) FROM collection_sounds WHERE collection_id = ?",
                             arguments: [collectionId]) ?? 0
        }
    }

    // MARK: - 成員

    /// 加入分頁，排在最後。
    ///
    /// 已經在裡面的音效**維持原本的位置不動**——拖第二次不該把它甩到最後面，
    /// 那會毀掉使用者手動排好的順序。回傳值代表這次有沒有真的加進去。
    @discardableResult
    func add(soundIds: [Int64], to collectionId: Int64) throws -> Int {
        try database.writer.write { db in
            var next = try Int.fetchOne(db, sql: """
                SELECT COALESCE(MAX(sort_order), -1) + 1 FROM collection_sounds WHERE collection_id = ?
                """, arguments: [collectionId]) ?? 0
            var added = 0
            for soundId in soundIds {
                let exists = try Bool.fetchOne(db, sql: """
                    SELECT EXISTS(SELECT 1 FROM collection_sounds
                                   WHERE collection_id = ? AND sound_id = ?)
                    """, arguments: [collectionId, soundId]) ?? false
                if exists { continue }
                try CollectionSound(collectionId: collectionId,
                                    soundId: soundId,
                                    sortOrder: next).insert(db)
                next += 1
                added += 1
            }
            if added > 0 {
                try db.execute(sql: "UPDATE collections SET updated_at = ? WHERE id = ?",
                               arguments: [Date(), collectionId])
            }
            return added
        }
    }

    /// 從分頁移除。**不是刪除檔案。**
    ///
    /// 移除之後不重新編號：剩下的音效維持原本的相對順序，
    /// 空出來的號碼留著沒關係，排序只看大小不看連續。
    func remove(soundIds: [Int64], from collectionId: Int64) throws {
        guard soundIds.isEmpty == false else { return }
        try database.writer.write { db in
            let placeholders = databaseQuestionMarks(count: soundIds.count)
            try db.execute(sql: """
                DELETE FROM collection_sounds
                 WHERE collection_id = ? AND sound_id IN (\(placeholders))
                """,
                arguments: StatementArguments([collectionId] + soundIds.map { $0 as DatabaseValueConvertible }))
            try db.execute(sql: "UPDATE collections SET updated_at = ? WHERE id = ?",
                           arguments: [Date(), collectionId])
        }
    }

    func contains(soundId: Int64, in collectionId: Int64) throws -> Bool {
        try database.writer.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM collection_sounds
                               WHERE collection_id = ? AND sound_id = ?)
                """, arguments: [collectionId, soundId]) ?? false
        }
    }

    /// 分頁內的手動排序。傳入的是完整的 sound id 順序。
    func reorderSounds(_ soundIds: [Int64], in collectionId: Int64) throws {
        try database.writer.write { db in
            for (index, soundId) in soundIds.enumerated() {
                try db.execute(sql: """
                    UPDATE collection_sounds SET sort_order = ?
                     WHERE collection_id = ? AND sound_id = ?
                    """, arguments: [index, collectionId, soundId])
            }
            try db.execute(sql: "UPDATE collections SET updated_at = ? WHERE id = ?",
                           arguments: [Date(), collectionId])
        }
    }

    /// 把 `moving` 搬到 `target` 前面，回傳新的完整順序。
    ///
    /// 純函數，跟資料庫無關，所以邊界可以被完整測試。
    /// 用「搬到某一筆前面」而不是「從第幾列搬到第幾列」，是因為索引會被翻頁弄亂：
    /// 當前頁的第 3 列在整個分頁裡可能是第 63 筆。
    ///
    /// `target` 不在名單裡時回 nil——寧可什麼都不做，也不要猜一個位置塞進去。
    static func reordering(all: [Int64], moving: [Int64], before target: Int64) -> [Int64]? {
        let moving = moving.filter { $0 != target }
        guard moving.isEmpty == false else { return nil }
        var result = all
        result.removeAll { moving.contains($0) }
        guard let insertion = result.firstIndex(of: target) else { return nil }
        // moving 的相對順序保持不變——一次拖多筆時，它們之間的順序也是使用者排的。
        result.insert(contentsOf: moving, at: insertion)
        return result
    }

    /// 分頁裡的 sound id，照使用者排的順序。
    func soundIds(in collectionId: Int64) throws -> [Int64] {
        try database.writer.read { db in
            try Int64.fetchAll(db, sql: """
                SELECT sound_id FROM collection_sounds
                 WHERE collection_id = ? ORDER BY sort_order, sound_id
                """, arguments: [collectionId])
        }
    }
}

// MARK: - 依分類自動建立分頁

extension CollectionStore {

    /// 一個候選分頁：分類路徑與它底下的音效數。
    struct AutoFillCandidate: Equatable, Identifiable {
        var path: String
        var count: Int
        var id: String { path }
    }

    struct AutoFillResult: Equatable {
        var collectionsCreated: Int
        var soundsAdded: Int
    }

    /// 預覽：會建立哪些分頁、各幾筆。
    ///
    /// **只看已經接受的分類**（`sounds.category_id`），不看建議。
    /// 分頁是捷徑不是 metadata，但從沒人看過的建議生出一堆分頁，
    /// 等於繞過使用者的決定——那些分類還沒被你同意過。
    func autoFillCandidates(minCount: Int) throws -> [AutoFillCandidate] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.path AS path, COUNT(*) AS n
                  FROM sounds s JOIN categories c ON c.id = s.category_id
                 GROUP BY c.path
                HAVING n >= ?
                 ORDER BY n DESC, c.path
                """, arguments: [minCount])
                .map { AutoFillCandidate(path: $0["path"] ?? "", count: $0["n"] ?? 0) }
        }
    }

    /// 依分類建立分頁並填入。
    ///
    /// 填進去之後就是使用者的了——這是**快照不是動態查詢**。
    /// 之後拖進拖出、重新排序、改名都不會被程式回頭「更新」。
    /// 這跟手動分頁是同一個原則：手動放的東西程式不准自作聰明去動（D-021）。
    ///
    /// 同名的分頁已經存在時沿用它，只補上還沒有的音效——
    /// 重跑一次不該產生「Drums/Kick 2」這種東西。
    @discardableResult
    func autoFillByCategory(minCount: Int) throws -> AutoFillResult {
        let candidates = try autoFillCandidates(minCount: minCount)
        guard candidates.isEmpty == false else { return AutoFillResult(collectionsCreated: 0, soundsAdded: 0) }

        return try database.writer.write { db in
            var created = 0
            var added = 0
            for candidate in candidates {
                let collectionId: Int64
                if let existing = try Int64.fetchOne(db,
                        sql: "SELECT id FROM collections WHERE name = ? LIMIT 1",
                        arguments: [candidate.path]) {
                    collectionId = existing
                } else {
                    let position = try Int.fetchOne(db,
                        sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM collections") ?? 0
                    try db.execute(sql: "INSERT INTO collections (name, created_at, position) VALUES (?, ?, ?)",
                                   arguments: [candidate.path, Date(), position])
                    collectionId = db.lastInsertedRowID
                    created += 1
                }

                let offset = try Int.fetchOne(db, sql: """
                    SELECT COALESCE(MAX(sort_order), -1) + 1 FROM collection_sounds WHERE collection_id = ?
                    """, arguments: [collectionId]) ?? 0

                try db.execute(sql: """
                    INSERT INTO collection_sounds (collection_id, sound_id, sort_order, added_at)
                    SELECT ?, s.id,
                           ? + ROW_NUMBER() OVER (ORDER BY s.relative_path, s.id) - 1,
                           ?
                      FROM sounds s
                      JOIN categories c ON c.id = s.category_id
                     WHERE c.path = ?
                    ON CONFLICT (collection_id, sound_id) DO NOTHING
                    """, arguments: [collectionId, offset, Date(), candidate.path])
                added += db.changesCount
            }
            AppLog.app.info("自動建立分頁 新建=\(created, privacy: .public) 加入=\(added, privacy: .public)")
            return AutoFillResult(collectionsCreated: created, soundsAdded: added)
        }
    }
}
