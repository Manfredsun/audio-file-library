import Foundation

/// 把命名計畫變成可執行的連結工作，依音色庫分組。
///
/// **為什麼依音色庫分組**：硬連結必須跟原檔在同一個檔案系統上。
/// 把整理樹放在每個音色庫自己的根目錄底下（`<庫根目錄>/_Organized/`），
/// 這條限制就自然滿足，不需要額外檢查掛載點。
///
/// 目前只建 **by-role** 一棵樹（`Drums/Kick/…`）。dev-plan 原本規劃 by-genre
/// 與 by-role 兩棵，但風格只有 70% 的檔案有、角色有 95%，而且兩棵樹的連結數量
/// 直接翻倍。先做覆蓋率高的那一棵；要加另一棵隨時再跑一次就好，
/// 原檔從頭到尾沒被動過，成本只是時間。
enum OrganizeRun {

    /// 整理樹在音色庫根目錄底下的名字。
    static let treeFolder = "_Organized"

    struct Group: Equatable {
        var libraryId: Int64
        /// 這一批的整理樹根目錄，例如 `/Volumes/Example SSD/Drums/_Organized`。
        var root: String
        var jobs: [OrganizeExecutor.Job]
    }

    /// 依音色庫分組。`rows` 用來把 sound id 對回原始檔案路徑與庫根目錄。
    ///
    /// 有阻擋性問題的那幾筆（碰撞、descriptor 不在原路徑裡）**不會進來**——
    /// 這是安全模型的第三道：執行的東西必須是人看過的那份 manifest 裡乾淨的部分。
    static func groups(from plan: NamingPlan, rows: [NamingRow]) -> [Group] {
        var byId: [Int64: NamingRow] = [:]
        for row in rows { byId[row.id] = row }

        var grouped: [Int64: Group] = [:]
        for entry in plan.entries {
            guard entry.issues.contains(where: \.isBlocking) == false else { continue }
            guard let row = byId[entry.soundId],
                  row.filePath.isEmpty == false,
                  row.libraryRoot.isEmpty == false else { continue }

            let root = (row.libraryRoot as NSString).appendingPathComponent(treeFolder)
            grouped[row.libraryId, default: Group(libraryId: row.libraryId, root: root, jobs: [])]
                .jobs.append(OrganizeExecutor.Job(soundId: entry.soundId,
                                                  sourcePath: row.filePath,
                                                  destination: entry.destination))
        }
        // 順序固定，結果才可重現。
        return grouped.values.sorted { $0.libraryId < $1.libraryId }
    }

    /// 這次執行總共會建立幾個連結。按下去之前要講清楚的數字。
    static func linkCount(_ groups: [Group]) -> Int {
        groups.reduce(0) { $0 + $1.jobs.count }
    }
}
