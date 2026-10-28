import Foundation

/// 列表的複選狀態。純資料，沒有 UI、沒有資料庫。
///
/// 為什麼要有錨點：shift 點擊是「從上次點的那一列選到這一列」，
/// 沒有錨點就不知道從哪裡開始。
///
/// **換頁不清除選取。** 使用者的庫有 41,293 個檔案、每頁 20 筆，
/// 選到一半換頁就被清掉的話複選等於沒用。代價是選取裡可能有
/// 不在當前頁的 id——所有批次動作都直接吃 id，不需要那些列在畫面上。
struct SoundSelection: Equatable {

    private(set) var ids: Set<Int64> = []

    /// 上一個被點到的列。shift 範圍選取從這裡算起。
    private(set) var anchor: Int64?

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }
    /// 兩個以上才叫複選——一個的時候維持原本的單選行為，批次列不出現。
    var isMultiple: Bool { ids.count > 1 }

    func contains(_ id: Int64) -> Bool { ids.contains(id) }

    /// 一般點擊：只留這一個。
    mutating func replace(with id: Int64) {
        ids = [id]
        anchor = id
    }

    /// ⌘ 點擊：單獨加減一個。
    ///
    /// 取消掉的那一個仍然當錨點——Finder 是這樣，接著 shift 點擊才不會跳掉。
    mutating func toggle(_ id: Int64) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        anchor = id
    }

    /// ⇧ 點擊：從錨點選到這一列。
    ///
    /// 錨點不在當前頁時（換頁之後很常見）沒有範圍可算，
    /// 就把這一列加進來並成為新的錨點——**不清掉既有的選取**。
    mutating func extend(to id: Int64, in page: [Int64]) {
        guard let anchor,
              let from = page.firstIndex(of: anchor),
              let to = page.firstIndex(of: id) else {
            ids.insert(id)
            self.anchor = id
            return
        }
        let range = from <= to ? from...to : to...from
        ids.formUnion(page[range])
        // 錨點刻意不動：連續 shift 點擊要一直從同一個起點算，
        // 否則第二次 shift 點擊會從上一次的終點開始，選出來的範圍不是人想的那個。
    }

    /// ⌘A：全選當前頁。跨頁的既有選取保留。
    mutating func selectAll(_ page: [Int64]) {
        ids.formUnion(page)
        if anchor == nil { anchor = page.first }
    }

    mutating func clear() {
        ids = []
        anchor = nil
    }

    /// 選取裡已經不存在的 id（檔案被移除）清掉。
    mutating func prune(keeping existing: Set<Int64>) {
        ids.formIntersection(existing)
        if let anchor, existing.contains(anchor) == false { self.anchor = nil }
    }

    /// 批次動作的對象，順序固定，結果才可重現。
    var sortedIds: [Int64] { ids.sorted() }
}
