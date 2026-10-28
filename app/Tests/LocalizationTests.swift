import XCTest
import AppKit
@testable import FoleyLibrary

final class LocalizationTests: XCTestCase {
    func testBothLanguagesTranslateActionsAndInterpolatedMessages() {
        XCTAssertEqual(L10n.tr("加入音色庫", locale: "en"), "Add Library")
        XCTAssertEqual(L10n.tr("加入音色庫", locale: "zh-Hant"), "加入音色庫")
        XCTAssertEqual(L10n.tr("分析中 %@/%@", "2", "5", locale: "en"), "Analyzing 2/5")
        XCTAssertEqual(L10n.tr("分析中 %@/%@", "2", "5", locale: "zh-Hant"), "分析中 2/5")
        XCTAssertEqual(L10n.tr("加入音色庫", locale: "xx"), "Add Library")
    }

    func testCountsHaveEnglishSingularAndPluralAndChineseCount() {
        XCTAssertEqual(L10n.sounds(1, locale: "en"), "1 sound")
        XCTAssertEqual(L10n.sounds(2, locale: "en"), "2 sounds")
        XCTAssertEqual(L10n.sounds(0, locale: "en"), "0 sounds")
        XCTAssertEqual(L10n.sounds(2, locale: "zh-Hant"), "2 個音效")
    }

    func testProgressUsesNativeSingularAndPluralRules() {
        let single = BatchAnalysisProgress(phase: .finished, total: 1, completed: 1, failed: 1, needsReview: 1)
        XCTAssertEqual(single.summary(locale: "en"), "Completed 1 item, 1 needs review, 1 read failure")
        let plural = BatchAnalysisProgress(phase: .finished, total: 2, completed: 2, failed: 2, needsReview: 2)
        XCTAssertEqual(plural.summary(locale: "en"), "Completed 2 items, 2 need review, 2 read failures")
        XCTAssertEqual(single.summary(locale: "zh-Hant"), "完成 1 個，其中 1 個待複查，1 個讀取失敗")
    }

    func testBuiltInNamesTranslateWithoutChangingCanonicalInputs() {
        let value = "Foley/Doors"
        XCTAssertEqual(BuiltinNames.category(value, locale: "zh-Hant"), "擬音／門")
        XCTAssertEqual(BuiltinNames.category(value, locale: "en"), value)
        XCTAssertEqual(value, "Foley/Doors")
        XCTAssertEqual(BuiltinNames.style("Hip Hop", locale: "zh-Hant"), "嘻哈（Hip Hop）")
        XCTAssertEqual(BuiltinNames.texture("Metal", locale: "zh-Hant"), "金屬")
        XCTAssertEqual(BuiltinNames.category("Custom/Value", locale: "zh-Hant"), "Custom/Value")
    }

    func testVocabularyTranslationsCoverAllControlledValues() throws {
        for path in try Taxonomy.load().allPaths {
            XCTAssertFalse(BuiltinNames.category(path, locale: "zh-Hant").isEmpty)
            XCTAssertNotEqual(L10n.tr("category." + path, locale: "zh-Hant"), "category." + path)
        }
        for style in try StyleVocabulary.load().styles {
            XCTAssertNotEqual(L10n.tr("style." + style, locale: "zh-Hant"), "style." + style)
        }
        for texture in try TextureVocabulary.load().textures {
            XCTAssertNotEqual(L10n.tr("texture." + texture, locale: "zh-Hant"), "texture." + texture)
        }
    }

    func testSmallTextHasReadableContrastInBothAppearances() throws {
        func rgb(_ color: NSColor, _ name: NSAppearance.Name) throws -> [Double] {
            var resolved: NSColor?
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(.sRGB)
            }
            let value = try XCTUnwrap(resolved)
            return [value.redComponent, value.greenComponent, value.blueComponent].map(Double.init)
        }
        func luminance(_ rgb: [Double]) -> Double {
            let c = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return c[0]*0.2126 + c[1]*0.7152 + c[2]*0.0722
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let background = luminance(try rgb(NSColor(DS.Palette.sumi), appearance))
            for color in [DS.Palette.textPrimary, DS.Palette.textSecondary, DS.Palette.textTertiary] {
                let foreground = luminance(try rgb(NSColor(color), appearance))
                XCTAssertGreaterThanOrEqual((max(background, foreground)+0.05)/(min(background, foreground)+0.05), 4.5)
            }
        }
    }
}
