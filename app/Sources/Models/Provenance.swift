import Foundation

/// Metadata 來源。`manual` 永不被自動覆寫（AGENTS.md §7、ROADMAP §6）。
enum MetadataSource: String, Codable, CaseIterable, Hashable {
    case manual
    case acceptedAI = "accepted_ai"
    /// 歷史值。Antigravity 已經從這個 app 移除（D-013），但舊資料可能帶著它，
    /// 所以列舉值留著——拿掉會讓那些列解碼失敗。
    case antigravity
    case imported
    case system

    var isManual: Bool { self == .manual }

    /// 權威順序：manual > accepted_ai > antigravity/imported > system
    var authority: Int {
        switch self {
        case .manual:       return 4
        case .acceptedAI:   return 3
        case .antigravity:  return 2
        case .imported:     return 2
        case .system:       return 1
        }
    }
}

/// 檔案狀態。離線是正常狀態，不是錯誤。
enum FileStatus: String, Codable, CaseIterable, Hashable {
    case ok
    case missing
    case offline
    /// 檔案在，但音訊讀不動（損毀或系統不支援的編碼）。
    /// 仍然保留紀錄——使用者可能想知道它壞了。
    case unreadable
}

/// 分析狀態。注意：這不能取代 `needs_review`（見 DECISIONS D-004）。
enum AnalysisStatus: String, Codable, CaseIterable, Hashable {
    case none
    case queued
    case analyzing
    case done
    case failed
}
