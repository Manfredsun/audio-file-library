import Foundation

/// Display-only aliases. Canonical values remain the input to filters, writes and naming.
enum BuiltinNames {
    private static let categories = (try? Taxonomy.load().allPaths) ?? []
    private static let styles = (try? StyleVocabulary.load().styles) ?? []
    private static let textures = (try? TextureVocabulary.load().textures) ?? []

    static func category(_ path: String, locale: String = L10n.language, leafOnly: Bool = false) -> String {
        guard categories.contains(path) else { return path }
        if locale == "en" { return leafOnly ? String(path.split(separator: "/").last ?? Substring(path)) : path }
        if leafOnly || !path.contains("/") { return L10n.tr("category." + path, locale: locale) }
        let top = String(path.split(separator: "/")[0])
        return L10n.tr("category." + top, locale: locale) + "／" + L10n.tr("category." + path, locale: locale)
    }
    static func style(_ value: String, locale: String = L10n.language) -> String {
        styles.contains(value) ? L10n.tr("style." + value, locale: locale) : value
    }
    static func texture(_ value: String, locale: String = L10n.language) -> String {
        textures.contains(value) ? L10n.tr("texture." + value, locale: locale) : value
    }
    struct Matches {
        var categories: [String]
        var styles: [String]
        var textures: [String]
    }
    private struct Alias {
        let canonical: String
        let searchable: [String]
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static let categoryAliases = categories.map { value in
        Alias(canonical: value, searchable: [normalized(value), normalized(category(value, locale: "zh-Hant"))])
    }
    private static let styleAliases = styles.map { value in
        Alias(canonical: value, searchable: [normalized(value), normalized(style(value, locale: "zh-Hant"))])
    }
    private static let textureAliases = textures.map { value in
        Alias(canonical: value, searchable: [normalized(value), normalized(texture(value, locale: "zh-Hant"))])
    }
    static func matching(_ term: String) -> Matches {
        let value = normalized(term)
        func find(_ aliases: [Alias]) -> [String] {
            guard !value.isEmpty else { return [] }
            return aliases.filter { $0.searchable.contains { $0.contains(value) } }.map(\.canonical)
        }
        return Matches(categories: find(categoryAliases), styles: find(styleAliases), textures: find(textureAliases))
    }
}
