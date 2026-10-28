import Foundation

/// 翻頁列上的一格。
enum PageToken: Equatable, Hashable {
    case page(Int)
    /// 被省略掉的一段頁碼。
    case gap
}

/// 頁碼視窗的計算。
///
/// 純邏輯，沒有任何 UI 相依，所以整張真值表都能用測試釘住。
/// 41,293 個檔案、每頁 20 筆 = 2,065 頁，一頁一頁按不可能，
/// 所以要能看到自己在哪、也能直接跳。
enum Pagination {

    /// 目前頁前後各顯示幾頁。
    static let defaultWindow = 2

    /// 回傳翻頁列要顯示的內容。頁碼從 1 開始。
    ///
    /// 規則：永遠顯示第一頁與最後一頁，加上目前頁前後各 `window` 頁，
    /// 中間斷掉的地方放刪節號。
    static func tokens(total: Int, current: Int, window: Int = defaultWindow) -> [PageToken] {
        guard total > 0 else { return [] }
        let current = min(max(current, 1), total)

        var wanted: Set<Int> = [1, total]
        for page in (current - window)...(current + window) where page >= 1 && page <= total {
            wanted.insert(page)
        }

        var tokens: [PageToken] = []
        var previous = 0
        for page in wanted.sorted() {
            let gapSize = page - previous - 1
            if previous > 0 && gapSize > 0 {
                // 刪節號只蓋掉一頁時，直接把那一頁顯示出來。
                // 「1 … 3 4 5」裡的 … 其實就是第 2 頁，寫成「1 2 3 4 5」才對。
                // Google 的翻頁感覺順手，一半是因為處理了這種細節。
                if gapSize == 1 {
                    tokens.append(.page(previous + 1))
                } else {
                    tokens.append(.gap)
                }
            }
            tokens.append(.page(page))
            previous = page
        }
        return tokens
    }
}
