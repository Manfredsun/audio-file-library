import Foundation

/// 受控風格白名單。由 `style-vocabulary.md` 經 `scripts/generate-schemas.py` 產生。
struct StyleVocabulary: Decodable, Equatable {
    let version: Int
    let source: String
    let sourceSHA256: String
    /// 正規風格名。
    let styles: [String]
    /// 廠商用語 → 正規風格名。鍵一律小寫。
    let aliases: [String: String]
    /// 比對順序：詞數多的在前，"tech house" 才不會被 "house" 搶走。
    /// 排序在產生階段做掉，Swift 端不必依賴宣告順序。
    let aliasOrder: [String]
    /// 同時是曲風名也是一般音效描述詞的別名。只有在音樂製作素材的脈絡下才算風格。
    let ambiguous: [String]

    enum CodingKeys: String, CodingKey {
        case version
        case source
        case sourceSHA256 = "source_sha256"
        case styles
        case aliases
        case aliasOrder = "alias_order"
        case ambiguous
    }

    var styleSet: Set<String> { Set(styles) }
    var ambiguousSet: Set<String> { Set(ambiguous) }

    func isValid(_ style: String) -> Bool { styleSet.contains(style) }

    static func load(from bundle: Bundle = .main) throws -> StyleVocabulary {
        guard let url = bundle.url(forResource: "style-vocabulary", withExtension: "json") else {
            throw AppError.organizerInvalidOutput("找不到 style-vocabulary.json 資源")
        }
        return try JSONDecoder().decode(StyleVocabulary.self, from: Data(contentsOf: url))
    }
}

/// 從路徑讀出風格。
///
/// 只讀字面，不碰音訊。一個 kick 就是一個 kick——Boom Bap 的 kick 與
/// Tech House 的 kick 在頻譜上沒有可靠的分界，任何宣稱「聽出風格」的系統
/// 都是在做 D-013 記錄的那件事。風格寫在廠商的資料夾名上，那才是證據。
enum StyleReader {

    struct Match: Equatable {
        var style: String
        /// 實際命中的字串。審核介面要能說明「因為資料夾裡有 boom bap」。
        var term: String
        /// 命中在資料夾還是檔名。資料夾比較可信。
        var fromFolder: Bool
    }

    /// `relativePath` 應含資料夾與檔名。找不到就回 nil——nil 是合法狀態，不是失敗。
    ///
    /// `category` 是同一次分析算出的分類，用來判斷這是不是音樂製作素材。
    /// 有些字（metal、rock、house⋯⋯）同時是曲風也是一般的音效描述詞，
    /// 只有在 `Drums/` 或 `Instruments/` 底下才該被當成曲風——
    /// 「金屬地板上的赤腳腳步聲」不是重金屬，「房子音效庫」不是 House 音樂。
    static func read(relativePath: String,
                     filename: String,
                     vocabulary: StyleVocabulary,
                     category: String? = nil) -> Match? {
        let production = isProductionMaterial(category)
        let folder = (relativePath as NSString).deletingLastPathComponent
        if let match = firstMatch(in: PathEvidenceReader.normalise(folder),
                                  vocabulary: vocabulary, production: production) {
            return Match(style: match.0, term: match.1, fromFolder: true)
        }
        let base = (filename as NSString).deletingPathExtension
        if let match = firstMatch(in: PathEvidenceReader.normalise(base),
                                  vocabulary: vocabulary, production: production) {
            return Match(style: match.0, term: match.1, fromFolder: false)
        }
        return nil
    }

    /// 分類為 nil 時視為「沒有製作素材的證據」，模糊字一律不採用。
    /// 寧可漏標，不要標錯——錯的風格標籤事後分辨不出來。
    static func isProductionMaterial(_ category: String?) -> Bool {
        guard let category else { return false }
        return category.hasPrefix("Drums/") || category.hasPrefix("Instruments/")
            || category == "Drums" || category == "Instruments"
    }

    /// 詞界比對，不是子字串比對。
    /// `normalise` 已經把文字包成 " a b c " 的形式，所以比對 " term " 就是詞界比對——
    /// "pop" 不會命中 "City Pop" 裡的 pop 以外的位置，"house" 不會吃掉 "Tech House"。
    private static func firstMatch(in normalisedText: String,
                                   vocabulary: StyleVocabulary,
                                   production: Bool) -> (String, String)? {
        guard normalisedText.trimmingCharacters(in: .whitespaces).isEmpty == false else { return nil }
        let ambiguous = vocabulary.ambiguousSet
        for alias in vocabulary.aliasOrder {
            guard let style = vocabulary.aliases[alias] else { continue }
            // 模糊字只在音樂製作素材的脈絡下採用。
            if ambiguous.contains(alias), production == false { continue }
            if normalisedText.contains(" \(alias) ") {
                return (style, alias)
            }
        }
        return nil
    }
}
