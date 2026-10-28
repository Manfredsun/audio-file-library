import Foundation

/// 一群共用命名慣例的檔案，以及從中抽出的 descriptor。
struct NamingConvention: Equatable {
    /// 這一群共同的固定前綴，例如 "AU_FP_"。
    var prefix: String
    /// 共同的固定後綴（不含副檔名）。
    var suffix: String
    var fileCount: Int
    /// 抽得出 descriptor 的檔案比例 0–1。
    var coverage: Double

    var isEmpty: Bool { fileCount == 0 }
}

/// 從一群檔名抽出命名慣例與 descriptor。
///
/// **全部在本機、確定性、可測試。**
///
/// 原本 M30 的計畫是把這件事整包交給 Antigravity（D-017）。實際動手才發現
/// 絕大部分是規則解得掉的：同一個資料夾裡的檔名共用前綴，剩下的段落
/// 扣掉角色詞、風格詞、編號、BPM、調性之後，留下來的就是 descriptor。
///
/// 照 AGENTS.md §60 的判準——寫得出確定性規則的就不要用 AI——這一層不該給它做。
/// 留給 Antigravity 的只剩下規則真的碰不到的那一小塊：沒有任何風格詞的 pack 名
/// （`Yeezus` → Hip Hop 這種要世界知識的），以及廠商附的說明文件。
enum NamingConventionDetector {

    /// 一群至少要有這麼多檔案，共同前綴才有意義。
    /// 兩三個檔案的「共同前綴」多半是巧合。
    static let minimumGroupSize = 4

    /// 前綴至少要這麼長才算前綴，避免把單一個字母當成慣例。
    static let minimumAffixLength = 2

    /// 扣掉之後不算 descriptor 的通用詞。
    ///
    /// 這些字描述的是「這是什麼類型的檔案」而不是「這個聲音聽起來如何」，
    /// 而類型已經由分類欄位表達了，重複寫進檔名只是雜訊。
    static let genericTerms: Set<String> = [
        "one", "shot", "shots", "oneshot", "oneshots", "sample", "samples",
        "wav", "aiff", "mp3", "audio", "sound", "sounds", "fx",
        "loop", "loops", "full", "part", "parts", "stem", "stems",
        "vol", "volume", "pack", "kit", "bonus", "bonuses", "free",
        "the", "and", "with", "by",
        // 真實庫量測（docs/naming-coverage.txt）抓出來的雜訊
        "sfx", "sfxs", "effect", "effects", "take", "takes", "file", "files",
        "track", "tracks", "mix", "master", "edit", "raw", "misc", "new",
        "final", "copy", "bpm", "hz", "khz", "bit", "mono", "stereo",
    ]

    /// descriptor 最多幾個字。
    ///
    /// 有些檔名整句都是描述（`..._onboard_startup_idle_steady_rpms_ramps_...`）。
    /// 那是紀錄不是名字——全部塞進新檔名只會得到另一個一樣難讀的檔名。
    static let maximumDescriptorWords = 4

    /// 一個詞出現在這麼高比例的檔案裡，就算是整群共用的（廠商名、pack 名）。
    ///
    /// 嚴格的「位置前綴」抓不到 `Cymatics - Lofi Top Loop 1` 這種：
    /// 資料夾裡混了別的東西，Cymatics 就不在第 0 個位置了，
    /// 但它出現在 95% 的檔名裡，那顯然不是在描述聲音。
    static let groupTermShare = 0.8

    /// 把檔名拆成可比較的詞。
    static func tokens(of filename: String) -> [String] {
        let base = (filename as NSString).deletingPathExtension
        let separators = CharacterSet.alphanumerics.inverted
        return base.components(separatedBy: separators).filter { $0.isEmpty == false }
    }

    /// 去掉頭尾的數字，露出詞本身。
    ///
    /// `Track01` 是 `track`（通用詞），`86BPM` 是 `bpm`（通用詞），
    /// 但 `ak47` 去掉數字只剩 `ak`——那不是詞，所以保留原樣。
    static func stem(of token: String) -> String {
        let trimmed = token.drop(while: \.isNumber).reversed().drop(while: \.isNumber).reversed()
        let candidate = String(trimmed)
        return candidate.count >= 3 ? candidate : token
    }

    /// 整群共用的詞——廠商名、pack 名。出現在 `groupTermShare` 以上的檔名裡。
    static func groupTerms(_ filenames: [String]) -> Set<String> {
        guard filenames.count >= minimumGroupSize else { return [] }
        var counts: [String: Int] = [:]
        for filename in filenames {
            for token in Set(tokens(of: filename).map({ $0.lowercased() })) {
                counts[token, default: 0] += 1
            }
        }
        let threshold = Double(filenames.count) * groupTermShare
        return Set(counts.filter { Double($0.value) >= threshold }.keys)
    }

    /// 一群檔名的共同前綴詞與後綴詞。
    ///
    /// 用**詞**而不是字元：字元層級的共同前綴會切在詞中間
    /// （`kick_hard` 與 `kick_soft` 的字元共同前綴是 `kick_` 沒錯，
    /// 但 `snare_1` 與 `snake_2` 會變成 `sna`，那不是慣例是巧合）。
    static func commonAffixes(_ filenames: [String]) -> (prefix: [String], suffix: [String]) {
        guard filenames.count >= minimumGroupSize else { return ([], []) }
        let all = filenames.map { tokens(of: $0) }
        guard let shortest = all.map(\.count).min(), shortest > 0 else { return ([], []) }

        var prefix: [String] = []
        for index in 0..<shortest {
            let candidate = all[0][index].lowercased()
            guard all.allSatisfy({ $0[index].lowercased() == candidate }) else { break }
            prefix.append(all[0][index])
        }
        // 前綴不可以把整個檔名吃掉，否則就沒有東西能分辨檔案了。
        if prefix.count >= shortest { prefix.removeLast() }

        var suffix: [String] = []
        for index in 0..<(shortest - prefix.count) {
            let candidate = all[0][all[0].count - 1 - index].lowercased()
            guard all.allSatisfy({ $0[$0.count - 1 - index].lowercased() == candidate }) else { break }
            suffix.insert(all[0][all[0].count - 1 - index], at: 0)
        }

        return (prefix.joined(separator: "_").count >= minimumAffixLength ? prefix : [],
                suffix.joined(separator: "_").count >= minimumAffixLength ? suffix : [])
    }

    /// 抽出一個檔名的 descriptor。
    ///
    /// 步驟：去掉共同前後綴 → 去掉角色詞、風格詞、通用詞 → 去掉編號、BPM、調性。
    /// 剩下的就是廠商用來形容這個聲音的字。
    ///
    /// **抽不出來就回 nil。** 不填佔位字，不拿編號充數（D-017）。
    static func descriptor(for filename: String,
                           prefix: [String],
                           suffix: [String],
                           roleTerms: Set<String>,
                           styleTerms: Set<String>,
                           groupTerms: Set<String> = []) -> String? {
        let all = tokens(of: filename)
        guard all.isEmpty == false else { return nil }

        // 共同前後綴的位置先標起來，等一下跳過。
        var dropped = Set<Int>()
        if all.count > prefix.count, prefix.isEmpty == false,
           all.prefix(prefix.count).map({ $0.lowercased() }) == prefix.map({ $0.lowercased() }) {
            dropped.formUnion(0..<prefix.count)
        }
        if all.count > suffix.count, suffix.isEmpty == false,
           all.suffix(suffix.count).map({ $0.lowercased() }) == suffix.map({ $0.lowercased() }) {
            dropped.formUnion((all.count - suffix.count)..<all.count)
        }

        // **第一個角色詞是「這個檔案是什麼」，之後的角色詞是音色。**
        //
        // `SD_Snare_WoodBlock` 是一顆聽起來像木魚的小鼓——woodblock 本身也是角色詞，
        // 但它出現在 snare 後面。把它一起扣掉會把整個檔名扣光，
        // 而那正是這個檔名裡唯一有價值的資訊。
        //
        // 用**位置**判斷而不是「扣過一次了沒」：角色詞可能藏在共同前綴裡
        // （`FTH_Kick_*`），也可能被別的規則先扣掉，那些都不該讓真正的角色逃掉。
        let roleIndex = all.firstIndex { roleTerms.contains(stem(of: $0).lowercased()) }

        let key = MusicalMetadata.key(in: filename)?.lowercased()
        var kept: [String] = []
        for (index, token) in all.enumerated() {
            if dropped.contains(index) { continue }
            if index == roleIndex { continue }
            let lower = stem(of: token).lowercased()
            if lower.isEmpty { continue }
            // 純數字：編號、BPM、軌號，全部不是描述。
            if lower.allSatisfy(\.isNumber) { continue }
            if genericTerms.contains(lower) { continue }
            // 整群共用的詞是廠商名或 pack 名，不是這一個檔案的描述。
            if groupTerms.contains(lower) { continue }
            if roleTerms.contains(lower) { kept.append(token); continue }
            if styleTerms.contains(lower) { continue }
            if let key, lower == key { continue }
            // 一兩個字母的殘渣多半是廠商代號，不是描述。
            if lower.count <= 2 { continue }
            kept.append(token)
        }

        guard kept.isEmpty == false else { return nil }
        return kept.prefix(maximumDescriptorWords).joined(separator: " ")
    }

    /// 對一群檔名做完整的偵測。
    static func detect(filenames: [String],
                       roleTerms: Set<String>,
                       styleTerms: Set<String>) -> (convention: NamingConvention, descriptors: [String: String]) {
        guard filenames.count >= minimumGroupSize else {
            return (NamingConvention(prefix: "", suffix: "", fileCount: filenames.count, coverage: 0), [:])
        }
        let (prefix, suffix) = commonAffixes(filenames)
        let shared = groupTerms(filenames)
        var descriptors: [String: String] = [:]
        for filename in filenames {
            if let value = descriptor(for: filename,
                                      prefix: prefix,
                                      suffix: suffix,
                                      roleTerms: roleTerms,
                                      styleTerms: styleTerms,
                                      groupTerms: shared) {
                descriptors[filename] = value
            }
        }
        let convention = NamingConvention(
            prefix: prefix.joined(separator: "_"),
            suffix: suffix.joined(separator: "_"),
            fileCount: filenames.count,
            coverage: Double(descriptors.count) / Double(filenames.count))
        return (convention, descriptors)
    }

    /// 規則表裡所有的角色詞，用來從 descriptor 裡扣掉。
    static func roleTerms(from rules: [PathEvidenceReader.Rule]) -> Set<String> {
        var terms: Set<String> = []
        for rule in rules {
            for term in rule.terms where PathEvidenceReader.containsCJK(term) == false {
                // 多詞的規則拆開來收，因為 descriptor 是逐詞過濾的。
                for word in term.split(separator: " ") {
                    terms.insert(String(word).lowercased())
                }
            }
        }
        return terms
    }

    static func styleTerms(from vocabulary: StyleVocabulary) -> Set<String> {
        var terms: Set<String> = []
        for alias in vocabulary.aliases.keys {
            for word in alias.split(separator: " ") {
                terms.insert(String(word).lowercased())
            }
        }
        for style in vocabulary.styles {
            for word in style.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                terms.insert(String(word))
            }
        }
        return terms
    }
}
