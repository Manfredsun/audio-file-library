import XCTest
@testable import FoleyLibrary

/// 中文音效庫的規則。
///
/// 測試裡的路徑全部取自使用者真實的 `46-音频音效` 庫（28,176 個檔案）。
/// 補中文之前那一庫只有 21% 拿到分類，因為規則表整張都是英文的。
final class ChineseRuleTests: XCTestCase {

    private var taxonomy: Taxonomy!
    private var vocabulary: TagVocabulary!

    override func setUpWithError() throws {
        taxonomy = try TestSupport.taxonomy()
        vocabulary = try TestSupport.vocabulary()
    }

    private func category(_ path: String) -> String? {
        PathEvidenceReader.read(relativePath: path,
                                filename: (path as NSString).lastPathComponent,
                                taxonomy: taxonomy,
                                vocabulary: vocabulary).category
    }

    // MARK: - 比對方式

    func testChineseMatchesAsSubstringBecauseThereAreNoWordBoundaries() {
        // 「军事爆破」normalise 之後是一整個 token，詞界比對永遠對不上。
        XCTAssertEqual(category("91+[超实用音效素材]第1部分/军事爆破/b12.wav"), "Impacts/Generic")
    }

    func testEnglishStillUsesWordBoundaries() {
        // 中文改成子字串，不能連帶把英文也變成子字串。
        XCTAssertNil(category("Popcorn Kitchen/kernel.wav"), "pop 不得命中 popcorn")
    }

    func testCJKDetection() {
        XCTAssertTrue(PathEvidenceReader.containsCJK("爆破"))
        XCTAssertTrue(PathEvidenceReader.containsCJK("水声 water"))
        XCTAssertFalse(PathEvidenceReader.containsCJK("whoosh"))
        XCTAssertFalse(PathEvidenceReader.containsCJK("808"))
    }

    // MARK: - 真實路徑

    func testRealPathsFromTheLibrary() {
        XCTAssertEqual(category("1200种音效素材/1200种音效素材/常用音效/Y音效/鼓掌.WAV"),
                       "Human/Cheer")
        XCTAssertEqual(category("2013年8月整理音效合集/自然风光/12 飞越彩虹.mp3"),
                       "Nature")
        XCTAssertEqual(category("91+[超实用音效素材]第2部分/光效音/光音效/光7.mp3"),
                       "Designed/Whoosh")
        XCTAssertEqual(category("91+[超实用音效素材]第2部分/电子机器设备/按钮/B1/SND387.WAV"),
                       "UI/Click",
                       "按钮 是葉資料夾，比上層的「电子机器设备」具體")
        XCTAssertEqual(category("9月份音效合集/交通工具/汽车/刹车.wav"), "Vehicles/Car")
        XCTAssertEqual(category("索尼媒体音效素材/动物/多种鸟类的叫声/bird_03.wav"),
                       "Animals/Bird")
    }

    func testTraditionalAndSimplifiedBothWork() {
        XCTAssertEqual(category("音效庫/腳步聲/木地板 01.wav"), "Foley/Footsteps")
        XCTAssertEqual(category("音效库/脚步声/木地板 01.wav"), "Foley/Footsteps")
        XCTAssertEqual(category("音效庫/開門/大門 02.wav"), "Foley/Doors")
        XCTAssertEqual(category("音效库/开门/大门 02.wav"), "Foley/Doors")
    }

    // MARK: - 短詞的風險

    func testOverlappingTermsInOneRuleCountOnce() {
        // 「电子机器设备」同時命中 "电子机器设备" 與 "电子"。兩個都算的話這條規則
        // 就有兩分，會壓過命中「按钮」的 UI/Click——但那只是同一件事被數了兩次。
        XCTAssertEqual(category("电子机器设备/按钮/B1/SND387.WAV"), "UI/Click")
    }

    func testSpecificTermsBeatGenericOnesOnATie() {
        // 「风扇」含有「风」。電風扇不是自然風聲，具體的規則必須贏。
        XCTAssertEqual(category("电子机器设备/风扇/fan_01.wav"), "Machines/Fan")
        XCTAssertEqual(category("自然/风声/wind_01.wav"), "Nature/Wind")
    }

    func testAcousticGuitarIsNotWoodImpact() {
        // 「木吉他」含有「木」。規則表刻意不收單字的「木」。
        XCTAssertEqual(category("乐器/木吉他/G_01.wav"), "Instruments/Guitar")
        XCTAssertEqual(category("碰撞/木头/wood_01.wav"), "Impacts/Wood")
    }

    func testRadarIsNotThunder() {
        // 「雷达」含有「雷」。
        XCTAssertEqual(category("军事/雷达/radar_01.wav"), "Machines/Electronics")
        XCTAssertEqual(category("自然/雷电/thunder_01.wav"), "Nature/Thunder")
    }

    // MARK: - 包裝用語不得成為規則

    func testPackagingWordsAreNotRules() {
        // 「音效素材」「精选」「最实用」「更多选择」這類是包裝用語不是內容。
        // 把它們寫進規則表會讓幾千個檔案一起歸錯類。
        let packaging = ["超实用音效素材", "精选音效", "最实用", "更多选择",
                         "音效大全箱", "顶级音效素材库", "音效合集", "个音频素材"]
        for word in packaging {
            for rule in PathEvidenceReader.chineseRules {
                XCTAssertFalse(rule.terms.contains(word),
                               "包裝用語 \(word) 不該出現在規則表裡")
            }
        }
    }

    func testAPathOfOnlyPackagingWordsStaysUnclassified() {
        XCTAssertNil(category("91+[超实用音效素材]第2部分/更多选择/其他的/84.WAV"))
    }

    // MARK: - 規則表本身

    func testEveryChineseRuleMapsToAValidTaxonomyPath() {
        for rule in PathEvidenceReader.chineseRules {
            XCTAssertTrue(taxonomy.isValidPath(rule.category),
                          "規則指向不存在的分類：\(rule.category)")
        }
    }

    func testChineseRulesAreActuallyChinese() {
        for rule in PathEvidenceReader.chineseRules {
            for term in rule.terms {
                XCTAssertTrue(PathEvidenceReader.containsCJK(term),
                              "\(term) 不是中文，應該放在 englishRules")
            }
        }
    }
}
