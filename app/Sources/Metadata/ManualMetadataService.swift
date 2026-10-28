import Foundation
import GRDB

enum MetadataWriteError: Error, Equatable, LocalizedError {
    case soundNotFound(Int64)
    case suggestionNotFound(Int64)
    case categoryNotFound(String)
    /// 自動流程試圖覆寫人工設定的值。這是被設計成不可能發生的事。
    case manualValueProtected(field: String)

    var errorDescription: String? {
        switch self {
        case .soundNotFound(let id):        return "找不到音效 id=\(id)"
        case .suggestionNotFound(let id):   return "找不到建議 id=\(id)"
        case .categoryNotFound(let path):   return "找不到分類：\(path)"
        case .manualValueProtected(let f):  return "\(f) 是人工設定的值，不得由自動流程覆寫"
        }
    }
}

/// 所有對 `sounds` metadata 欄位的寫入都必須經過這裡。
///
/// 人工優先權在這一層強制執行，而不是靠 UI 文字提醒（AGENTS.md §8）。
struct ManualMetadataService {
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - 人工編輯（永遠允許）

    func setDisplayName(_ value: String?, soundId: Int64, source: MetadataSource = .manual, force: Bool = false) throws {
        try write(soundId: soundId, field: "display_name", sourceColumn: "display_name_source", source: source, force: force) { db in
            try db.execute(sql: "UPDATE sounds SET display_name = ?, display_name_source = ? WHERE id = ?",
                           arguments: [value, source.rawValue, soundId])
        }
    }

    func setCategory(path: String?, soundId: Int64, source: MetadataSource = .manual, force: Bool = false) throws {
        try write(soundId: soundId, field: "category", sourceColumn: "category_source", source: source, force: force) { db in
            var categoryId: Int64?
            if let path {
                guard let category = try Category.filter(Category.Columns.path == path).fetchOne(db),
                      let id = category.id else {
                    throw MetadataWriteError.categoryNotFound(path)
                }
                categoryId = id
            }
            // 人親手設定分類（包括明確設成未分類），就是審核過了（D-043）。
            try db.execute(sql: "UPDATE sounds SET category_id = ?, category_source = ?, needs_review = 0 WHERE id = ?",
                           arguments: [categoryId, source.rawValue, soundId])
        }
    }

    func setSubcategory(_ value: String?, soundId: Int64, source: MetadataSource = .manual, force: Bool = false) throws {
        try write(soundId: soundId, field: "subcategory", sourceColumn: "subcategory_source", source: source, force: force) { db in
            try db.execute(sql: "UPDATE sounds SET subcategory = ?, subcategory_source = ? WHERE id = ?",
                           arguments: [value, source.rawValue, soundId])
        }
    }

    func setStyle(_ value: String?, soundId: Int64) throws {
        try setLiteral(value, field: "style", soundId: soundId)
    }

    func setTexture(_ value: String?, soundId: Int64) throws {
        try setLiteral(value, field: "texture", soundId: soundId)
    }

    private func setLiteral(_ value: String?, field: String, soundId: Int64) throws {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed?.isEmpty == false ? trimmed : nil
        try write(soundId: soundId, field: field, sourceColumn: field + "_source", source: .manual, force: false) { db in
            try db.execute(sql: "UPDATE sounds SET \(field) = ?, \(field)_source = ? WHERE id = ?",
                           arguments: [value, MetadataSource.manual.rawValue, soundId])
        }
    }

    func setFavorite(_ value: Bool, soundId: Int64) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sounds SET favorite = ? WHERE id = ?", arguments: [value, soundId])
        }
    }

    func setRating(_ value: Int, soundId: Int64) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sounds SET rating = ? WHERE id = ?", arguments: [max(0, min(5, value)), soundId])
        }
    }

    func setNotes(_ value: String?, soundId: Int64) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sounds SET notes = ? WHERE id = ?", arguments: [value, soundId])
        }
    }

    func setNeedsReview(_ value: Bool, soundId: Int64) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sounds SET needs_review = ? WHERE id = ?", arguments: [value, soundId])
        }
    }

    // MARK: - 標籤

    /// 加標籤。同一個 canonical 名稱全庫只會有一筆 tag 紀錄，
    /// 同一個音效重複加同一個標籤也不會產生第二列。
    @discardableResult
    func addTag(_ raw: String, soundId: Int64) throws -> Tag? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let canonical = Tag.canonicalize(trimmed)

        return try database.writer.write { db in
            let tag: Tag
            if let existing = try Tag.filter(Tag.Columns.canonicalName == canonical).fetchOne(db) {
                tag = existing
            } else {
                var created = Tag(name: trimmed, canonicalName: canonical)
                try created.insert(db)
                tag = created
            }
            guard let tagId = tag.id else { return nil }

            let already = try SoundTag
                .filter(Column("sound_id") == soundId)
                .filter(Column("tag_id") == tagId)
                .filter(Column("source") == MetadataSource.manual.rawValue)
                .fetchCount(db)
            if already == 0 {
                let link = SoundTag(soundId: soundId,
                                    tagId: tagId,
                                    source: .manual,
                                    confidence: nil,
                                    accepted: true)
                try link.insert(db)
            }
            return tag
        }
    }

    /// 移除標籤。只解除這個音效與標籤的關聯，不刪除標籤本身——
    /// 別的音效可能還在用它。
    func removeTag(tagId: Int64, soundId: Int64) throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM sound_tags WHERE sound_id = ? AND tag_id = ?",
                           arguments: [soundId, tagId])
        }
    }

    // MARK: - 接受 / 拒絕 AI 建議

    /// 接受一則建議。寫入的 provenance 是 `accepted_ai`，不是 `manual`。
    /// 若目標欄位目前是人工值，預設拒絕覆寫；`force` 代表使用者明確選擇覆寫自己的舊值。
    func accept(suggestionId: Int64, force: Bool = false) throws {
        try database.writer.write { db in
            guard let suggestion = try OrganizerSuggestion.fetchOne(db, key: suggestionId) else {
                throw MetadataWriteError.suggestionNotFound(suggestionId)
            }
            guard let analysis = try OrganizerAnalysis.fetchOne(db, key: suggestion.analysisId) else {
                throw MetadataWriteError.suggestionNotFound(suggestionId)
            }
            let soundId = analysis.soundId
            guard let sound = try Sound.fetchOne(db, key: soundId) else {
                throw MetadataWriteError.soundNotFound(soundId)
            }

            switch suggestion.field {
            case .displayName:
                try guardManual(sound.displayNameSource, field: "display_name", force: force)
                try db.execute(sql: "UPDATE sounds SET display_name = ?, display_name_source = ? WHERE id = ?",
                               arguments: [suggestion.value, MetadataSource.acceptedAI.rawValue, soundId])

            case .category:
                try guardManual(sound.categorySource, field: "category", force: force)
                guard let category = try Category.filter(Category.Columns.path == suggestion.value).fetchOne(db),
                      let categoryId = category.id else {
                    throw MetadataWriteError.categoryNotFound(suggestion.value)
                }
                // 分類是審核的主體：人接受了分類，這個音效就不再待複查（D-043）。
                try db.execute(sql: """
                    UPDATE sounds SET category_id = ?, category_source = ?, needs_review = 0 WHERE id = ?
                    """, arguments: [categoryId, MetadataSource.acceptedAI.rawValue, soundId])

            case .subcategory:
                try guardManual(sound.subcategorySource, field: "subcategory", force: force)
                try db.execute(sql: "UPDATE sounds SET subcategory = ?, subcategory_source = ? WHERE id = ?",
                               arguments: [suggestion.value, MetadataSource.acceptedAI.rawValue, soundId])

            case .style:
                try guardManual(sound.styleSource, field: "style", force: force)
                try db.execute(sql: "UPDATE sounds SET style = ?, style_source = ? WHERE id = ?",
                               arguments: [suggestion.value, MetadataSource.acceptedAI.rawValue, soundId])

            case .tag:
                let canonical = Tag.canonicalize(suggestion.value)
                let tagId: Int64
                if let existing = try Tag.filter(Tag.Columns.canonicalName == canonical).fetchOne(db), let id = existing.id {
                    tagId = id
                } else {
                    var tag = Tag(name: suggestion.value, canonicalName: canonical)
                    try tag.insert(db)
                    tagId = tag.id ?? 0
                }
                let link = SoundTag(soundId: soundId,
                                    tagId: tagId,
                                    source: .acceptedAI,
                                    confidence: suggestion.confidence,
                                    accepted: true)
                try link.insert(db)

            case .summary, .alternativeCategory:
                // 描述與替代分類不直接落到 sounds 欄位，接受它們只代表在 UI 上標記為已採用。
                break
            }

            try db.execute(sql: "UPDATE organizer_suggestions SET status = ? WHERE id = ?",
                           arguments: [OrganizerSuggestion.Status.accepted.rawValue, suggestionId])
        }
    }

    func reject(suggestionId: Int64) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE organizer_suggestions SET status = ? WHERE id = ?",
                           arguments: [OrganizerSuggestion.Status.rejected.rawValue, suggestionId])
            // 拒絕分類建議也是一個決定——人看過了，「不是這個」。跟審核列的 R 鍵一致（D-043）。
            try db.execute(sql: """
                UPDATE sounds SET needs_review = 0
                 WHERE id = (SELECT a.sound_id FROM organizer_suggestions g
                               JOIN organizer_analysis a ON a.id = g.analysis_id
                              WHERE g.id = ? AND g.field = 'category')
                """, arguments: [suggestionId])
        }
    }

    // MARK: - 內部

    private func guardManual(_ existing: MetadataSource?, field: String, force: Bool) throws {
        if existing == .manual && !force {
            throw MetadataWriteError.manualValueProtected(field: field)
        }
    }

    private func write(soundId: Int64,
                       field: String,
                       sourceColumn: String,
                       source: MetadataSource,
                       force: Bool,
                       _ body: @escaping (Database) throws -> Void) throws {
        try database.writer.write { db in
            guard let sound = try Sound.fetchOne(db, key: soundId) else {
                throw MetadataWriteError.soundNotFound(soundId)
            }
            if !source.isManual {
                let existing: MetadataSource?
                switch sourceColumn {
                case "display_name_source": existing = sound.displayNameSource
                case "category_source":     existing = sound.categorySource
                default:                    existing = sound.subcategorySource
                }
                try guardManual(existing, field: field, force: force)
            }
            try body(db)
        }
    }
}
