import XCTest
@testable import FoleyLibrary

@MainActor
final class AppPreferencesTests: XCTestCase {
    private func fixture() -> (UserDefaults, String) {
        let domain = "ui-preferences-tests." + UUID().uuidString
        return (UserDefaults(suiteName: domain)!, domain)
    }

    func testDefaultsFollowSystemWithoutWritingLanguageOverride() {
        let (defaults, domain) = fixture()
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = AppPreferences(defaults: defaults, domain: domain, appliesAppearance: false)
        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertEqual(preferences.language, .system)
        XCTAssertNil(defaults.persistentDomain(forName: domain)?["AppleLanguages"])
    }

    func testAppearancePersistsWithoutReplacingLanguageOrOtherPreferences() {
        let (defaults, domain) = fixture()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("keep", forKey: "unrelated")
        let preferences = AppPreferences(defaults: defaults, domain: domain, appliesAppearance: false)
        preferences.appearance = .light
        preferences.language = .traditionalChinese
        let reopened = AppPreferences(defaults: defaults, domain: domain, appliesAppearance: false)
        XCTAssertEqual(reopened.appearance, .light)
        XCTAssertEqual(reopened.language, .traditionalChinese)
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
        preferences.appearance = .dark
        XCTAssertEqual(defaults.string(forKey: "appearance"), "dark")
    }

    func testLanguageOnlyChangesAppDomainAndKeepsActiveLanguageUntilRelaunch() {
        let (defaults, domain) = fixture()
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = AppPreferences(defaults: defaults, domain: domain, appliesAppearance: false)
        let active = preferences.activeLanguage
        preferences.language = .english
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en"])
        XCTAssertEqual(preferences.activeLanguage, active)
        preferences.language = .system
        XCTAssertNil(defaults.persistentDomain(forName: domain)?["AppleLanguages"])
    }

    func testLanguageResolutionUsesSupportedPreferenceAndEnglishFallback() {
        XCTAssertEqual(AppLanguage.resolve(["fr-FR", "zh-Hant-TW", "en"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolve(["en-GB", "zh-Hant"]), .english)
        XCTAssertEqual(AppLanguage.resolve(["ja-JP"]), .english)
        XCTAssertEqual(AppLanguage.resolve(["zh-Hans-CN", "en-US"]), .english)
        XCTAssertEqual(AppLanguage.resolve([]), .english)
    }

    func testInvalidStoredAppearanceFallsBackWithoutChangingOtherData() {
        let (defaults, domain) = fixture()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("invalid", forKey: "appearance")
        XCTAssertEqual(AppPreferences(defaults: defaults, domain: domain, appliesAppearance: false).appearance, .system)
    }
}
