import Foundation

/// 從路徑字面抽出的音樂資訊。
///
/// 只讀字面，不碰音訊。廠商幾乎都把 BPM 和調性寫在檔名上：
/// `LOB_116_Drums_Cushdy_Full_1.wav`、`ESW LoFi - Top Loop 04 - 75 BPM.wav`、
/// `Cymatics - Diplomats - 149 BPM E Min Brass.wav`
enum MusicalMetadata {

    struct BPMMatch: Equatable {
        var bpm: Double
        /// 有沒有 "bpm" 這個字在旁邊。有的話幾乎不可能誤判。
        var explicit: Bool
        var term: String
    }

    /// 合理的 BPM 範圍。超出這個範圍的數字是檔案編號不是節拍。
    static let plausible: ClosedRange<Double> = 60...200

    /// 判斷「這是不是一個範圍寫法」時用的寬鬆帶。
    ///
    /// 比 `plausible` 寬，因為廠商的範圍資料夾會寫成 `55-89 BPM`——
    /// 55 不是我們會採用的 BPM，但它確實是範圍的一端。
    /// 用 `plausible` 去判斷範圍的話，這種資料夾就會漏掉，
    /// 然後 89 被當成這個檔案的節拍，整批 loop 全部標錯。
    private static let rangeBand: ClosedRange<Double> = 20...400

    /// 從文字抽 BPM。
    ///
    /// 兩種強度：
    ///
    /// - **明確**：數字旁邊有 "bpm"（`75 BPM`、`(144BPM)`）。幾乎不會錯。
    /// - **推測**：獨立的 2–3 位數字且落在合理範圍（`LOB_116_Drums`）。
    ///   `SND387`、`06622_SFX` 這種黏在字母上或超出範圍的不算。
    ///
    /// 範圍（`100-175 BPM` 這種資料夾名）一律忽略——那是一整包的範圍，
    /// 不是這個檔案的節拍，硬取其中一個數字是在編。
    static func bpm(in text: String) -> BPMMatch? {
        let lowered = text.lowercased()

        // 先排除範圍寫法，例如 "100-175 bpm"、"55-89 bpm"。
        //
        // 但**兩個數字都要像節拍才算範圍**（`rangeBand`）。
        // `ESW LoFi - Top Loop 04 - 75 BPM.wav` 長得像範圍（"04 - 75 bpm"），
        // 其實是「第 04 軌，75 BPM」。04 連 20 都不到，所以那不是範圍。
        // 第一版沒有這個檢查，把使用者庫裡一整批檔名的 BPM 全吃掉了。
        var scrubbed = lowered
        let rangePattern = #"(\d{2,3})\s*[-–]\s*(\d{2,3})\s*bpm"#
        if let regex = try? NSRegularExpression(pattern: rangePattern) {
            let matches = regex.matches(in: lowered,
                                        range: NSRange(lowered.startIndex..., in: lowered))
            for match in matches.reversed() {
                guard let lowRange = Range(match.range(at: 1), in: lowered),
                      let highRange = Range(match.range(at: 2), in: lowered),
                      let low = Double(lowered[lowRange]),
                      let high = Double(lowered[highRange]),
                      rangeBand.contains(low), rangeBand.contains(high),
                      let full = Range(match.range, in: scrubbed) else { continue }
                scrubbed.replaceSubrange(full, with: " ")
            }
        }

        // 明確：數字與 bpm 相鄰（任一順序）
        for pattern in [#"(\d{2,3})\s*bpm"#, #"bpm\s*(\d{2,3})"#] {
            if let value = firstNumber(pattern, in: scrubbed), plausible.contains(value) {
                return BPMMatch(bpm: value, explicit: true, term: "\(Int(value)) bpm")
            }
        }

        // 推測：獨立的 2–3 位數字。前後必須是分隔符，不能黏在字母上。
        let standalone = #"(?<![0-9a-z])(\d{2,3})(?![0-9a-z])"#
        if let regex = try? NSRegularExpression(pattern: standalone) {
            let matches = regex.matches(in: scrubbed,
                                        range: NSRange(scrubbed.startIndex..., in: scrubbed))
            let values = matches.compactMap { match -> Double? in
                guard let range = Range(match.range(at: 1), in: scrubbed) else { return nil }
                return Double(scrubbed[range])
            }.filter { plausible.contains($0) }
            // 只有唯一一個合理候選時才採用。兩個以上代表其中至少一個是編號，
            // 沒有依據在它們之間選。
            if values.count == 1, let value = values.first {
                return BPMMatch(bpm: value, explicit: false, term: "\(Int(value))")
            }
        }
        return nil
    }

    /// 從文字抽調性。
    ///
    /// 只認「音名 + 升降記號」或「音名 + 調式」——單獨一個大寫字母誤判率太高
    /// （`Kit C`、`Take A` 到處都是）。
    static func key(in text: String) -> String? {
        // 調式用 (?i:) 不分大小寫——廠商寫 "E Min"、"E MIN"、"E minor" 的都有。
        //
        // **音名維持大寫。** 接受小寫音名會讓誤判暴增：小寫 b 是降記號不是音名，
        // 而 a、e、c 這些字母在檔名裡到處都是。寧可漏掉 "e min"，
        // 也不要把 "take a min" 讀成 A 小調。
        let pattern = #"(?<![A-Za-z])([A-G])(#|b)?\s?(?i:(maj|major|min|minor|m))(?![A-Za-z])"#
            + #"|(?<![A-Za-z])([A-G])(#|b)(?![A-Za-z#b])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text,
                                           range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }

        if let note = group(1) {
            let accidental = group(2) ?? ""
            let mode = (group(3) ?? "").lowercased()
            let isMinor = mode.hasPrefix("min") || mode == "m"
            return note.uppercased() + accidental + (isMinor ? "m" : "")
        }
        if let note = group(4) {
            return note.uppercased() + (group(5) ?? "")
        }
        return nil
    }

    /// 路徑字面有沒有說這是 loop 或 one-shot。
    static func loopHint(in text: String) -> Bool? {
        // 路徑分隔符與副檔名的點也要當成分隔符，否則 "LOOPS/x.wav" 裡的
        // loops 後面沒有空白，詞界比對會漏掉。
        let lowered = PathEvidenceReader.normalise(text)
        if lowered.contains(" one shot ") || lowered.contains(" oneshot ")
            || lowered.contains(" one shots ") || lowered.contains(" oneshots ") {
            return false
        }
        for term in [" loop ", " loops ", " break ", " breaks ", " groove ", " bar "]
        where lowered.contains(term) {
            return true
        }
        return nil
    }

    private static func firstNumber(_ pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }
}
