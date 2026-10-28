import Foundation

/// 受控分類白名單。由 `taxonomy.md` 經 `scripts/generate-schemas.py` 產生。
struct Taxonomy: Decodable, Equatable {
    let version: Int
    let source: String
    /// 來源 markdown 的 sha256，用於偵測 md 與 json 漂移（CLAUDE.md §53）。
    let sourceSHA256: String
    let topLevel: [String]
    let categories: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case version
        case source
        case sourceSHA256 = "source_sha256"
        case topLevel = "top_level"
        case categories
    }

    static let unclassified = "Unclassified"

    /// 所有合法的分類路徑，例如 "Foley" 與 "Foley/Doors"。
    var allPaths: [String] {
        var paths: [String] = []
        for top in topLevel {
            paths.append(top)
            for sub in categories[top] ?? [] {
                paths.append("\(top)/\(sub)")
            }
        }
        return paths
    }

    func isValidPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        switch parts.count {
        case 1:
            return topLevel.contains(parts[0])
        case 2:
            guard topLevel.contains(parts[0]) else { return false }
            return (categories[parts[0]] ?? []).contains(parts[1])
        default:
            return false
        }
    }

    static func load(from bundle: Bundle = .main) throws -> Taxonomy {
        guard let url = bundle.url(forResource: "taxonomy", withExtension: "json") else {
            throw AppError.organizerInvalidOutput("找不到 taxonomy.json 資源")
        }
        return try JSONDecoder().decode(Taxonomy.self, from: Data(contentsOf: url))
    }
}

/// 受控標籤詞彙。由 `tagging-rules.md` 產生。
struct TagVocabulary: Decodable, Equatable {
    let version: Int
    let source: String
    let sourceSHA256: String
    let maxTags: Int
    let targetRange: [Int]
    let groups: [String: [String]]
    let canonical: [String]

    enum CodingKeys: String, CodingKey {
        case version
        case source
        case sourceSHA256 = "source_sha256"
        case maxTags = "max_tags"
        case targetRange = "target_range"
        case groups
        case canonical
    }

    var canonicalSet: Set<String> { Set(canonical) }

    func isCanonical(_ tag: String) -> Bool {
        canonicalSet.contains(Tag.canonicalize(tag))
    }

    static func load(from bundle: Bundle = .main) throws -> TagVocabulary {
        guard let url = bundle.url(forResource: "tag-vocabulary", withExtension: "json") else {
            throw AppError.organizerInvalidOutput("找不到 tag-vocabulary.json 資源")
        }
        return try JSONDecoder().decode(TagVocabulary.self, from: Data(contentsOf: url))
    }
}
