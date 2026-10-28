import Foundation
import GRDB

/// 只讀路徑的重算。**一個音檔都不開。**
///
/// 存在的理由很具體：使用者的 46,000 筆分析結果是在 M27b（中文規則）、
/// D-020（風格誤判修正）、D-022（層級計分）、M36（材質）之前跑的。
/// 那之後所有的改進，對他現有的資料都不存在——而重新分析四萬多個音檔
/// 會把他的機器吃掉，他還要用那台機器做音樂。
///
/// 但其中有一部分改進**只跟路徑有關**：
///
/// ```text
/// 只讀路徑（這裡）        風格、材質、字面 BPM、調性與 loop 線索
/// 必須讀音訊（批次分析）   分類建議、BPM 量測、聲學形狀
/// ```
///
/// `relative_path` 與 `filename` 早就在資料庫裡，所以這是一次掃描，不是四萬次解碼。
///
/// **這條路徑不得寫 Organizer 建議。** D-040 的事故證明，較弱的 path-only
/// 分類結果一旦走一般 mapper，就會把已經有音訊佐證的建議整組標成 superseded。
enum PathRereadService {

    struct Result: Equatable {
        var errorMessage: String?
        var scanned = 0
        var styleFilled = 0
        var textureFilled = 0
        var tempoFilled = 0
        var skippedManual = 0

        var summary: String {
            var parts = ["掃描 \(scanned) 筆"]
            if styleFilled > 0 { parts.append("風格 \(styleFilled)") }
            if textureFilled > 0 { parts.append("材質 \(textureFilled)") }
            if tempoFilled > 0 { parts.append("節拍／調性 \(tempoFilled)") }
            if skippedManual > 0 { parts.append("人工設定的 \(skippedManual) 筆沒動") }
            return (errorMessage.map { "重讀未完成：" + $0 + "。" } ?? "") + parts.joined(separator: "，")
        }
    }

    private struct Row1 {
        var id: Int64
        var relativePath: String
        var filename: String
        var category: String?
        var styleSource: String?
        var textureSource: String?
        var bpmSource: String?
    }

    @discardableResult
    static func run(database: AppDatabase,
                    taxonomy: Taxonomy,
                    vocabulary: TagVocabulary,
                    styles: StyleVocabulary,
                    textures: TextureVocabulary,
                    shouldContinue: () -> Bool = { true },
                    onProgress: (Int, Int) -> Void = { _, _ in }) -> Result {

        var result = Result()
        let rows: [Row1]
        do {
            rows = try database.writer.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT s.id, s.relative_path, s.filename, s.style_source,
                           s.texture_source, s.bpm_source, c.path AS category
                      FROM sounds s LEFT JOIN categories c ON c.id = s.category_id
                    """).map {
                        Row1(id: $0["id"],
                             relativePath: $0["relative_path"] ?? "",
                             filename: $0["filename"] ?? "",
                             category: $0["category"],
                             styleSource: $0["style_source"],
                             textureSource: $0["texture_source"],
                             bpmSource: $0["bpm_source"])
                    }
            }
        } catch {
            result.errorMessage = error.localizedDescription
            return result
        }

        let manual = MetadataSource.manual.rawValue
        let protected = [manual, MetadataSource.acceptedAI.rawValue]
        let total = rows.count

        for chunk in stride(from: 0, to: rows.count, by: 200).map({
            Array(rows[$0..<min($0 + 200, rows.count)])
        }) {
            guard shouldContinue() else { break }
            do {
                let committed = try database.writer.write { (db: Database) -> Result in
                    var committed = result
                for row in chunk {
                    committed.scanned += 1
                    guard let current = try Row.fetchOne(db, sql: "SELECT style_source, texture_source, bpm_source, key_source FROM sounds WHERE id = ?", arguments: [row.id]) else { continue }
                    let styleSource: String? = current["style_source"]
                    let textureSource: String? = current["texture_source"]
                    let bpmSource: String? = current["bpm_source"]
                    let keySource: String? = current["key_source"]

                    let evidence = PathEvidenceReader.read(relativePath: row.relativePath,
                                                           filename: row.filename,
                                                           taxonomy: taxonomy,
                                                           vocabulary: vocabulary,
                                                           styles: styles)

                    // 風格、材質、字面節拍：這些是字面事實，直接寫欄位。
                    // 分類建議刻意不在這裡產生；它必須走會讀音訊的主管線（D-040）。
                    // 人工設定過的一律不動（CLAUDE.md §57 第三條）。
                    var touchedManual = false

                    if !protected.contains(styleSource ?? ""), let style = evidence.style?.style {
                        try db.execute(
                            sql: "UPDATE sounds SET style = ?, style_source = ? WHERE id = ?",
                            arguments: [style, MetadataSource.imported.rawValue, row.id])
                        committed.styleFilled += 1
                    } else if protected.contains(styleSource ?? "") {
                        touchedManual = true
                    }

                    if !protected.contains(textureSource ?? ""),
                       let texture = TextureReader.read(relativePath: row.relativePath,
                                                        filename: row.filename,
                                                        vocabulary: textures,
                                                        category: evidence.category) {
                        try db.execute(
                            sql: "UPDATE sounds SET texture = ?, texture_source = ? WHERE id = ?",
                            arguments: [texture.texture, MetadataSource.imported.rawValue, row.id])
                        committed.textureFilled += 1
                    } else if protected.contains(textureSource ?? "") {
                        touchedManual = true
                    }

                    // 字面 BPM 與調性。**量測的那一半需要音訊，這裡不做。**
                    if !protected.contains(bpmSource ?? "") || !protected.contains(keySource ?? "") {
                        // 字面 BPM 只在檔名明寫 "bpm" 時才採用。
                        // 黏在字母上的數字（SND387）是編號不是節拍（D-027）。
                        let match = MusicalMetadata.bpm(in: row.relativePath)
                        let bpm = !protected.contains(bpmSource ?? "") && match?.explicit == true ? match?.bpm : nil
                        let key = protected.contains(keySource ?? "") ? nil : MusicalMetadata.key(in: row.relativePath)
                        let loop = protected.contains(bpmSource ?? "") ? nil : MusicalMetadata.loopHint(in: row.relativePath)
                        if bpm != nil || key != nil || loop != nil {
                            try db.execute(sql: """
                                UPDATE sounds
                                   SET bpm = COALESCE(?, bpm),
                                       bpm_source = CASE WHEN ? IS NULL THEN bpm_source ELSE ? END,
                                       musical_key = COALESCE(?, musical_key),
                                       key_source = CASE WHEN ? IS NULL THEN key_source ELSE ? END,
                                       is_loop = COALESCE(?, is_loop)
                                 WHERE id = ?
                                """, arguments: [bpm, bpm, MetadataSource.imported.rawValue,
                                                 key, key, MetadataSource.imported.rawValue,
                                                 loop, row.id])
                            committed.tempoFilled += 1
                        }
                    } else {
                        touchedManual = true
                    }

                    if touchedManual { committed.skippedManual += 1 }
                }
                    return committed
                }
                result = committed
            } catch {
                result.errorMessage = error.localizedDescription
                break
            }
            onProgress(result.scanned, total)
        }
        return result
    }
}
