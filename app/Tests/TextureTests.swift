import XCTest
@testable import FoleyLibrary

/// 材質讀取。**字面題，不是聲學題。**
///
/// 塑膠與木頭在頻譜上沒有可靠的分界。宣稱聽得出來的系統就是在做 D-013
/// 記錄的那件事。但錄音的人需要事後找得到素材，所以材質幾乎都寫在檔名裡。
final class TextureTests: XCTestCase {

    private var vocabulary: TextureVocabulary!

    override func setUpWithError() throws {
        vocabulary = try TestSupport.textures()
    }

    private func read(_ path: String, category: String? = nil) -> TextureReader.Match? {
        TextureReader.read(relativePath: path,
                           filename: (path as NSString).lastPathComponent,
                           vocabulary: vocabulary,
                           category: category)
    }

    // MARK: - 真實檔名

    func testMaterialInTheFilename() {
        XCTAssertEqual(read("Foley/Bare_Feet_Metal_SLOW_MED_WALK.wav")?.texture, "Metal")
        XCTAssertEqual(read("Foley/Plastic_Creak_Bottle_File_2_Takes_7.wav")?.texture, "Plastic")
    }

    func testMaterialInTheFolder() {
        let match = read("SFX/Wood Impacts/hit_03.wav")
        XCTAssertEqual(match?.texture, "Wood")
        XCTAssertTrue(match?.fromFolder == true, "資料夾比檔名可信")
    }

    func testChineseIsMatchedAsASubstring() {
        // 中文沒有詞界，只能用 contains（D-023）。
        XCTAssertEqual(read("46-音频音效/金屬撞擊聲.wav")?.texture, "Metal")
        XCTAssertEqual(read("46-音频音效/木门开关.wav")?.texture, "Wood")
        XCTAssertEqual(read("46-音频音效/玻璃破碎.wav")?.texture, "Glass")
    }

    func testSimplifiedAndTraditionalBothWork() {
        XCTAssertEqual(read("a/塑膠袋.wav")?.texture, "Plastic")
        XCTAssertEqual(read("a/塑料袋.wav")?.texture, "Plastic")
    }

    func testNoTextureTermLeavesItEmpty() {
        // 留空是合法狀態。猜一個比留空更糟——事後分辨不出哪些是讀到的、哪些是編的。
        XCTAssertNil(read("Ambience/city_street_evening.wav"))
    }

    // MARK: - 詞界

    func testEnglishUsesWordBoundariesNotSubstrings() {
        // tin 不可以命中 painting，ice 不可以命中 service。
        XCTAssertNil(read("Foley/painting_brush_strokes.wav"))
        XCTAssertNil(read("Ambience/service_station_ambience.wav"))
    }

    func testPluralsStillMatch() {
        XCTAssertEqual(read("Foley/glass_bottles_clink.wav")?.texture, "Glass")
    }

    // MARK: - 材質贏過表面詞

    func testAMaterialBeatsASurfaceTerm() {
        // 路徑上同時有 soft 與 cloth 時，材質比較具體。
        let match = read("Foley/soft_cloth_movement.wav")
        XCTAssertEqual(match?.texture, "Cloth")
        XCTAssertFalse(match?.isSurface == true)
    }

    func testASurfaceTermIsUsedWhenThereIsNoMaterial() {
        let match = read("Foley/hard_impact_short.wav")
        XCTAssertEqual(match?.texture, "Hard")
        XCTAssertTrue(match?.isSurface == true, "表面詞的證據力比較弱，要標記出來")
    }

    func testAMaterialInTheFilenameBeatsASurfaceTermInTheFolder() {
        // 材質優先於表面詞，這條比「資料夾優先於檔名」更強。
        XCTAssertEqual(read("Soft Textures/metal_scrape_01.wav")?.texture, "Metal")
    }

    // MARK: - 跟曲風撞名（D-020 的鏡像）

    func testMetalIsGenreNotMaterialInsideDrums() {
        // 一個字不能同時當兩個欄位的證據。在 Drums/ 底下 metal 由風格認領。
        XCTAssertNil(read("Drum Machines/TS_HMD_kick_metal.wav", category: "Drums/Kick"))
    }

    func testMetalIsMaterialOutsideProductionCategories() {
        XCTAssertEqual(read("Foley/metal_door_slam.wav", category: "Foley/Doors")?.texture, "Metal")
    }

    func testRockIsStoneOutsideProductionCategoriesAndNothingInside() {
        XCTAssertEqual(read("Nature/rock_slide_02.wav", category: "Nature")?.texture, "Stone")
        XCTAssertNil(read("Instruments/rock_guitar_riff.wav", category: "Instruments/Guitar"))
    }

    // MARK: - 兩個材質詞

    func testWhenTwoMaterialsAppearTheLongerTermWins() {
        // `rock_slide_gravel` 同時有 rock 與 gravel。這種情況沒有「正確答案」，
        // 所以規則是**固定的**而不是聰明的：比對順序長的在前，結果可重現。
        // 這一條釘著的是可重現性，不是正確性——真的標錯就人工改。
        XCTAssertEqual(read("Nature/rock_slide_gravel.wav", category: "Nature")?.texture, "Gravel")
    }

    func testAnUnknownCategoryIsTreatedAsNotProduction() {
        // 分類不明時偏向把 metal 當材質——在 Foley 庫裡那是絕大多數的情況。
        XCTAssertEqual(read("unsorted/metal_hit.wav")?.texture, "Metal")
    }

    // MARK: - 詞彙表本身

    func testEveryAliasMapsToAValidTexture() {
        for (alias, texture) in vocabulary.aliases {
            XCTAssertTrue(vocabulary.isValid(texture),
                          "\(alias) 指向白名單以外的材質：\(texture)")
        }
    }

    func testSurfaceTermsAreAlsoInTheWhitelist() {
        for term in vocabulary.surface {
            XCTAssertTrue(vocabulary.isValid(term), "\(term) 不在白名單裡")
        }
    }

    func testTheTermThatMatchedIsReportedSoTheUserCanCheckIt() {
        // 審核介面要能說明「因為檔名裡有 metal」，否則使用者只能選擇相信。
        XCTAssertEqual(read("Foley/metal_door_slam.wav")?.term, "metal")
    }
}

/// 材質屬於**主分析流程**，不是另一顆要記得去按的按鈕。
///
/// M36 一開始把材質做成獨立的一層，結果使用者重新分析了全庫（68,629 筆），
/// 材質仍然是 0——欄位存在、UI 碰得到、但主管線不填它。
/// 這是 D-026 的第三次變形，測試釘在這裡。
final class TextureInAnalysisTests: XCTestCase {

    private func engine() throws -> LocalAnalysisEngine {
        LocalAnalysisEngine(taxonomy: try TestSupport.taxonomy(),
                            vocabulary: try TestSupport.vocabulary(),
                            styles: try TestSupport.styles(),
                            textures: try TestSupport.textures(),
                            // 音訊量測給一份固定的假資料：這組測試驗的是材質有沒有
                            // 跟著分析結果出來，不是量測本身。
                            measure: { _ in
                                AcousticFeatures(duration: 1, sampleRate: 44_100, channelCount: 2,
                                                 peak: 0.8, rms: 0.2, crestFactor: 4,
                                                 attackTime: 0.005, decayTime: 0.2, sustainRatio: 0.1,
                                                 zeroCrossingRate: 0.1, spectralCentroid: 2000,
                                                 spectralRolloff: 4000, spectralFlatness: 0.2,
                                                 lowEnergyRatio: 0.3, midEnergyRatio: 0.4,
                                                 highEnergyRatio: 0.3, centroidSlope: 0,
                                                 onsetCount: 1, leadingSilence: 0, trailingSilence: 0,
                                                 tempo: nil, tempoConfidence: 0, isLoopLike: false)
                            })
    }

    private func analyse(_ relativePath: String) async throws -> OrganizerResult {
        try await engine().analyze(OrganizerRequest(
            soundId: 1,
            audioURL: URL(fileURLWithPath: "/tmp/\(relativePath)"),
            filename: (relativePath as NSString).lastPathComponent,
            relativePath: relativePath,
            fileFormat: "wav"))
    }

    func testAnalysisProducesTheTexture() async throws {
        let result = try await analyse("Foley/Doors/metal_door_slam.wav")
        XCTAssertEqual(result.texture, "Metal", "重新分析要能填上材質，不必另外按一顆按鈕")
    }

    func testAnalysisLeavesTextureEmptyWhenThePathSaysNothing() async throws {
        let result = try await analyse("Ambience/city_street_evening.wav")
        XCTAssertNil(result.texture)
    }

    func testTheSummaryExplainsWhereTheTextureCameFrom() async throws {
        // 使用者要能看出「因為檔名裡有 metal」，否則他只能選擇相信。
        let result = try await analyse("Foley/Doors/metal_door_slam.wav")
        XCTAssertTrue(result.summary?.contains("材質線索") == true)
    }
}
