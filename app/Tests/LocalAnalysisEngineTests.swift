import XCTest
@testable import FoleyLibrary

/// 本機分析引擎的三層測試：形狀判斷、路徑證據、兩者合併。
///
/// 合併層是重點。D-013 的教訓是「高信心的錯答案比沒答案危險」，
/// 所以這裡花最多篇幅在證明：證據衝突時它會降低信心而不是挑一邊硬講。
final class LocalAnalysisEngineTests: XCTestCase {

    private var taxonomy: Taxonomy!
    private var vocabulary: TagVocabulary!

    override func setUpWithError() throws {
        taxonomy = try TestSupport.taxonomy()
        vocabulary = try TestSupport.vocabulary()
    }

    // MARK: - 樣本特徵

    private func features(duration: Double = 1,
                          peak: Float = 0.9,
                          rms: Float = 0.1,
                          crest: Float = 9,
                          attack: Double = 0.005,
                          decay: Double = 0.2,
                          sustain: Float = 0.1,
                          centroid: Float = 2000,
                          flatness: Float = 0.3,
                          low: Float = 0.3,
                          mid: Float = 0.4,
                          high: Float = 0.3,
                          slope: Float = 0,
                          onsets: Int = 1,
                          tempo: Double? = nil,
                          loopLike: Bool = false) -> AcousticFeatures {
        AcousticFeatures(duration: duration,
                         sampleRate: 44_100,
                         channelCount: 2,
                         peak: peak,
                         rms: rms,
                         crestFactor: crest,
                         attackTime: attack,
                         decayTime: decay,
                         sustainRatio: sustain,
                         zeroCrossingRate: 0.1,
                         spectralCentroid: centroid,
                         spectralRolloff: centroid * 2,
                         spectralFlatness: flatness,
                         lowEnergyRatio: low,
                         midEnergyRatio: mid,
                         highEnergyRatio: high,
                         centroidSlope: slope,
                         onsetCount: onsets,
                         leadingSilence: 0,
                         trailingSilence: 0,
                         tempo: tempo,
                         tempoConfidence: tempo == nil ? 0 : 0.9,
                         isLoopLike: loopLike)
    }

    private var impulseFeatures: AcousticFeatures { features() }

    private var droneFeatures: AcousticFeatures {
        features(duration: 20, crest: 2.5, attack: 0.5, decay: 5,
                 sustain: 0.95, centroid: 400, flatness: 0.05,
                 low: 0.8, mid: 0.15, high: 0.05, onsets: 1)
    }

    private var noiseFeatures: AcousticFeatures {
        features(duration: 8, crest: 3, attack: 0.3, decay: 4,
                 sustain: 0.9, centroid: 6000, flatness: 0.5,
                 low: 0.1, mid: 0.3, high: 0.6, onsets: 1)
    }

    private var sweepFeatures: AcousticFeatures {
        features(duration: 3, crest: 3, attack: 0.5, decay: 1,
                 sustain: 0.8, centroid: 4000, flatness: 0.2, slope: 2500)
    }

    // MARK: - 形狀

    func testImpulseIsRecognisedAsImpulse() {
        XCTAssertEqual(AcousticClassifier.evidence(from: impulseFeatures).shape, .impulse)
    }

    func testSustainedToneIsRecognisedAsTonal() {
        XCTAssertEqual(AcousticClassifier.evidence(from: droneFeatures).shape, .tonal)
    }

    func testSustainedFlatSpectrumIsRecognisedAsNoise() {
        XCTAssertEqual(AcousticClassifier.evidence(from: noiseFeatures).shape, .noise)
    }

    func testMovingCentroidIsRecognisedAsSweep() {
        XCTAssertEqual(AcousticClassifier.evidence(from: sweepFeatures).shape, .sweep)
    }

    func testManyOnsetsAreRecognisedAsRhythmic() {
        let evidence = AcousticClassifier.evidence(from: features(duration: 4, sustain: 0.4, onsets: 8))
        XCTAssertEqual(evidence.shape, .rhythmic)
    }

    func testSilenceIsItsOwnShapeNotAFailure() {
        let evidence = AcousticClassifier.evidence(from: .silent(duration: 2, sampleRate: 44_100, channelCount: 1))
        XCTAssertEqual(evidence.shape, .silent)
        XCTAssertTrue(evidence.tags.isEmpty)
    }

    func testInBetweenSignalStaysAmbiguousInsteadOfGuessing() {
        // 持續，但平坦度卡在調性與噪聲之間——這是真的說不準。
        let evidence = AcousticClassifier.evidence(from: features(duration: 5, crest: 3, sustain: 0.8, flatness: 0.2))
        XCTAssertEqual(evidence.shape, .ambiguous)
        XCTAssertLessThan(evidence.confidence, 0.5, "說不準的時候信心必須低")
    }

    // MARK: - 量測標籤

    func testTagsComeOnlyFromMeasurements() throws {
        let evidence = AcousticClassifier.evidence(from: impulseFeatures)
        for tag in evidence.tags {
            XCTAssertTrue(vocabulary.isCanonical(tag), "\(tag) 不在受控詞彙表裡")
        }
        // 材質永遠不能由聲學層產生——量測支持不了「金屬」這個詞。
        let materials = Set(vocabulary.groups["material"] ?? [])
        XCTAssertTrue(Set(evidence.tags).isDisjoint(with: materials),
                      "聲學層不得輸出材質標籤")
    }

    func testDurationTagsFollowDuration() {
        XCTAssertTrue(AcousticClassifier.evidence(from: features(duration: 0.4)).tags.contains("short"))
        XCTAssertTrue(AcousticClassifier.evidence(from: features(duration: 3)).tags.contains("medium"))
        XCTAssertTrue(AcousticClassifier.evidence(from: features(duration: 30)).tags.contains("long"))
    }

    func testBrightnessTagFollowsSpectralCentroid() {
        XCTAssertTrue(AcousticClassifier.evidence(from: features(centroid: 8000)).tags.contains("bright"))
        XCTAssertTrue(AcousticClassifier.evidence(from: features(centroid: 300)).tags.contains("dark"))
    }

    func testLongTailAfterImpactIsTaggedReverberant() {
        let evidence = AcousticClassifier.evidence(from: features(duration: 4, decay: 2.5))
        XCTAssertTrue(evidence.tags.contains("reverberant"))
    }

    func testSustainedToneIsNotTaggedSharpOrDull() {
        // 持續音沒有明確起音，套 sharp/dull 只是在硬安詞。
        let tags = AcousticClassifier.evidence(from: droneFeatures).tags
        XCTAssertFalse(tags.contains("sharp"))
        XCTAssertFalse(tags.contains("dull"))
    }

    func testNotesAreHumanReadableMeasurements() {
        let notes = AcousticClassifier.evidence(from: impulseFeatures).notes
        XCTAssertFalse(notes.isEmpty)
        XCTAssertTrue(notes.contains { $0.contains("波峰因數") })
        XCTAssertTrue(notes.contains { $0.contains("頻譜重心") })
    }

    // MARK: - 路徑證據

    private func path(_ relativePath: String) -> PathEvidence {
        PathEvidenceReader.read(relativePath: relativePath,
                                filename: (relativePath as NSString).lastPathComponent,
                                taxonomy: taxonomy,
                                vocabulary: vocabulary)
    }

    func testEveryRuleMapsToAValidTaxonomyPath() {
        for rule in PathEvidenceReader.rules {
            XCTAssertTrue(taxonomy.isValidPath(rule.category),
                          "規則指向不存在的分類：\(rule.category)")
        }
    }

    func testFolderNameDrivesCategory() {
        XCTAssertEqual(path("Cinematic Hits/Hit Metal Reverb 03.wav").category, "Designed/Impact Hit")
        XCTAssertEqual(path("Drones/Low Drone 02.wav").category, "Designed/Drone")
        XCTAssertEqual(path("Whoosh/Air Pass 11.wav").category, "Designed/Whoosh")
    }

    func testLongerPhrasesWinOverShorterOnes() {
        // "whoosh to hit" 必須贏過 "whoosh"，否則整個資料夾會被歸錯。
        XCTAssertEqual(path("Whoosh To Hit/WTH 04.wav").category, "Designed/Impact Hit")
    }

    func testSeparatorsDoNotChangeMatching() {
        XCTAssertEqual(path("Transition/soft_transition-02.wav").category,
                       path("Transition/Soft Transition 02.wav").category)
    }

    func testFolderAndFilenameAgreeingRaisesConfidence() {
        let agreeing = path("Drones/deep drone bed.wav")
        let folderOnly = path("Drones/xk_0042.wav")
        XCTAssertGreaterThan(agreeing.confidence, folderOnly.confidence)
    }

    func testFolderAndFilenameDisagreeingLowersConfidence() {
        let conflicting = path("Drones/glass smash 01.wav")
        XCTAssertEqual(conflicting.category, "Designed/Drone", "衝突時採信資料夾")
        XCTAssertLessThan(conflicting.confidence, 0.6, "衝突必須反映成低信心")
    }

    // MARK: - 音樂製作素材（M27）

    func testDrumRolesAreRecognisedFromPaths() {
        XCTAssertEqual(path("Diginoiz_Free_Boom_Bap_Drums/Boom Bap Drums - Kick 1.wav").category,
                       "Drums/Kick")
        XCTAssertEqual(path("2. Sorted Drums/2. Snares/Unsort/snare (32).wav").category,
                       "Drums/Snare")
        XCTAssertEqual(path("Cymatics x S1/Hihats/Closed Hihat 7.wav").category,
                       "Drums/Hi-Hat")
        XCTAssertEqual(path("2. Sorted Drums/8. Toms/tom (11).wav").category, "Drums/Tom")
        XCTAssertEqual(path("Splice/One_Shots/DrumPerc_One_Shots/Kicks/FTH_Kick_19.wav").category,
                       "Drums/Kick")
    }

    func testDrumLoopsAreDistinguishedFromOneShots() {
        XCTAssertEqual(path("2. Sorted Drums/5. Loops/Top Loops/LOFI/Top Loop 04 - 75 BPM.wav").category,
                       "Drums/Drum Loop")
        XCTAssertEqual(path("LOB_WAV_LOOPS/LOB_DRUM_LOOPS_WITH_PARTS/LOB_116_Drums_Cushdy_Full_1.wav").category,
                       "Drums/Drum Loop")
    }

    func testMelodicMaterialGoesToInstrumentsNotDrums() {
        // 這一庫叫 Drum Machines，但 8078 個檔案裡有 2218 個是旋律類。
        // 只針對鼓設計的分類法會漏掉超過四分之一。
        XCTAssertEqual(path("Funk_Odyssey/Loops/Melodic_Loops/Guitar/Electric_Guitar/a.wav").category,
                       "Instruments/Guitar")
        XCTAssertEqual(path("Tokyo_City_Pop/Loops/Melodic_Loops/Piano___Keys/b.wav").category,
                       "Instruments/Keys")
        XCTAssertEqual(path("Tokyo_Nights/one_shots/Vocal_Oneshots/JapaneseShout8.wav").category,
                       "Instruments/Vocal")
        XCTAssertEqual(path("Sample Magic - Chiptune/synth shots/chords/ct_chord_lima1_C.wav").category,
                       "Instruments/Chord")
    }

    func testAddingDrumRulesDoesNotStealTheFXTextureFolder() {
        // 迴歸測試。這個資料夾同時命中 Designed/Texture（noise、hiss、crackle）
        // 與 Drums/Percussion（perc）。若用「第一個命中的規則就算」，
        // 加入鼓的規則會把 FX 庫裡五百多個 Texture 一次弄壞。
        let evidence = path("Noise/musicradar-noise-hiss-crackle-samples/Noise_Perc_Hits/Perc_Hit_43.wav")
        XCTAssertEqual(evidence.category, "Designed/Texture",
                       "命中最多詞的規則才該勝出")
    }

    func testScoringCountsFolderLevelsNotMatchedTerms() {
        // 計分的單位是資料夾層級：兩層都在講 noise 系的東西 = 兩分。
        // 但顯示要留下全部命中的詞，審核介面才看得出憑什麼這樣判斷。
        let evidence = path("Noise/hiss crackle grain/x.wav")
        XCTAssertEqual(evidence.category, "Designed/Texture")
        XCTAssertGreaterThanOrEqual(evidence.matchedTerms.count, 3,
                                    "命中的詞要留給審核介面看")
    }

    func testMoreFolderLevelsAgreeingIsStrongerEvidence() {
        // 三層都提到 noise 系的詞，只有最後一層提到 perc。
        // 若改用宣告順序決定，加入鼓的規則會把 FX 庫裡五百多個 Texture 一次弄壞。
        XCTAssertEqual(path("Noise/noise-hiss-crackle-samples/Noise_Perc_Hits/a.wav").category,
                       "Designed/Texture")
        // 只有一層提到 noise 時，葉資料夾的 perc 就該贏。
        XCTAssertEqual(path("Sample Pack/Perc/a.wav").category, "Drums/Percussion")
    }

    func test808GoesToDrumsNotInstrumentBass() {
        // 808 在製作上是當 kick 用的，不是貝斯。
        XCTAssertEqual(path("Trap Kit/808s/808 deep 01.wav").category, "Drums/808")
    }

    func testDrumsAndInstrumentsPathsAreAllValidTaxonomyEntries() {
        for rule in PathEvidenceReader.rules where rule.category.hasPrefix("Drums/")
            || rule.category.hasPrefix("Instruments/") {
            XCTAssertTrue(taxonomy.isValidPath(rule.category),
                          "規則指向不存在的分類：\(rule.category)")
        }
    }

    func testUnknownPathYieldsNoCategory() {
        XCTAssertNil(path("Cute/xk_9931.wav").category)
    }

    func testTagsAreLiteralHitsOnly() {
        let evidence = path("Impacts/heavy metal slam.wav")
        XCTAssertTrue(evidence.tags.contains("metal"))
        XCTAssertTrue(evidence.tags.contains("heavy"))
        XCTAssertTrue(evidence.tags.contains("slam"))
        XCTAssertFalse(evidence.tags.contains("wood"), "沒寫在路徑裡的詞不得出現")
    }

    // MARK: - 合併

    private func engine(_ measured: AcousticFeatures?) -> LocalAnalysisEngine {
        LocalAnalysisEngine(taxonomy: taxonomy, vocabulary: vocabulary, measure: { _ in measured })
    }

    private func request(_ relativePath: String) -> OrganizerRequest {
        OrganizerRequest(soundId: 1,
                         audioURL: URL(fileURLWithPath: "/tmp/\(relativePath)"),
                         filename: (relativePath as NSString).lastPathComponent,
                         relativePath: relativePath,
                         fileFormat: "wav")
    }

    func testAgreeingEvidenceProducesRecognised() async throws {
        let result = try await engine(impulseFeatures).analyze(request("Cinematic Hits/Hit Metal Reverb 03.wav"))
        XCTAssertEqual(result.status, .recognized)
        XCTAssertEqual(result.category, "Designed/Impact Hit")
        XCTAssertFalse(result.needsReview)
        XCTAssertGreaterThan(result.confidence, 0.75)
    }

    func testContradictingEvidenceProducesUncertainNotAConfidentAnswer() async throws {
        // 資料夾說是撞擊，訊號卻是持續的低頻調性音。這正是 D-013 裡最危險的情境。
        let result = try await engine(droneFeatures).analyze(request("Cinematic Hits/Hit Metal Reverb 03.wav"))
        XCTAssertEqual(result.status, .uncertain)
        XCTAssertTrue(result.needsReview)
        XCTAssertLessThanOrEqual(result.confidence, 0.4)
        XCTAssertFalse(result.alternativeCategories.isEmpty, "應該把量測支持的候選附上")
    }

    func testNeutralShapeStillAllowsSuggestion() async throws {
        // Cute 沒有形狀預期，但這裡用的是有路徑證據、形狀無預期的分類。
        let result = try await engine(impulseFeatures).analyze(request("Foley/Cloth/rustle 01.wav"))
        XCTAssertEqual(result.category, "Foley/Cloth")
        XCTAssertEqual(result.status, .suggested)
    }

    func testNoPathEvidenceNeverInventsACategory() async throws {
        let result = try await engine(noiseFeatures).analyze(request("Cute/xk_9931.wav"))
        XCTAssertEqual(result.category, Taxonomy.unclassified)
        XCTAssertEqual(result.status, .uncertain)
        XCTAssertTrue(result.needsReview)
        XCTAssertLessThan(result.confidence, 0.5)
        // 形狀只能提供候選，不能變成答案。
        XCTAssertTrue(result.alternativeCategories.contains("Designed/Texture"))
    }

    func testUnreadableAudioFailsInsteadOfFallingBackToFilename() async throws {
        // 這是 D-013 的核心防線：光靠檔名就下判斷，正是出事的那種行為。
        let result = try await engine(nil).analyze(request("Cinematic Hits/Hit Metal Reverb 03.wav"))
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.category, Taxonomy.unclassified)
        XCTAssertEqual(result.confidence, 0)
        XCTAssertTrue(result.tags.isEmpty)
    }

    func testResultAlwaysPassesTheSchemaValidator() async throws {
        let validator = try TestSupport.validator()
        let cases = ["Cinematic Hits/Hit Metal Reverb 03.wav",
                     "Drones/deep drone bed.wav",
                     "Cute/xk_9931.wav",
                     "Impacts/heavy metal slam.wav"]
        let measurements = [impulseFeatures, droneFeatures, noiseFeatures, sweepFeatures]
        for (path, measured) in zip(cases, measurements) {
            let result = try await engine(measured).analyze(request(path))
            XCTAssertNoThrow(try validator.validate(result),
                             "\(path) 的輸出沒通過語意驗證")
        }
    }

    func testTagCountStaysWithinVocabularyLimit() async throws {
        let result = try await engine(impulseFeatures).analyze(request("Impacts/heavy metal slam hard hit.wav"))
        XCTAssertLessThanOrEqual(result.tags.count, vocabulary.maxTags)
        XCTAssertEqual(Set(result.tags).count, result.tags.count, "標籤不得重複")
    }
}
