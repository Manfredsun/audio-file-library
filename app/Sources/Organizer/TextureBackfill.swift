import Foundation
import GRDB

/// 用既有的路徑把材質補上。
///
/// **不碰音檔。** 材質是從 `relative_path` 與 `filename` 讀出來的，
/// 那兩個欄位早就在資料庫裡了——所以四萬多筆回填只是一次掃描，
/// 不需要重新分析，也不會把使用者的機器吃掉。
enum TextureBackfill {

    struct Result: Equatable {
        var errorMessage: String?
        var scanned = 0
        var filled = 0
        /// 人工設定過的不覆寫（CLAUDE.md §57 第三條）。
        var skippedManual = 0

        var summary: String {
            var parts = ["讀出 \(filled) 個材質"]
            if skippedManual > 0 { parts.append("\(skippedManual) 個人工設定的沒動") }
            return (errorMessage.map { "回填未完成：" + $0 + "。" } ?? "") + parts.joined(separator: "，") + "（共掃描 \(scanned) 筆）"
        }
    }

    /// `shouldContinue` 回 false 就停下來，已寫入的保留。
    @discardableResult
    static func run(database: AppDatabase,
                    vocabulary: TextureVocabulary,
                    shouldContinue: () -> Bool = { true },
                    onProgress: (Int, Int) -> Void = { _, _ in }) -> Result {
        var result = Result()
        let rows: [(Int64, String, String, String?, String?)]
        do {
            rows = try database.writer.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT s.id, s.relative_path, s.filename, s.texture_source, c.path AS category
                      FROM sounds s LEFT JOIN categories c ON c.id = s.category_id
                    """).map {
                        ($0["id"], $0["relative_path"] ?? "", $0["filename"] ?? "",
                         $0["texture_source"], $0["category"])
                    }
            }
        } catch {
            result.errorMessage = error.localizedDescription
            return result
        }

        let total = rows.count
        var pending: [(Int64, String)] = []

        for row in rows {
            guard shouldContinue() else { break }
            result.scanned += 1

            // 人工設定過的一律不動。自動流程不得覆寫人工欄位。
            if [MetadataSource.manual.rawValue, MetadataSource.acceptedAI.rawValue].contains(row.3 ?? "") {
                result.skippedManual += 1
                continue
            }
            if let match = TextureReader.read(relativePath: row.1,
                                              filename: row.2,
                                              vocabulary: vocabulary,
                                              category: row.4) {
                pending.append((row.0, match.texture))
            }
            if pending.count >= 500 {
                do {
                    let changed = try write(pending, to: database)
                    result.filled += changed
                    result.skippedManual += pending.count - changed
                } catch {
                    result.errorMessage = error.localizedDescription
                    onProgress(result.scanned, total)
                    return result
                }
                pending.removeAll(keepingCapacity: true)
                onProgress(result.scanned, total)
            }
        }
        do {
            let changed = try write(pending, to: database)
            result.filled += changed
            result.skippedManual += pending.count - changed
        } catch { result.errorMessage = error.localizedDescription }
        onProgress(result.scanned, total)
        return result
    }

    private static func write(_ pending: [(Int64, String)], to database: AppDatabase) throws -> Int {
        guard pending.isEmpty == false else { return 0 }
        return try database.writer.write { db in
            var changed = 0
            for (id, texture) in pending {
                try db.execute(sql: """
                    UPDATE sounds SET texture = ?, texture_source = ? WHERE id = ? AND (texture_source IS NULL OR texture_source NOT IN ('manual', 'accepted_ai'))
                    """, arguments: [texture, MetadataSource.imported.rawValue, id])
                changed += db.changesCount
            }
            return changed
        }
    }
}
