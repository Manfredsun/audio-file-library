import Foundation

/// 節拍的量測結果。
struct TempoEstimate: Equatable {
    var bpm: Double?
    /// 0–1。兩種互相獨立的方法一致時才會高。
    var confidence: Double
    /// 給審核介面看的依據。
    var reason: String

    static let none = TempoEstimate(bpm: nil, confidence: 0, reason: "沒有足夠的節奏證據")
}

/// 從音訊量測節拍。
///
/// 兩種互相獨立的方法：
///
/// 1. **長度反推**——sample pack 的 loop 幾乎都是剪成整數小節的。
///    已知小節數就能從長度直接算出 BPM，而且極準。
/// 2. **起音間隔**——相鄰起音點之間的時間，取眾數當一拍。
///    loop 沒有剪準時這一條還在。
///
/// 兩者一致才給高信心。這跟分類層「兩條獨立證據」是同一個原則：
/// 一個方法說 87、另一個也說 87，那大概就是 87。
enum TempoAnalyzer {

    /// 常見的 BPM 範圍。超出的都會被折進來。
    static let range: ClosedRange<Double> = 60...200

    /// sample pack 常見的小節數。
    static let commonBars = [1, 2, 4, 8, 16]

    /// 把 BPM 折進常見範圍。
    ///
    /// 節拍本來就有八度模糊：87 與 174 在訊號上是同一件事，
    /// 差別只在你把哪一層當成「一拍」。折進 60–200 是業界慣例。
    ///
    /// **這個範圍本身消不掉模糊性**：87 與 174 都在範圍內，
    /// 從 348 折下來會停在 174 而不是 87。真正解決模糊的是
    /// `estimate` 裡兩種方法的互相印證，不是折疊。
    static func fold(_ bpm: Double, into range: ClosedRange<Double> = TempoAnalyzer.range) -> Double? {
        guard bpm.isFinite, bpm > 0 else { return nil }
        var value = bpm
        var guard_ = 0
        while value < range.lowerBound && guard_ < 12 { value *= 2; guard_ += 1 }
        while value > range.upperBound && guard_ < 12 { value /= 2; guard_ += 1 }
        return range.contains(value) ? value : nil
    }

    /// 假設整段正好是整數小節，從長度反推 BPM。
    ///
    /// 回傳所有落在合理範圍內的候選，由呼叫端跟其他證據對照。
    static func fromDuration(_ duration: Double,
                             bars: [Int] = commonBars,
                             beatsPerBar: Int = 4) -> [Double] {
        guard duration > 0.2 else { return [] }
        return bars.compactMap { bar in
            let beats = Double(bar * beatsPerBar)
            return fold(beats * 60 / duration)
        }
    }

    /// 從起音點的時間推估 BPM。
    ///
    /// 取相鄰間隔的眾數而不是平均：平均會被一個長休止整個拉歪，
    /// 而眾數對「大部分的拍子都差不多長」這件事很穩。
    static func fromOnsets(_ times: [Double], tolerance: Double = 0.06) -> Double? {
        guard times.count >= 4 else { return nil }
        let intervals = zip(times.dropFirst(), times).map { $0 - $1 }.filter { $0 > 0.05 }
        guard intervals.count >= 3 else { return nil }

        // 把彼此接近的間隔分成一群，最大的那一群就是主要的拍長。
        var best: (interval: Double, votes: Int) = (0, 0)
        for candidate in intervals {
            let votes = intervals.filter { abs($0 - candidate) <= candidate * tolerance }.count
            if votes > best.votes { best = (candidate, votes) }
        }
        guard best.votes >= 3 else { return nil }

        // 用群內平均當代表值，比單一樣本穩。
        let members = intervals.filter { abs($0 - best.interval) <= best.interval * tolerance }
        let mean = members.reduce(0, +) / Double(members.count)
        return fold(60 / mean)
    }

    /// 合併兩種方法。
    static func estimate(duration: Double,
                         onsetTimes: [Double],
                         isLoopLike: Bool) -> TempoEstimate {
        let fromOnsets = fromOnsets(onsetTimes)
        let candidates = isLoopLike ? fromDuration(duration) : []

        if let measured = fromOnsets,
           let agreeing = candidates.min(by: { abs($0 - measured) < abs($1 - measured) }),
           abs(agreeing - measured) <= 2 {
            // 兩條獨立證據一致。長度反推的值更精確（它是整除算出來的），採用它。
            return TempoEstimate(bpm: (agreeing * 10).rounded() / 10,
                                 confidence: 0.9,
                                 reason: "長度反推與起音間隔一致")
        }
        if let measured = fromOnsets {
            return TempoEstimate(bpm: (measured * 10).rounded() / 10,
                                 confidence: 0.5,
                                 reason: "只有起音間隔的證據")
        }
        if candidates.count == 1, let only = candidates.first {
            return TempoEstimate(bpm: (only * 10).rounded() / 10,
                                 confidence: 0.4,
                                 reason: "只有長度反推，且只有一個合理候選")
        }
        // 多個候選但沒有東西可以在它們之間選——說不知道，不要挑一個。
        return .none
    }
}
