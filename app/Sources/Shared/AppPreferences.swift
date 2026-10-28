import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .light ? .light : .dark) }
    var title: String {
        switch self {
        case .system: return L10n.tr("跟隨系統")
        case .light: return L10n.tr("淺色")
        case .dark: return L10n.tr("深色")
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, traditionalChinese = "zh-Hant", english = "en"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return L10n.tr("跟隨系統")
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        }
    }
    static func resolve(_ languages: [String]) -> AppLanguage {
        for value in languages {
            if value == "zh-Hant" || value.hasPrefix("zh-Hant-") || ["zh-TW", "zh-HK", "zh-MO"].contains(value) { return .traditionalChinese }
            if value == "en" || value.hasPrefix("en-") { return .english }
        }
        return .english
    }
}

/// Preferences are app-scoped. No service, library, playback or database is rebuilt.
@MainActor
final class AppPreferences: ObservableObject {
    private let defaults: UserDefaults
    private let appliesAppearance: Bool
    private let systemLanguages: [String]
    let activeLanguage: AppLanguage
    @Published var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            if appliesAppearance { applyAppearance() }
        }
    }
    @Published var language: AppLanguage {
        didSet {
            // The app domain overrides the system preference only on the next launch.
            if language == .system { defaults.removeObject(forKey: "AppleLanguages") }
            else { defaults.set([language.rawValue], forKey: "AppleLanguages") }
        }
    }
    var languageChangePending: Bool {
        let resolved = language == .system ? AppLanguage.resolve(systemLanguages) : language
        return resolved != activeLanguage
    }
    init(defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? "com.manfredsun.foleylibrary", appliesAppearance: Bool = true) {
        systemLanguages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String] ?? Locale.preferredLanguages
        self.defaults = defaults
        self.appliesAppearance = appliesAppearance && ProcessInfo.processInfo.environment["FOLEY_TEST_HOST"] != "1"
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        let override = defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String]
        language = override.map(AppLanguage.resolve) ?? .system
        activeLanguage = AppLanguage.resolve(Bundle.main.preferredLocalizations)
    }
    func applyAppearance() {
        NSApp?.appearance = appearance == .system ? nil : NSAppearance(named: appearance == .light ? .aqua : .darkAqua)
    }
}
