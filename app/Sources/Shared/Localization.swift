import Foundation

/// The active language is fixed at launch, just like AppKit's menus and panels.
enum L10n {
    static let language = AppLanguage.resolve(Bundle.main.preferredLocalizations).rawValue
    private static let bundles: [String: Bundle] = {
        var result: [String: Bundle] = [:]
        for code in ["en", "zh-Hant"] {
            if let url = Bundle.main.url(forResource: code, withExtension: "lproj"),
               let bundle = Bundle(url: url) { result[code] = bundle }
        }
        return result
    }()
    static func tr(_ key: String, _ arguments: CVarArg..., locale: String? = nil) -> String {
        let code = locale ?? language
        let bundle = bundles[code] ?? bundles["en"] ?? .main
        let format = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: code), arguments: arguments)
    }
    static func files(_ count: Int, locale: String? = nil) -> String {
        tr("count.files", count, locale: locale)
    }
    static func sounds(_ count: Int, locale: String? = nil) -> String {
        tr("count.sounds", count, locale: locale)
    }
}
