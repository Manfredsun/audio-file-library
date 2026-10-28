import Foundation

/// 信心門檻。預設值來自 `references/confidence-rules.md`，且必須可調整——
/// 這些數字尚未經過評估資料集校準，不要當成真理（ROADMAP §35）。
struct ConfidencePolicy: Equatable {
    enum Band: String, Equatable {
        case strong
        case moderate
        case weak
        case veryWeak
    }

    var strongMin: Double
    var moderateMin: Double
    var weakMin: Double
    /// 低於此值一律進 Needs Review。
    var reviewBelow: Double

    init(strongMin: Double = 0.85,
         moderateMin: Double = 0.65,
         weakMin: Double = 0.40,
         reviewBelow: Double = 0.70) {
        self.strongMin = strongMin
        self.moderateMin = moderateMin
        self.weakMin = weakMin
        self.reviewBelow = reviewBelow
    }

    static let `default` = ConfidencePolicy()

    func band(for confidence: Double) -> Band {
        if confidence >= strongMin { return .strong }
        if confidence >= moderateMin { return .moderate }
        if confidence >= weakMin { return .weak }
        return .veryWeak
    }

    /// 只會把 `needsReview` 由 false 提升為 true，**永遠不會**把 true 降為 false。
    ///
    /// Organizer 自己說要複查時，理由可能與信心無關（例如檔名與音訊衝突，
    /// 見 examples.md 第 4 例），應用程式沒有資格推翻它。
    func effectiveNeedsReview(for result: OrganizerResult) -> Bool {
        if result.needsReview { return true }
        switch result.status {
        case .uncertain, .unknown, .failed:
            return true
        case .recognized, .suggested:
            return result.confidence < reviewBelow
        }
    }
}
