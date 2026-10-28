import Foundation

/// 側欄的資料夾節點。`count` 含子資料夾。
struct FolderNode: Identifiable, Hashable {
    let path: String
    let name: String
    let count: Int
    let children: [FolderNode]

    var id: String { path }
    var hasChildren: Bool { !children.isEmpty }
}

enum FolderTree {

    /// 由「資料夾 → 直接檔案數」建出樹。
    ///
    /// 中間層資料夾可能自己一個檔案都沒有（例如只有 `A/B/x.wav` 時的 `A`），
    /// 但它仍然必須出現在樹上，否則使用者點不進去。
    static func build(from counts: [(path: String, count: Int)]) -> [FolderNode] {
        var direct: [String: Int] = [:]
        var allPaths = Set<String>()

        for entry in counts where !entry.path.isEmpty {
            direct[entry.path, default: 0] += entry.count
            var parts = entry.path.split(separator: "/").map(String.init)
            while !parts.isEmpty {
                allPaths.insert(parts.joined(separator: "/"))
                parts.removeLast()
            }
        }

        func total(of path: String) -> Int {
            let prefix = path + "/"
            return direct.reduce(0) { sum, entry in
                (entry.key == path || entry.key.hasPrefix(prefix)) ? sum + entry.value : sum
            }
        }

        func children(of parent: String) -> [FolderNode] {
            let depth = parent.isEmpty ? 1 : parent.split(separator: "/").count + 1
            let prefix = parent.isEmpty ? "" : parent + "/"

            let names = allPaths.filter { path in
                guard parent.isEmpty || path.hasPrefix(prefix) else { return false }
                return path.split(separator: "/").count == depth
            }

            return names.sorted { lhs, rhs in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }.map { path in
                FolderNode(path: path,
                           name: path.split(separator: "/").last.map(String.init) ?? path,
                           count: total(of: path),
                           children: children(of: path))
            }
        }

        return children(of: "")
    }
}
