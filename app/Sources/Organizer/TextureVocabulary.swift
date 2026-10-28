import Foundation

/// 受控材質白名單。由 `texture-vocabulary.md` 經 `scripts/generate-schemas.py` 產生。
struct TextureVocabulary: Decodable, Equatable {
    let version: Int
    let source: String
    let sourceSHA256: String
    /// 正規材質名。
    let textures: [String]
    /// 廠商用語與中文 → 正規材質名。鍵一律小寫。
    let aliases: [String: String]
    /// 比對順序：詞數多的在前。
    let aliasOrder: [String]
    /// 表面／硬度詞。**只是退路**——路徑上有材質詞就用材質詞。
    let surface: [String]
    /// 同時是材質也是曲風的字（metal、rock）。
    let ambiguous: [String]

    enum CodingKeys: String, CodingKey {
        case version, source, textures, aliases, surface, ambiguous
        case sourceSHA256 = "source_sha256"
        case aliasOrder = "alias_order"
    }

    var textureSet: Set<String> { Set(textures) }
    var surfaceSet: Set<String> { Set(surface) }
    var ambiguousSet: Set<String> { Set(ambiguous) }

    func isValid(_ texture: String) -> Bool { textureSet.contains(texture) }

    static func load(from bundle: Bundle = .main) throws -> TextureVocabulary {
        guard let url = bundle.url(forResource: "texture-vocabulary", withExtension: "json") else {
            throw AppError.organizerInvalidOutput("找不到 texture-vocabulary.json 資源")
        }
        return try JSONDecoder().decode(TextureVocabulary.self, from: Data(contentsOf: url))
    }
}

/// 從路徑讀出材質。
///
/// **材質聽不出來，但常常寫在路徑上。**
/// 塑膠與木頭在頻譜上沒有可靠的分界；宣稱聽得出來的系統就是在做 D-013 記錄的那件事
/// （金屬殘響被聽成「公雞啼叫」）。但錄音的人需要事後找得到自己的素材，
/// 所以材質幾乎都寫在檔名裡——`Bare_Feet_Metal_SLOW_MED_WALK`、`金屬撞擊聲`。
/// 那才是證據，而且使用者打開 Finder 就能驗證。
enum TextureReader {

    struct Match: Equatable {
        var texture: String
        /// 實際命中的字串。審核介面要能說明「因為檔名裡有 metal」。
        var term: String
        var fromFolder: Bool
        /// 命中的是材質詞還是表面詞。表面詞的證據力比較弱。
        var isSurface: Bool
    }

    /// `category` 用來處理跟曲風撞名的字。
    ///
    /// `metal` 與 `rock` 同時是材質與曲風。風格那邊已經把它們閘在
    /// `Drums/` 與 `Instruments/` 底下（D-020）；這裡取它的鏡像——
    /// 在那些分類底下這兩個字由風格認領，材質**留空**。
    ///
    /// 這會漏掉一些真的資訊（`kick_metal` 可能真的是金屬感的 kick），
    /// 是刻意的取捨：**一個字不能同時當兩個欄位的證據**，
    /// 而留空補得回來，標錯補不回來。
    static func read(relativePath: String,
                     filename: String,
                     vocabulary: TextureVocabulary,
                     category: String? = nil) -> Match? {
        let production = StyleReader.isProductionMaterial(category)
        let folder = (relativePath as NSString).deletingLastPathComponent
        let base = (filename as NSString).deletingPathExtension

        // 資料夾比檔名可信，材質比表面詞具體。四種組合的優先順序：
        // 資料夾材質 → 檔名材質 → 資料夾表面 → 檔名表面。
        let folderText = PathEvidenceReader.normalise(folder)
        let fileText = PathEvidenceReader.normalise(base)

        if let hit = match(in: folderText, vocabulary: vocabulary,
                           production: production, surfaceOnly: false) {
            return Match(texture: hit.0, term: hit.1, fromFolder: true, isSurface: false)
        }
        if let hit = match(in: fileText, vocabulary: vocabulary,
                           production: production, surfaceOnly: false) {
            return Match(texture: hit.0, term: hit.1, fromFolder: false, isSurface: false)
        }
        if let hit = match(in: folderText, vocabulary: vocabulary,
                           production: production, surfaceOnly: true) {
            return Match(texture: hit.0, term: hit.1, fromFolder: true, isSurface: true)
        }
        if let hit = match(in: fileText, vocabulary: vocabulary,
                           production: production, surfaceOnly: true) {
            return Match(texture: hit.0, term: hit.1, fromFolder: false, isSurface: true)
        }
        return nil
    }

    /// 中文用子字串比對，英文用詞界比對（D-023）。
    /// 中文沒有詞界，`normalise` 也不會在字之間插空白，所以只能用 contains；
    /// 英文若用 contains，`tin` 會命中 `painting`、`ice` 會命中 `service`。
    private static func match(in normalisedText: String,
                              vocabulary: TextureVocabulary,
                              production: Bool,
                              surfaceOnly: Bool) -> (String, String)? {
        guard normalisedText.trimmingCharacters(in: .whitespaces).isEmpty == false else { return nil }
        let surface = vocabulary.surfaceSet
        let ambiguous = vocabulary.ambiguousSet

        for alias in vocabulary.aliasOrder {
            guard let texture = vocabulary.aliases[alias] else { continue }
            // 表面詞只在這一輪或那一輪出現，不會兩輪都比。
            if surface.contains(texture) != surfaceOnly { continue }
            // 跟曲風撞名的字，在音樂製作素材底下讓給風格。
            if ambiguous.contains(alias), production { continue }

            if PathEvidenceReader.containsCJK(alias) {
                if normalisedText.contains(alias) { return (texture, alias) }
            } else if normalisedText.contains(" \(alias) ") || normalisedText.contains(" \(alias)s ") {
                return (texture, alias)
            }
        }
        return nil
    }
}
