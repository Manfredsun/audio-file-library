import Foundation

/// 可復原的錯誤狀態（CLAUDE.md §39）。一個壞檔案不能弄垮整個音色庫。
enum AppError: LocalizedError, Equatable {
    case libraryOffline(String)
    case missingFile(String)
    case permissionLost(String)
    case unsupportedAudio(String)
    case scanFailed(String)
    case databaseError(String)
    case organizerUnavailable(String)
    case organizerTimeout(String)
    case organizerInvalidOutput(String)
    case renameFailed(String)
    case fileConflict(String)

    var errorDescription: String? {
        switch self {
        case .libraryOffline(let s):        return L10n.tr("音色庫離線：%@", String(describing: s))
        case .missingFile(let s):           return L10n.tr("找不到檔案：%@", String(describing: s))
        case .permissionLost(let s):        return L10n.tr("失去存取權限：%@", String(describing: s))
        case .unsupportedAudio(let s):      return L10n.tr("不支援的音訊格式：%@", String(describing: s))
        case .scanFailed(let s):            return L10n.tr("掃描失敗：%@", String(describing: s))
        case .databaseError(let s):         return L10n.tr("資料庫錯誤：%@", String(describing: s))
        case .organizerUnavailable(let s):  return L10n.tr("Organizer 無法使用：%@", String(describing: s))
        case .organizerTimeout(let s):      return L10n.tr("Organizer 逾時：%@", String(describing: s))
        case .organizerInvalidOutput(let s):return L10n.tr("Organizer 輸出不合法：%@", String(describing: s))
        case .renameFailed(let s):          return L10n.tr("改名失敗：%@", String(describing: s))
        case .fileConflict(let s):          return L10n.tr("檔名衝突：%@", String(describing: s))
        }
    }
}
