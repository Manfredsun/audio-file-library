import XCTest
@testable import FoleyLibrary

/// 命名慣例的偵測與 descriptor 抽取。
///
/// 所有檔名都取自使用者真實的庫。這一層原本規劃要交給 Antigravity（D-017），
/// 實際動手才發現絕大部分規則解得掉——照 AGENTS.md §60 的判準，
/// 寫得出確定性規則的就不該給 AI 做。
final class NamingConventionTests: XCTestCase {

    private var roleTerms: Set<String> = []
    private var styleTerms: Set<String> = []

    override func setUpWithError() throws {
        roleTerms = NamingConventionDetector.roleTerms(from: PathEvidenceReader.rules)
        styleTerms = NamingConventionDetector.styleTerms(from: try TestSupport.styles())
    }

    private func detect(_ filenames: [String]) -> (NamingConvention, [String: String]) {
        NamingConventionDetector.detect(filenames: filenames,
                                        roleTerms: roleTerms,
                                        styleTerms: styleTerms)
    }

    private func descriptor(_ filename: String, in group: [String]) -> String? {
        detect(group).1[filename]
    }

    // MARK: - 共同前綴

    func testCommonPrefixIsFoundByWordNotByCharacter() {
        let group = ["AU_FP_kick_one_shot_dirt.wav",
                     "AU_FP_snare_one_shot_crisp.wav",
                     "AU_FP_hat_one_shot_tight.wav",
                     "AU_FP_clap_one_shot_wide.wav"]
        let (convention, _) = detect(group)
        XCTAssertEqual(convention.prefix, "AU_FP")
    }

    func testCharacterLevelCoincidencesAreNotTreatedAsAPrefix() {
        // snare 與 snake 的字元共同前綴是 "sna"，那是巧合不是慣例。
        let group = ["snare_1.wav", "snake_2.wav", "snap_3.wav", "snail_4.wav"]
        let (convention, _) = detect(group)
        XCTAssertEqual(convention.prefix, "")
    }

    func testPrefixNeverSwallowsTheWholeFilename() {
        // 全部一模一樣時，前綴不可以吃掉整個檔名，否則沒有東西能分辨檔案。
        let group = ["kick_hard.wav", "kick_hard.wav", "kick_hard.wav", "kick_hard.wav"]
        let (convention, _) = detect(group)
        XCTAssertNotEqual(convention.prefix, "kick_hard")
    }

    func testTooSmallAGroupHasNoConvention() {
        let (convention, _) = detect(["AU_FP_kick.wav", "AU_FP_snare.wav"])
        XCTAssertEqual(convention.prefix, "")
        XCTAssertEqual(convention.coverage, 0)
    }

    // MARK: - descriptor 抽取（真實檔名）

    func testVendorPrefixAndRoleWordAreStripped() {
        let group = ["AU_FP_kick_one_shot_dirt.wav",
                     "AU_FP_snare_one_shot_crisp.wav",
                     "AU_FP_hat_one_shot_tight.wav",
                     "AU_FP_clap_one_shot_wide.wav"]
        XCTAssertEqual(descriptor("AU_FP_kick_one_shot_dirt.wav", in: group), "dirt")
        XCTAssertEqual(descriptor("AU_FP_snare_one_shot_crisp.wav", in: group), "crisp")
    }

    func testTimbreWordSurvives() {
        let group = ["SD_Snare_WoodBlock.wav", "SD_Snare_SaySo.wav",
                     "SD_Kick_RoundThud.wav", "SD_Perc_Treat.wav"]
        XCTAssertEqual(descriptor("SD_Snare_WoodBlock.wav", in: group), "WoodBlock")
        XCTAssertEqual(descriptor("SD_Kick_RoundThud.wav", in: group), "RoundThud")
    }

    func testNumbersAndKeysAndStylesAreStripped() {
        let group = ["Cymatics - Lofi Snare 2 - C#.wav",
                     "Cymatics - Lofi Kick 7 - E.wav",
                     "Cymatics - Lofi Open Hihat 3.wav",
                     "Cymatics - Lofi Clap 1.wav"]
        // Cymatics（前綴）、Lofi（風格）、Snare（角色）、2（編號）、C#（調性）全部扣掉
        XCTAssertNil(descriptor("Cymatics - Lofi Snare 2 - C#.wav", in: group),
                     "全部都是可扣掉的成分時，descriptor 是空的——不要拿編號充數")
    }

    func testPureNumberingYieldsNoDescriptor() {
        let group = ["FTH_Kick_19.wav", "FTH_Kick_20.wav", "FTH_Kick_21.wav", "FTH_Kick_22.wav"]
        XCTAssertNil(descriptor("FTH_Kick_19.wav", in: group))
    }

    func testShortVendorCodesAreNotDescriptors() {
        // 一兩個字母的殘渣多半是廠商代號。
        let group = ["ct_snr_ab.wav", "ct_snr_cd.wav", "ct_snr_ef.wav", "ct_snr_gh.wav"]
        XCTAssertNil(descriptor("ct_snr_ab.wav", in: group))
    }

    func testMeaninglessButLongCodesAreKept() {
        // "gunta" 對我們沒有意義，但它是廠商放進去的字，不是編號也不是角色。
        // 判斷它有沒有意義需要世界知識——那才是 AI 該碰的地方。
        let group = ["ct_snr_gunta.wav", "ct_snr_hennessy.wav",
                     "ct_snr_hostel.wav", "ct_snr_arise.wav"]
        XCTAssertEqual(descriptor("ct_snr_gunta.wav", in: group), "gunta")
    }

    // MARK: - 覆蓋率

    func testCoverageReportsHowMuchWasExtracted() {
        let group = ["FTH_Kick_19.wav", "FTH_Kick_20.wav",
                     "FTH_Kick_dusty.wav", "FTH_Kick_punchy.wav"]
        let (convention, descriptors) = detect(group)
        XCTAssertEqual(descriptors.count, 2)
        XCTAssertEqual(convention.coverage, 0.5, accuracy: 0.01)
        XCTAssertEqual(convention.fileCount, 4)
    }

    func testEverythingExtractedGivesFullCoverage() {
        let group = ["SD_Snare_WoodBlock.wav", "SD_Snare_SaySo.wav",
                     "SD_Kick_RoundThud.wav", "SD_Perc_Treat.wav"]
        XCTAssertEqual(detect(group).0.coverage, 1.0, accuracy: 0.01)
    }

    // MARK: - 抽取式的硬約束（D-017）

    func testEveryDescriptorWordAppearsInTheOriginalFilename() {
        // 這是 D-017 的核心約束：descriptor 必須是原檔名裡出現過的字。
        // 本機這一層天生滿足它（我們只做刪除不做生成），但還是要有測試釘住——
        // 之後接上 AI 補這一格時，這條檢查就是唯一的保險。
        let groups = [
            ["AU_FP_kick_one_shot_dirt.wav", "AU_FP_snare_one_shot_crisp.wav",
             "AU_FP_hat_one_shot_tight.wav", "AU_FP_clap_one_shot_wide.wav"],
            ["SD_Snare_WoodBlock.wav", "SD_Snare_SaySo.wav",
             "SD_Kick_RoundThud.wav", "SD_Perc_Treat.wav"],
            ["ct_snr_gunta.wav", "ct_snr_hennessy.wav",
             "ct_snr_hostel.wav", "ct_snr_arise.wav"],
        ]
        for group in groups {
            let (_, descriptors) = detect(group)
            for (filename, descriptor) in descriptors {
                let source = filename.lowercased()
                for word in descriptor.lowercased().split(separator: " ") {
                    XCTAssertTrue(source.contains(word),
                                  "\(filename) 的 descriptor 含有來源裡沒有的字：\(word)")
                }
            }
        }
    }

    func testRoleWordInThePrefixStillLeavesLaterRoleWordsAsTimbre() {
        // 角色（Kick）被收進共同前綴，後面的 woodblock 描述的是音色。
        let group = ["FTH_Kick_WoodBlock.wav", "FTH_Kick_Dusty.wav",
                     "FTH_Kick_Punchy.wav", "FTH_Kick_19.wav"]
        XCTAssertEqual(descriptor("FTH_Kick_WoodBlock.wav", in: group), "WoodBlock")
    }

    func testTheOnlyRoleWordIsStillStripped() {
        // 只有一個角色詞時它就是角色，不是音色——抽不出東西就回 nil。
        let group = ["Pack_Snare_01.wav", "Pack_Kick_02.wav",
                     "Pack_Clap_03.wav", "Pack_Hat_04.wav"]
        XCTAssertNil(descriptor("Pack_Snare_01.wav", in: group))
    }

    // MARK: - 真實庫量測抓出來的問題（docs/naming-coverage.txt）

    func testVendorNameIsStrippedEvenWhenItIsNotAPositionalPrefix() {
        // 資料夾裡混了別的東西，Cymatics 就不在第 0 個位置，嚴格前綴抓不到它。
        // 但它出現在幾乎每個檔名裡——那不是在描述聲音。
        let group = ["Cymatics - Lofi Top Loop 1 - 70 BPM.wav",
                     "Cymatics - Lofi Dusty Perc 2.wav",
                     "Intro - Cymatics Gritty Bass.wav",
                     "Cymatics - Lofi Warm Keys 4.wav"]
        XCTAssertEqual(descriptor("Cymatics - Lofi Top Loop 1 - 70 BPM.wav", in: group), nil)
        XCTAssertEqual(descriptor("Cymatics - Lofi Dusty Perc 2.wav", in: group), "Dusty")
    }

    func testNumberedGenericWordsAreStripped() {
        // Track01 是 track，Effect1 是 effect——兩個都是通用詞。
        let group = ["Track01.mp3", "Track02.mp3", "Effect1.wav", "Effect2.wav"]
        XCTAssertNil(descriptor("Track01.mp3", in: group))
        XCTAssertNil(descriptor("Effect1.wav", in: group))
    }

    func testStemOnlyStripsDigitsWhenAWordRemains() {
        XCTAssertEqual(NamingConventionDetector.stem(of: "Track01"), "Track")
        XCTAssertEqual(NamingConventionDetector.stem(of: "86BPM"), "BPM")
        // ak47 去掉數字只剩 ak，那不是詞——保留原樣，它才是描述。
        XCTAssertEqual(NamingConventionDetector.stem(of: "ak47"), "ak47")
    }

    func testDescriptorIsCappedSoItStaysAName() {
        // 整句話的檔名是紀錄不是名字，全塞進去只會得到另一個一樣難讀的檔名。
        let group = ["Hellcat_onboard_startup_idle_steady_ramps_throttle_shutdown_cockpit.wav",
                     "Hellcat_onboard_taxi_slow_gentle_turns_cockpit.wav",
                     "Hellcat_flyby_fast_low_distant_exterior.wav",
                     "Hellcat_landing_rough_bounce_exterior.wav"]
        let value = descriptor("Hellcat_onboard_startup_idle_steady_ramps_throttle_shutdown_cockpit.wav",
                               in: group)
        XCTAssertEqual(value?.split(separator: " ").count,
                       NamingConventionDetector.maximumDescriptorWords)
    }

    // MARK: - 詞表本身

    func testRoleTermsAreDerivedFromTheRuleTable() {
        XCTAssertTrue(roleTerms.contains("kick"))
        XCTAssertTrue(roleTerms.contains("snare"))
        XCTAssertTrue(roleTerms.contains("whoosh"))
        XCTAssertFalse(roleTerms.contains("爆破"), "中文詞不該混進英文 descriptor 的過濾表")
    }

    func testStyleTermsCoverAliasesAndCanonicalNames() {
        XCTAssertTrue(styleTerms.contains("lofi"))
        XCTAssertTrue(styleTerms.contains("boom"))
        XCTAssertTrue(styleTerms.contains("chiptune"))
    }
}
