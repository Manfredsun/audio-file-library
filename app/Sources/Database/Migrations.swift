import Foundation
import GRDB

/// 資料庫遷移。永不做破壞性 schema 變更（AGENTS.md §27）。
enum AppMigrations {

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        registerV1(&migrator)
        registerV2(&migrator)
        registerV3(&migrator)
        registerV4(&migrator)
        registerV5(&migrator)
        registerV6(&migrator)
        registerV7(&migrator)
        registerV8(&migrator)
        registerV9(&migrator)
        registerV10(&migrator)
        registerV11(&migrator)
        registerV12(&migrator)
        registerV13(&migrator)
        registerV14(&migrator)
        registerV15(&migrator)
        return migrator
    }

    /// Writers from an older scan must not commit after a newer scan takes ownership.
    private static func registerV15(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v15_library_scan_ownership") { db in
            try db.alter(table: "libraries") { t in
                t.add(column: "active_scan_token", .text)
            }
        }
    }

    /// Per-scan identity avoids millisecond timestamp collisions during rapid rescans.
    private static func registerV14(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v14_scan_identity") { db in
            try db.alter(table: "sounds") { t in
                t.add(column: "last_scan_token", .text)
            }
        }
    }

    /// Forward-only: preserve old journals; never infer a new file identity for them.
    private static func registerV13(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v13_safe_organize_undo") { db in
            try db.alter(table: "organize_journal") { t in
                t.add(column: "undo_state", .text).notNull().defaults(to: "pending")
                t.add(column: "undo_recovery_path", .text)
            }
        }
    }

    private static func registerV1(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial_schema") { db in

            try db.create(table: "libraries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("root_path", .text).notNull()
                t.column("bookmark_data", .blob)
                t.column("created_at", .datetime).notNull()
                t.column("last_scanned_at", .datetime)
                t.column("availability_status", .text).notNull().defaults(to: "available")
            }

            try db.create(table: "categories") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("parent_id", .integer).references("categories", onDelete: .cascade)
                t.column("path", .text).notNull()
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "idx_categories_path", on: "categories", columns: ["path"], unique: true)

            try db.create(table: "tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("canonical_name", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_tags_canonical", on: "tags", columns: ["canonical_name"], unique: true)

            try db.create(table: "sounds") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("library_id", .integer).notNull()
                    .references("libraries", onDelete: .cascade)

                t.column("file_path", .text).notNull()
                t.column("relative_path", .text).notNull()
                t.column("filename", .text).notNull()
                t.column("file_extension", .text).notNull()
                t.column("file_size", .integer).notNull().defaults(to: 0)
                t.column("file_identifier", .text)

                t.column("duration", .double)
                t.column("sample_rate", .integer)
                t.column("bit_depth", .integer)
                t.column("channel_count", .integer)

                t.column("file_created_at", .datetime)
                t.column("file_modified_at", .datetime)

                t.column("display_name", .text)
                t.column("display_name_source", .text)
                t.column("category_id", .integer).references("categories", onDelete: .setNull)
                t.column("category_source", .text)
                t.column("subcategory", .text)
                t.column("subcategory_source", .text)

                t.column("favorite", .boolean).notNull().defaults(to: false)
                t.column("rating", .integer).notNull().defaults(to: 0)
                t.column("notes", .text)

                t.column("status", .text).notNull().defaults(to: "ok")
                t.column("analysis_status", .text).notNull().defaults(to: "none")
                t.column("needs_review", .boolean).notNull().defaults(to: false)

                t.column("date_indexed", .datetime).notNull()
                t.column("last_played_at", .datetime)
                t.column("play_count", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "idx_sounds_library", on: "sounds", columns: ["library_id"])
            try db.create(index: "idx_sounds_identifier", on: "sounds", columns: ["file_identifier"])
            try db.create(index: "idx_sounds_needs_review", on: "sounds", columns: ["needs_review"])
            try db.create(index: "idx_sounds_path", on: "sounds", columns: ["library_id", "file_path"], unique: true)

            try db.create(table: "sound_tags") { t in
                t.column("sound_id", .integer).notNull()
                    .references("sounds", onDelete: .cascade)
                t.column("tag_id", .integer).notNull()
                    .references("tags", onDelete: .cascade)
                t.column("source", .text).notNull()
                t.column("confidence", .double)
                t.column("accepted", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
                t.primaryKey(["sound_id", "tag_id", "source"])
            }
            try db.create(index: "idx_sound_tags_tag", on: "sound_tags", columns: ["tag_id"])

            try db.create(table: "organizer_analysis") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sound_id", .integer).notNull()
                    .references("sounds", onDelete: .cascade)
                t.column("engine", .text).notNull()
                t.column("model", .text)
                t.column("model_version", .text)
                t.column("status", .text).notNull()
                t.column("confidence", .double).notNull()
                t.column("needs_review", .boolean).notNull()
                t.column("description", .text)
                t.column("started_at", .datetime).notNull()
                t.column("completed_at", .datetime)
                t.column("error_message", .text)
            }
            try db.create(index: "idx_analysis_sound", on: "organizer_analysis", columns: ["sound_id"])

            try db.create(table: "organizer_suggestions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("analysis_id", .integer).notNull()
                    .references("organizer_analysis", onDelete: .cascade)
                t.column("field", .text).notNull()
                t.column("value", .text).notNull()
                t.column("confidence", .double)
                t.column("status", .text).notNull().defaults(to: "suggested")
            }
            try db.create(index: "idx_suggestions_analysis", on: "organizer_suggestions", columns: ["analysis_id"])

            try db.create(table: "waveform_cache") { t in
                t.column("sound_id", .integer).notNull().primaryKey()
                    .references("sounds", onDelete: .cascade)
                t.column("waveform_data", .blob).notNull()
                t.column("resolution", .integer).notNull()
                t.column("generated_at", .datetime).notNull()
            }

            try db.create(table: "collections") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }

            try db.create(table: "collection_sounds") { t in
                t.column("collection_id", .integer).notNull()
                    .references("collections", onDelete: .cascade)
                t.column("sound_id", .integer).notNull()
                    .references("sounds", onDelete: .cascade)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.primaryKey(["collection_id", "sound_id"])
            }
        }
    }

    /// v2：掃描需要知道「這次掃描有沒有再看到這個檔案」。
    /// 沒看到的標成 missing，而不是刪除——metadata 是使用者的，不是掃描器的。
    private static func registerV2(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2_last_seen_at") { db in
            try db.alter(table: "sounds") { t in
                t.add(column: "last_seen_at", .datetime)
            }
            try db.create(index: "idx_sounds_last_seen", on: "sounds", columns: ["library_id", "last_seen_at"])
        }
    }

    /// v3：移除 M0 時期塞入的示範資料。
    ///
    /// 那批假資料的資料夾名稱（Doors、Footsteps、Props…）跟真實的 Foley 庫
    /// 長得一模一樣，使用者無法分辨它不是自己的檔案。
    /// 假資料不該偽裝成真資料——整批刪掉，寧可讓 App 一開始是空的。
    ///
    /// 注意：migration 期間外鍵約束是關閉的，`ON DELETE CASCADE` 不會觸發。
    /// 必須由子表往父表逐層刪除，否則會留下孤兒列，
    /// 在 migration 結束的完整性檢查時失敗。
    private static func registerV3(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3_remove_mock_seed") { db in
            let mockLibraries = "SELECT id FROM libraries WHERE name = 'Mock Library' AND root_path = '/Volumes/Mock/Foley'"
            let mockSounds = "SELECT id FROM sounds WHERE library_id IN (\(mockLibraries))"

            try db.execute(sql: """
                DELETE FROM organizer_suggestions
                 WHERE analysis_id IN (
                       SELECT id FROM organizer_analysis WHERE sound_id IN (\(mockSounds))
                 )
                """)
            try db.execute(sql: "DELETE FROM organizer_analysis WHERE sound_id IN (\(mockSounds))")
            try db.execute(sql: "DELETE FROM sound_tags WHERE sound_id IN (\(mockSounds))")
            try db.execute(sql: "DELETE FROM waveform_cache WHERE sound_id IN (\(mockSounds))")
            try db.execute(sql: "DELETE FROM collection_sounds WHERE sound_id IN (\(mockSounds))")
            try db.execute(sql: "DELETE FROM sounds WHERE library_id IN (\(mockLibraries))")
            try db.execute(sql: "DELETE FROM libraries WHERE id IN (\(mockLibraries))")
        }
    }

    /// v4：把所屬資料夾獨立成欄位。
    ///
    /// 側欄要能照資料夾瀏覽，就必須能用一次 GROUP BY 拿到每個資料夾的數量。
    /// 從 relative_path 現算的話，每次開側欄都要把整個音色庫的路徑拉出來字串處理——
    /// 十萬個檔案時那是不可接受的。
    private static func registerV4(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v4_folder_path") { db in
            try db.alter(table: "sounds") { t in
                t.add(column: "folder_path", .text).notNull().defaults(to: "")
            }
            try db.create(index: "idx_sounds_folder", on: "sounds", columns: ["library_id", "folder_path"])

            // 回填既有資料。SQLite 沒有 dirname，用 Swift 算比堆疊字串函式清楚得多。
            let rows = try Row.fetchAll(db, sql: "SELECT id, relative_path FROM sounds")
            for row in rows {
                let id: Int64 = row["id"]
                let relativePath: String = row["relative_path"] ?? ""
                try db.execute(sql: "UPDATE sounds SET folder_path = ? WHERE id = ?",
                               arguments: [FolderPath.folder(of: relativePath), id])
            }
        }
    }

    /// v5：音樂風格。
    ///
    /// 風格是獨立欄位而不是分類路徑的一層（D-014）。塞進 category 會逼人二選一：
    /// 要嘛好找「boom bap 的 kick」，要嘛好找「所有 boom bap」，不可能兩者都好。
    ///
    /// 沿用既有的 provenance 模型：人工設定的風格永遠優先於任何自動推得的值。
    /// 欄位可為 NULL，而且 **NULL 是正常狀態**——路徑沒有風格線索時就該是空的，
    /// 不填佔位字串。
    /// v6：虛擬資料夾（分頁）。
    ///
    /// `collections` 與 `collection_sounds` 在 v1 就建好了，當時為 M12 預留。
    /// 這裡補上分頁的左右順序與加入時間。
    ///
    /// 分頁內的排序沿用既有的 `sort_order`——那是使用者手動排的，
    /// 程式永遠不准自作聰明去重排它。複合主鍵已經保證同一個音檔在同一個分頁裡
    /// 只會有一列，拖第二次不會變兩筆。
    /// v7：節拍、調性、loop 判定。
    ///
    /// BPM 有兩個來源：檔名字面與訊號量測。兩者一致時信心高，不一致時標記待複查——
    /// 這跟分類層「兩條獨立證據」是同一個原則。
    ///
    /// NULL 是正常狀態。一個沒有節奏的撞擊聲本來就沒有 BPM，
    /// 硬填一個數字比空著更糟。
    /// v12：已確定分類的音效不再待複查（D-043）。
    ///
    /// 在這之前，Inspector 裡按「接受」分類建議或人工設定分類，都不會清掉 needs_review，
    /// 列表左邊的黃點因此留著（2026-09-23 實測 27 筆）。新的寫入路徑已經會清；
    /// 這裡把之前留下的補齊。只動 needs_review 一個旗標，分類與來源都不碰。
    private static func registerV12(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v12_clear_review_for_confirmed") { db in
            try db.execute(sql: """
                UPDATE sounds SET needs_review = 0
                 WHERE needs_review = 1
                   AND category_id IS NOT NULL
                   AND category_source IN ('manual', 'accepted_ai')
                """)
        }
    }

    /// v11：依分類瀏覽（M41）。只加索引，不改任何資料。
    ///
    /// 側欄的分類區要能用「已確定的分類」與「最新一次分析的待處理建議」兩條路找音效。
    /// 兩條都是從小集合往回查 sounds：
    ///   已確定  categories.path → sounds.category_id
    ///   建議    organizer_suggestions(field, status, value) → analysis → sound
    /// 沒有這兩個索引的話，每翻一頁都要把四萬筆 sounds 逐列跑一次 EXISTS（實測 0.18 秒 × 2）。
    private static func registerV11(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v11_category_browse") { db in
            try db.create(index: "idx_sounds_category", on: "sounds", columns: ["category_id"])
            try db.create(index: "idx_suggestions_field_status_value",
                          on: "organizer_suggestions", columns: ["field", "status", "value"])
        }
    }

    /// v10：材質（M36）。
    ///
    /// 跟 `style` 完全平行的欄位：受控白名單、從路徑字面讀、讀不到就留空。
    /// 索引一開始就建好，因為側欄依材質篩選是這個欄位存在的主要理由（D-026）。
    private static func registerV10(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v10_texture") { db in
            try db.alter(table: "sounds") { t in
                t.add(column: "texture", .text)
                t.add(column: "texture_source", .text)
            }
            try db.create(index: "idx_sounds_texture", on: "sounds", columns: ["texture"])
        }
    }

    /// v9：凍結整理後的編號與名字（M32c）。
    ///
    /// 編號若每次重算，在排序中間插進一個新檔案，它後面每一個檔案的號碼
    /// 都會位移，整棵樹跟著改名——第二次執行會製造出一整批假的「變更」，
    /// 而且樹裡會多出一批名字不同、指向同一份資料的連結。
    ///
    /// `organized_folder` 一起存：分類改了之後，舊資料夾裡的號碼就不適用了，
    /// 那時候要在新資料夾重新拿一個號，不能沿用。
    ///
    /// 原始的 `filename` 與 `relative_path` **永遠不覆寫**（dev-plan §6）——
    /// 哪天懷疑某個 descriptor 抽錯了，要有東西可以比對。
    private static func registerV9(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v9_organized_names") { db in
            try db.alter(table: "sounds") { t in
                t.add(column: "organized_number", .integer)
                t.add(column: "organized_folder", .text)
                t.add(column: "organized_name", .text)
                t.add(column: "organized_at", .datetime)
            }
        }
    }

    /// v8：硬連結整理的紀錄（M32）。
    ///
    /// 撤銷能乾淨，靠的就是這張表：每建一個連結就記一筆，
    /// 撤銷時只刪這個 batch 建立過的那些路徑。**沒有紀錄就不敢刪任何東西**——
    /// 憑「看起來像我們建的」去刪使用者磁碟上的檔案是不可接受的。
    private static func registerV8(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v8_organize_journal") { db in
            try db.create(table: "organize_batches") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("created_at", .datetime).notNull()
                /// 這一批是從哪個檢視跑的，例如「分頁：Kick」。撤銷時要讓人認得出來。
                t.column("scope", .text).notNull()
                t.column("root_path", .text).notNull()
                t.column("link_count", .integer).notNull().defaults(to: 0)
                /// 撤銷過的批次留著不刪，歷史要看得見。
                t.column("undone_at", .datetime)
            }
            try db.create(table: "organize_journal") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("batch_id", .integer).notNull()
                    .references("organize_batches", onDelete: .cascade)
                t.column("sound_id", .integer).notNull()
                    .references("sounds", onDelete: .cascade)
                /// device id + inode。改名搬移都不變，是對得回原檔的唯一依據。
                t.column("file_identifier", .text)
                /// 實際建立的連結路徑。撤銷時刪的就是它，一個字都不能猜。
                t.column("link_path", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_organize_journal_batch",
                          on: "organize_journal", columns: ["batch_id"])
            // 大小寫不敏感的碰撞要查得快：HFS+ 上 Kick 01.wav 與 kick 01.wav 是同一個檔案。
            try db.create(index: "idx_organize_journal_path",
                          on: "organize_journal", columns: ["link_path"])
        }
    }

    private static func registerV7(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v7_tempo") { db in
            try db.alter(table: "sounds") { t in
                t.add(column: "bpm", .double)
                t.add(column: "bpm_source", .text)
                t.add(column: "musical_key", .text)
                t.add(column: "key_source", .text)
                t.add(column: "is_loop", .boolean)
            }
            // 挑 loop 時第一個要看的就是 BPM，索引一開始就建好。
            try db.create(index: "idx_sounds_bpm", on: "sounds", columns: ["bpm"])
        }
    }

    private static func registerV6(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v6_collections") { db in
            try db.alter(table: "collections") { t in
                t.add(column: "position", .integer).notNull().defaults(to: 0)
                t.add(column: "updated_at", .datetime)
            }
            try db.alter(table: "collection_sounds") { t in
                t.add(column: "added_at", .datetime)
            }
            try db.create(index: "idx_collection_sounds_order",
                          on: "collection_sounds",
                          columns: ["collection_id", "sort_order"])
        }
    }

    private static func registerV5(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v5_style") { db in
            try db.alter(table: "sounds") { t in
                t.add(column: "style", .text)
                t.add(column: "style_source", .text)
            }
            // 依風格篩選是這個欄位存在的主要理由，索引一開始就建好。
            try db.create(index: "idx_sounds_style", on: "sounds", columns: ["style"])
        }
    }
}

/// 相對路徑的資料夾部分。根目錄的檔案是空字串，不是 nil——
/// 空字串代表「在根目錄」，nil 代表「還沒算過」，兩者不同。
enum FolderPath {
    static func folder(of relativePath: String) -> String {
        guard let index = relativePath.lastIndex(of: "/") else { return "" }
        return String(relativePath[relativePath.startIndex..<index])
    }
}
