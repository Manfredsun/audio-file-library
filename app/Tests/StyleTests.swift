import XCTest
@testable import FoleyLibrary

/// 風格的來源、比對規則與白名單約束。
///
/// 最重要的一條是最後那組：**沒有線索時必須留空。**
/// 一個猜錯的風格標籤比沒有標籤更糟，因為事後分辨不出哪些是讀到的、哪些是編的。
final class StyleTests: XCTestCase {

    private var styles: StyleVocabulary!
    private var taxonomy: Taxonomy!
    private var vocabulary: TagVocabulary!

    override func setUpWithError() throws {
        styles = try TestSupport.styles()
        taxonomy = try TestSupport.taxonomy()
        vocabulary = try TestSupport.vocabulary()
    }

    private func style(_ path: String) -> StyleReader.Match? {
        StyleReader.read(relativePath: path,
                         filename: (path as NSString).lastPathComponent,
                         vocabulary: styles)
    }

    // MARK: - 詞彙表本身

    func testEveryAliasPointsAtAStyleInTheWhitelist() {
        for (alias, target) in styles.aliases {
            XCTAssertTrue(styles.isValid(target), "別名 \(alias) 指向白名單外的風格：\(target)")
        }
    }

    func testAliasOrderPutsLongerPhrasesFirst() {
        // 這個排序是「tech house 不會被 house 搶走」的唯一保證。
        let wordCounts = styles.aliasOrder.map { $0.split(separator: " ").count }
        XCTAssertEqual(wordCounts, wordCounts.sorted(by: >),
                       "alias_order 必須由詞數多的排到少")
    }

    // MARK: - 詞界比對

    func testMatchingIsWordBoundedNotSubstring() {
        // 這是規劃階段量化覆蓋率時踩到的坑：子字串比對讓 "pop" 命中了
        // 448 次，其中絕大多數其實來自 "City Pop"。
        XCTAssertEqual(style("City Pop/Loops/thing.wav")?.style, "City Pop")
        XCTAssertNil(style("Popcorn Foley/kernel.wav")?.style,
                     "pop 不得命中 popcorn 這種只是字母相同的詞")
    }

    func testLongerPhraseWinsOverShorterOne() {
        XCTAssertEqual(style("Funky_Tech_House_Audio/Loops/a.wav")?.style, "Tech House",
                       "tech house 必須贏過 house 與 funky")
        XCTAssertEqual(style("Future_Bass_Pack/one_shots/b.wav")?.style, "Future Bass",
                       "future bass 必須贏過 bass")
    }

    func testVendorFolderNamesNormaliseToCanonicalStyles() {
        XCTAssertEqual(style("LOFI_BREAKS/LOB_WAV_LOOPS/x.wav")?.style, "Lo-Fi")
        XCTAssertEqual(style("Diginoiz_Free_Boom_Bap_Drums/Snare 19.wav")?.style, "Boom Bap")
        XCTAssertEqual(style("Sample Magic - Chiptune/drum hits/ct_hat.wav")?.style, "Chiptune")
        XCTAssertEqual(style("AizerX - Hybrid Cyberpunk Toolkit/hit.wav")?.style, "Cyberpunk")
        XCTAssertEqual(style("Synth Wave/Cymbals/Closed/c.wav")?.style, "Synthwave")
    }

    func testFolderEvidenceIsPreferredOverFilename() {
        let match = style("Boom Bap Kit/house party snare.wav")
        XCTAssertEqual(match?.style, "Boom Bap")
        XCTAssertEqual(match?.fromFolder, true)
    }

    func testFilenameIsUsedWhenTheFolderSaysNothing() {
        let match = style("Unsorted/lofi kick 03.wav")
        XCTAssertEqual(match?.style, "Lo-Fi")
        XCTAssertEqual(match?.fromFolder, false)
    }

    // MARK: - 沒有線索時留空

    func testNoStyleEvidenceYieldsNilNotAGuess() {
        XCTAssertNil(style("2. Sorted Drums/8. Toms/tom (11).wav"))
        XCTAssertNil(style("Unsort/23 SNARE.wav"))
        XCTAssertNil(style("SONNY_D_drum_kit/SONNY_D_hihat_open_06.wav"))
    }

    // MARK: - 模糊字需要製作素材的脈絡

    private func style(_ path: String, category: String?) -> StyleReader.Match? {
        StyleReader.read(relativePath: path,
                         filename: (path as NSString).lastPathComponent,
                         vocabulary: styles,
                         category: category)
    }

    func testAmbiguousWordsAreRejectedOutsideMusicMaterial() {
        // 全部取自使用者真實的庫，第一次跑 M27 時這四筆都被標成了曲風。
        XCTAssertNil(style("Ultimate Bare Feet Expansion/Bare_Feet_Metal 1_SLOW_MED_WALK.wav",
                           category: "Foley/Footsteps"),
                     "金屬地板上的赤腳腳步聲不是重金屬")
        XCTAssertNil(style("Surround The Rain/Rain On Concrete, Drips On Metal.wav",
                           category: "Nature/Rain"))
        XCTAssertNil(style("Rock The Speakerbox - Melee/BASEBALL BAT Aluminum Hit Head.wav",
                           category: "Impacts"),
                     "Rock The Speakerbox 是廠商名字")
        XCTAssertNil(style("Coll Anderson - House Library Add Ons/EFX INT Door Bang.wav",
                           category: "Foley/Doors"),
                     "房子的音效庫不是 House 音樂")
    }

    func testAmbiguousWordsAreAcceptedInsideMusicMaterial() {
        XCTAssertEqual(style("SD_EDM_SamplePack/Samples/Drums/One Shots/House/Kicks/SD_Kick.wav",
                             category: "Drums/Kick")?.style,
                       "House",
                       "sample pack 裡的 House/Kicks 就是 House 音樂")
    }

    func testAmbiguousWordsAreRejectedWhenThereIsNoCategoryAtAll() {
        // 沒有分類＝沒有製作素材的證據。寧可漏標，不要標錯。
        XCTAssertNil(style("Random Pack/metal thing.wav", category: nil))
    }

    func testUnambiguousStylesDoNotNeedTheGate() {
        // 沒有人會把一段開門聲取名叫 tech house 或 boom bap。
        XCTAssertEqual(style("Funky_Tech_House_Audio/x.wav", category: "Foley/Doors")?.style,
                       "Tech House")
        XCTAssertEqual(style("Diginoiz_Free_Boom_Bap_Drums/x.wav", category: nil)?.style,
                       "Boom Bap")
    }

    func testEveryAmbiguousWordIsAKnownAlias() {
        for word in styles.ambiguous {
            XCTAssertNotNil(styles.aliases[word], "\(word) 不在別名表中")
        }
    }

    func testProductionMaterialTest() {
        XCTAssertTrue(StyleReader.isProductionMaterial("Drums/Kick"))
        XCTAssertTrue(StyleReader.isProductionMaterial("Instruments/Bass"))
        XCTAssertFalse(StyleReader.isProductionMaterial("Foley/Footsteps"))
        XCTAssertFalse(StyleReader.isProductionMaterial("Impacts/Metal"))
        XCTAssertFalse(StyleReader.isProductionMaterial(nil))
    }

    // MARK: - 與分類的整合

    private func evidence(_ path: String) -> PathEvidence {
        PathEvidenceReader.read(relativePath: path,
                                filename: (path as NSString).lastPathComponent,
                                taxonomy: taxonomy,
                                vocabulary: vocabulary,
                                styles: styles)
    }

    func testCategoryAndStyleAreIndependent() {
        let a = evidence("Diginoiz_Free_Boom_Bap_Drums/Boom Bap Drums - Kick 1.wav")
        XCTAssertEqual(a.category, "Drums/Kick")
        XCTAssertEqual(a.style?.style, "Boom Bap")

        let b = evidence("Funky_Tech_House_Audio/One_Shots/DrumPerc_One_Shots/Kicks/FTH_Kick_19.wav")
        XCTAssertEqual(b.category, "Drums/Kick", "同樣是 kick")
        XCTAssertEqual(b.style?.style, "Tech House", "風格不同")
    }

    func testStyleIsAbsentWhenNoStyleVocabularyIsSupplied() {
        let evidence = PathEvidenceReader.read(relativePath: "LOFI_BREAKS/x.wav",
                                               filename: "x.wav",
                                               taxonomy: taxonomy,
                                               vocabulary: vocabulary)
        XCTAssertNil(evidence.style)
    }

    // MARK: - 白名單約束

    func testValidatorRejectsAStyleOutsideTheWhitelist() throws {
        let validator = OrganizerSchemaValidator(taxonomy: taxonomy,
                                                 vocabulary: vocabulary,
                                                 styles: styles)
        let result = OrganizerResult(status: .suggested,
                                     displayName: nil,
                                     category: "Drums/Kick",
                                     style: "Vaporwave Trap Fusion",
                                     tags: [],
                                     confidence: 0.7,
                                     needsReview: false)
        XCTAssertThrowsError(try validator.validate(result)) { error in
            XCTAssertEqual(error as? OrganizerValidationError,
                           .unknownStyle("Vaporwave Trap Fusion"))
        }
    }

    func testValidatorAcceptsAWhitelistedStyle() throws {
        let validator = OrganizerSchemaValidator(taxonomy: taxonomy,
                                                 vocabulary: vocabulary,
                                                 styles: styles)
        let result = OrganizerResult(status: .suggested,
                                     displayName: nil,
                                     category: "Drums/Kick",
                                     style: "Boom Bap",
                                     tags: [],
                                     confidence: 0.7,
                                     needsReview: false)
        XCTAssertNoThrow(try validator.validate(result))
    }

    func testStyleIsOptionalButStillAllowed() {
        // style 是選填的：列為必填會逼既有的所有樣本與提示詞一起改，
        // 換不到任何安全性——AI 本來就不該猜風格，這個欄位是本機引擎填的。
        XCTAssertFalse(OrganizerResult.requiredKeys.contains("style"))
        XCTAssertTrue(OrganizerResult.allowedKeys.contains("style"))
    }
}

/// 風格在介面上的可用性。
///
/// M27 算出了 4,565 個音效的風格，但在這組測試出現之前，那個欄位在整個
/// 介面裡只出現在審核列的一行小字——側欄不能篩、搜尋找不到、Inspector 不顯示。
/// 算出來卻碰不到，等於沒做。
final class StyleFilteringTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: SoundRepository!
    private var libraryId: Int64 = 0

    override func setUpWithError() throws {
        database = try TestSupport.database()
        repository = SoundRepository(database: database)
        libraryId = try database.writer.write { db in
            var library = Library(name: "Test", rootPath: "/tmp/test")
            try library.insert(db)
            return library.id ?? 0
        }
    }

    @discardableResult
    private func sound(_ name: String, style: String?) throws -> Int64 {
        try database.writer.write { db in
            var sound = Sound(libraryId: libraryId,
                              filePath: "/tmp/test/\(name)",
                              relativePath: name,
                              filename: name,
                              fileExtension: "wav",
                              duration: 1)
            sound.style = style
            sound.styleSource = style == nil ? nil : .imported
            try sound.insert(db)
            return sound.id ?? 0
        }
    }

    func testStyleCountsAreOrderedByFrequency() throws {
        for index in 0..<5 { try sound("lofi\(index).wav", style: "Lo-Fi") }
        for index in 0..<2 { try sound("bb\(index).wav", style: "Boom Bap") }
        try sound("none.wav", style: nil)

        let counts = try repository.styleCounts()
        XCTAssertEqual(counts.map(\.style), ["Lo-Fi", "Boom Bap"])
        XCTAssertEqual(counts.map(\.count), [5, 2])
    }

    func testSoundsWithoutAStyleAreNotListed() throws {
        try sound("none.wav", style: nil)
        XCTAssertTrue(try repository.styleCounts().isEmpty,
                      "沒有風格的音效不該憑空生出一個空白的風格項目")
    }

    func testFilteringByStyle() throws {
        let lofi = try sound("a.wav", style: "Lo-Fi")
        try sound("b.wav", style: "Boom Bap")
        try sound("c.wav", style: nil)

        let hits = try repository.fetch(filter: .style("Lo-Fi"), limit: 20)
        XCTAssertEqual(hits.compactMap(\.id), [lofi])
        XCTAssertEqual(try repository.count(filter: .style("Lo-Fi")), 1)
    }

    func testStyleFilterIsIndependentOfCategory() throws {
        // 風格與分類正交：同一個分類可以有多種風格，反之亦然（D-014）。
        try database.writer.write { db in
            let kick = try Int64.fetchOne(db, sql: "SELECT id FROM categories WHERE path = ?",
                                          arguments: ["Drums/Kick"])
            for (name, style) in [("k1.wav", "Lo-Fi"), ("k2.wav", "Tech House")] {
                var sound = Sound(libraryId: libraryId,
                                  filePath: "/tmp/test/\(name)",
                                  relativePath: name,
                                  filename: name,
                                  fileExtension: "wav",
                                  duration: 1)
                sound.categoryId = kick
                sound.style = style
                try sound.insert(db)
            }
        }
        XCTAssertEqual(try repository.count(filter: .style("Lo-Fi")), 1)
        XCTAssertEqual(try repository.count(filter: .style("Tech House")), 1)
    }

    func testSearchFindsSoundsByStyle() throws {
        // 搜尋原本涵蓋檔名／名稱／路徑／分類／標籤／備註，就是沒有風格。
        let id = try sound("xk_0042.wav", style: "Boom Bap")
        let hits = try repository.fetch(filter: .all, search: "boom bap", limit: 20)
        XCTAssertEqual(hits.compactMap(\.id), [id],
                       "檔名完全看不出風格時，搜尋風格是唯一找得到它的方式")
    }

    func testEveryStyleInTheVocabularyCanBeFiltered() throws {
        let vocabulary = try TestSupport.styles()
        for style in vocabulary.styles.prefix(5) {
            try sound("\(style).wav", style: style)
        }
        for style in vocabulary.styles.prefix(5) {
            XCTAssertEqual(try repository.count(filter: .style(style)), 1, "\(style) 篩不出來")
        }
    }
}
