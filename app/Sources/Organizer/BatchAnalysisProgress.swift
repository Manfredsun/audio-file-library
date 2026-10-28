import Foundation

/// 批次分析的進度。
///
/// `failed` 與 `needsReview` 分開計數是刻意的：
/// 「讀不到檔案」與「分析完但沒把握」是兩件事，混在一起會讓使用者
/// 誤以為八百多個檔案裡有一半壞掉。
struct BatchAnalysisProgress: Equatable {
    enum Phase: String, Equatable {
        case idle
        case running
        case finished
        case cancelled
    }

    var phase: Phase = .idle
    var total: Int = 0
    var completed: Int = 0
    var failed: Int = 0
    var needsReview: Int = 0
    var currentName: String = ""

    var isRunning: Bool { phase == .running }

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    var summary: String { summary(locale: L10n.language) }

    func summary(locale: String) -> String {
        switch phase {
        case .idle:
            return ""
        case .running:
            return L10n.tr("分析中 %@/%@", String(describing: completed), String(describing: total), locale: locale)
        case .cancelled:
            return L10n.tr("已中止，完成 %@/%@", String(describing: completed), String(describing: total), locale: locale)
        case .finished:
            var parts = [L10n.tr("batch.completed", completed, locale: locale)]
            if needsReview > 0 { parts.append(L10n.tr("batch.review", needsReview, locale: locale)) }
            if failed > 0 { parts.append(L10n.tr("batch.failed", failed, locale: locale)) }
            return parts.joined(separator: L10n.tr("separator.list", locale: locale))
        }
    }
}
