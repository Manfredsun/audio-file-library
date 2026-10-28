import Foundation

/// 側欄分類區的一個節點（M41）。數量含子分類。
struct CategoryNode: Identifiable, Equatable {
    let path: String
    let name: String
    var confirmed: Int
    var suggested: Int
    var children: [CategoryNode]

    var id: String { path }
    var total: Int { confirmed + suggested }
}

/// 把每個路徑各自的數量，組成兩層的側欄樹。純邏輯，方便測試。
enum CategoryTree {

    /// 不列在分類區的路徑。「未分類」已經是 Review 區的一個入口，重複列出只會讓人困惑。
    static let excluded: Set<String> = ["Unclassified"]

    /// 頂層依名稱排序（找「Drums」要能預期它在哪裡），子分類也依名稱排序。
    /// 數量為 0 的節點不出現——空的分類只會把有東西的擠出視線。
    static func build(from counts: [CategoryCount]) -> [CategoryNode] {
        var tops: [String: CategoryNode] = [:]

        for count in counts where count.total > 0 {
            let parts = count.path.split(separator: "/", maxSplits: 1).map(String.init)
            guard let top = parts.first, excluded.contains(top) == false else { continue }

            var node = tops[top] ?? CategoryNode(path: top, name: top,
                                                 confirmed: 0, suggested: 0, children: [])
            node.confirmed += count.confirmed
            node.suggested += count.suggested

            if parts.count == 2 {
                node.children.append(CategoryNode(path: count.path, name: parts[1],
                                                  confirmed: count.confirmed,
                                                  suggested: count.suggested,
                                                  children: []))
            }
            tops[top] = node
        }

        return tops.values
            .map { node in
                var sorted = node
                sorted.children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return sorted
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
