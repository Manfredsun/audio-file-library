import Foundation

/// 組合式的篩選條件（CLAUDE.md §25）。
/// 每一條各自獨立，不寫死任何組合。
struct SoundFilters: Equatable {

    enum DurationBand: String, CaseIterable, Identifiable, Equatable {
        case any
        case short      // < 1s
        case medium     // 1–5s
        case long       // > 5s

        var id: String { rawValue }

        var title: String {
            switch self {
            case .any:    return L10n.tr("不限")
            case .short:  return "< 1s"
            case .medium: return "1–5s"
            case .long:   return "> 5s"
            }
        }

        var range: (lower: Double, upper: Double)? {
            switch self {
            case .any:    return nil
            case .short:  return (0, 1)
            case .medium: return (1, 5)
            case .long:   return (5, .greatestFiniteMagnitude)
            }
        }
    }

    /// 循環或單擊。挑素材時這是第一個要分開的兩種東西。
    enum LoopBand: String, CaseIterable, Identifiable, Equatable {
        case any
        case loops
        case oneShots

        var id: String { rawValue }

        var title: String {
            switch self {
            case .any:      return L10n.tr("不限")
            case .loops:    return L10n.tr("loop")
            case .oneShots: return L10n.tr("one-shot")
            }
        }
    }

    /// BPM 區間。挑 loop 時第一個要看的東西。
    ///
    /// 區間而不是精確值：沒有人會只要 87 不要 88。
    enum TempoBand: String, CaseIterable, Identifiable, Equatable {
        case any
        case slow        // < 90
        case mid         // 90–120
        case upTempo     // 120–140
        case fast        // > 140

        var id: String { rawValue }

        var title: String {
            switch self {
            case .any:     return L10n.tr("不限")
            case .slow:    return "< 90"
            case .mid:     return "90–120"
            case .upTempo: return "120–140"
            case .fast:    return "> 140"
            }
        }

        var range: (lower: Double, upper: Double)? {
            switch self {
            case .any:     return nil
            case .slow:    return (0, 90)
            case .mid:     return (90, 120)
            case .upTempo: return (120, 140)
            case .fast:    return (140, .greatestFiniteMagnitude)
            }
        }
    }

    var favoritesOnly = false
    var minRating = 0
    var duration: DurationBand = .any
    var fileTypes: Set<String> = []
    var loop: LoopBand = .any
    var tempo: TempoBand = .any

    var isActive: Bool {
        favoritesOnly || minRating > 0 || duration != .any || !fileTypes.isEmpty
            || loop != .any || tempo != .any
    }

    mutating func clear() {
        self = SoundFilters()
    }

    mutating func toggleFileType(_ ext: String) {
        if fileTypes.contains(ext) {
            fileTypes.remove(ext)
        } else {
            fileTypes.insert(ext)
        }
    }
}

/// 搜尋字串拆成詞。多個詞之間是 AND——
/// 「metal door」應該要找到同時符合兩者的檔案，而不是任一個。
enum SearchQuery {
    static func terms(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == " " || $0 == "　" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
