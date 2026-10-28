import XCTest
@testable import FoleyLibrary

/// 節拍的量測與字面抽取。
///
/// 兩邊都是純邏輯，所以邊界可以完整列出來。
final class TempoTests: XCTestCase {

    // MARK: - 八度折疊

    func testFoldingBringsTempoIntoTheUsualRange() {
        // 87 與 174 在訊號上是同一件事，差別只在把哪一層當成一拍。
        XCTAssertEqual(TempoAnalyzer.fold(87), 87)
        XCTAssertEqual(TempoAnalyzer.fold(43.5), 87)
        // 折疊本身消不掉八度模糊：174 也在範圍內，所以 348 停在 174。
        // 真正解決模糊的是兩種方法互相印證。
        XCTAssertEqual(TempoAnalyzer.fold(348), 174)
        XCTAssertNil(TempoAnalyzer.fold(0))
        XCTAssertNil(TempoAnalyzer.fold(-120))
    }

    // MARK: - 長度反推

    func testDurationOfWholeBarsGivesTheRightTempo() {
        // 一小節四拍、120 BPM = 每拍 0.5 秒 = 一小節 2 秒
        XCTAssertTrue(TempoAnalyzer.fromDuration(2).contains(120))
        // 兩小節 87 BPM ≈ 5.517 秒
        let candidates = TempoAnalyzer.fromDuration(5.517)
        XCTAssertTrue(candidates.contains { abs($0 - 87) < 0.5 })
    }

    func testVeryShortMaterialHasNoDurationCandidates() {
        XCTAssertTrue(TempoAnalyzer.fromDuration(0.15).isEmpty)
    }

    // MARK: - 起音間隔

    func testEvenlySpacedOnsetsGiveTheirTempo() {
        // 每 0.5 秒一次 = 120 BPM
        let times = (0..<9).map { Double($0) * 0.5 }
        XCTAssertEqual(try XCTUnwrap(TempoAnalyzer.fromOnsets(times)), 120, accuracy: 1)
    }

    func testOneLongGapDoesNotDragTheEstimate() {
        // 取眾數而不是平均：中間一個長休止不該把整個估計拉歪。
        var times = (0..<8).map { Double($0) * 0.5 }
        times.append(times.last! + 3.0)
        times += (1...6).map { times.last! + Double($0) * 0.5 }
        XCTAssertEqual(try XCTUnwrap(TempoAnalyzer.fromOnsets(times)), 120, accuracy: 2)
    }

    func testTooFewOnsetsGiveNothing() {
        XCTAssertNil(TempoAnalyzer.fromOnsets([0, 0.5, 1.0]))
        XCTAssertNil(TempoAnalyzer.fromOnsets([]))
    }

    // MARK: - 合併

    func testAgreementBetweenBothMethodsGivesHighConfidence() {
        let times = (0..<17).map { Double($0) * 0.5 }   // 120 BPM
        let estimate = TempoAnalyzer.estimate(duration: 8, onsetTimes: times, isLoopLike: true)
        XCTAssertEqual(try XCTUnwrap(estimate.bpm), 120, accuracy: 1)
        XCTAssertGreaterThan(estimate.confidence, 0.8)
    }

    func testOnsetsAloneGiveModerateConfidence() {
        let times = (0..<9).map { Double($0) * 0.5 }
        let estimate = TempoAnalyzer.estimate(duration: 4.31, onsetTimes: times, isLoopLike: false)
        XCTAssertNotNil(estimate.bpm)
        XCTAssertLessThan(estimate.confidence, 0.8)
    }

    func testNoEvidenceSaysNothingRatherThanGuessing() {
        // 多個長度候選、沒有起音證據——沒有依據在它們之間選。
        let estimate = TempoAnalyzer.estimate(duration: 8, onsetTimes: [], isLoopLike: true)
        XCTAssertNil(estimate.bpm)
        XCTAssertEqual(estimate.confidence, 0)
    }

    func testOneShotGetsNoDurationCandidates() {
        let estimate = TempoAnalyzer.estimate(duration: 0.4, onsetTimes: [], isLoopLike: false)
        XCTAssertNil(estimate.bpm)
    }

    // MARK: - 字面 BPM

    func testExplicitBPMInFilenames() {
        // 全部取自使用者真實的庫。
        XCTAssertEqual(MusicalMetadata.bpm(in: "ESW LoFi - Top Loop 04 - 75 BPM.wav")?.bpm, 75)
        XCTAssertEqual(MusicalMetadata.bpm(in: "Cymatics - Diplomats - 149 BPM E Min Brass.wav")?.bpm, 149)
        XCTAssertEqual(MusicalMetadata.bpm(in: "Kit_03_Memories_(144BPM)")?.bpm, 144)
        XCTAssertTrue(try XCTUnwrap(MusicalMetadata.bpm(in: "75 BPM")).explicit)
    }

    func testImplicitBPMFromAStandaloneNumber() {
        let match = try? XCTUnwrap(MusicalMetadata.bpm(in: "LOB_116_Drums_Cushdy_Full_1.wav"))
        XCTAssertEqual(match?.bpm, 116)
        XCTAssertEqual(match?.explicit, false)
    }

    func testNumbersGluedToLettersAreNotTempo() {
        // SND387、06622_SFX 是檔案編號不是節拍。
        XCTAssertNil(MusicalMetadata.bpm(in: "SND387.WAV"))
        XCTAssertNil(MusicalMetadata.bpm(in: "06622_SFX.mp3"))
        XCTAssertNil(MusicalMetadata.bpm(in: "ct_snr_gunta.wav"))
    }

    func testOutOfRangeNumbersAreNotTempo() {
        XCTAssertNil(MusicalMetadata.bpm(in: "sound_003.wav"))
        XCTAssertNil(MusicalMetadata.bpm(in: "take_999.wav"))
    }

    func testRangesInFolderNamesAreIgnored() {
        // 「100-175 BPM」是一整包的範圍，不是這個檔案的節拍。
        XCTAssertNil(MusicalMetadata.bpm(in: "LOB_SINGLE_DRUM_LOOPS/100-175 BPM"))
        // 55 不是我們會採用的 BPM，但它確實是範圍的一端——
        // 判斷「是不是範圍」要用比採用門檻更寬的帶，否則 89 會被當成這個檔案的節拍。
        XCTAssertNil(MusicalMetadata.bpm(in: "LOB_DRUM_LOOPS_WITH_PARTS/55-89 BPM"))
    }

    func testTwoPlausibleNumbersMeanWeCannotChoose() {
        // 兩個都在合理範圍，至少有一個是編號，沒有依據挑一個。
        XCTAssertNil(MusicalMetadata.bpm(in: "pack 120 take 95.wav"))
    }

    // MARK: - 字面調性

    func testKeyWithAccidentalOrMode() {
        XCTAssertEqual(MusicalMetadata.key(in: "Cymatics - Lofi Snare 2 - C#.wav"), "C#")
        XCTAssertEqual(MusicalMetadata.key(in: "149 BPM E Min Brass"), "Em")
        XCTAssertEqual(MusicalMetadata.key(in: "rfk_keys_130_sadsong_Am.wav"), "Am")
        XCTAssertEqual(MusicalMetadata.key(in: "FTH_Synth_Hit_01_Cmaj.wav"), "C")
        XCTAssertEqual(MusicalMetadata.key(in: "loop 90 E MIN.wav"), "Em",
                       "調式的大小寫寫法不一，要不分大小寫")
    }

    func testBareCapitalLettersAreNotKeys() {
        // 「Kit C」「Take A」到處都是，單獨一個大寫字母誤判率太高。
        XCTAssertNil(MusicalMetadata.key(in: "Drum Kit C.wav"))
        XCTAssertNil(MusicalMetadata.key(in: "Take A 01.wav"))
        XCTAssertNil(MusicalMetadata.key(in: "SD_Kick_Chrome.wav"))
        // 音名刻意只認大寫。接受小寫會讓誤判暴增——a、e、c 在檔名裡到處都是。
        XCTAssertNil(MusicalMetadata.key(in: "take a min.wav"))
    }

    // MARK: - loop / one-shot 的字面線索

    func testLoopHints() {
        XCTAssertEqual(MusicalMetadata.loopHint(in: "LOB_DRUM_LOOPS/x.wav"), true)
        XCTAssertEqual(MusicalMetadata.loopHint(in: "Breaks/amen.wav"), true)
        XCTAssertEqual(MusicalMetadata.loopHint(in: "One_Shots/Kicks/a.wav"), false)
        XCTAssertNil(MusicalMetadata.loopHint(in: "Cymatics - Flaws Crash.wav"))
    }

    func testOneShotHintBeatsLoopHint() {
        // 「DrumPerc_One_Shots」底下的東西不是 loop，即使上層資料夾叫 Loops。
        XCTAssertEqual(MusicalMetadata.loopHint(in: "Loops/DrumPerc_One_Shots/Hats/a.wav"), false)
    }
}

/// 節拍在介面上的可用性，以及字面與量測的交叉驗證。
///
/// D-026 的守則：一個新的 metadata 欄位，在能篩／能搜／能看至少做到一件之前，
/// 不算完成。這組測試守的是「能篩」和「能搜」。
final class TempoIntegrationTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: SoundRepository!
    private var engine: LocalAnalysisEngine!
    private var libraryId: Int64 = 0

    override func setUpWithError() throws {
        database = try TestSupport.database()
        repository = SoundRepository(database: database)
        engine = LocalAnalysisEngine(taxonomy: try TestSupport.taxonomy(),
                                     vocabulary: try TestSupport.vocabulary(),
                                     styles: try TestSupport.styles())
        libraryId = try database.writer.write { db in
            var library = Library(name: "Test", rootPath: "/tmp/test")
            try library.insert(db)
            return library.id ?? 0
        }
    }

    @discardableResult
    private func sound(_ name: String, bpm: Double?, isLoop: Bool?, key: String? = nil) throws -> Int64 {
        try database.writer.write { db in
            var sound = Sound(libraryId: libraryId,
                              filePath: "/tmp/test/\(name)",
                              relativePath: name,
                              filename: name,
                              fileExtension: "wav",
                              duration: 4)
            sound.bpm = bpm
            sound.bpmSource = bpm == nil ? nil : .imported
            sound.isLoop = isLoop
            sound.musicalKey = key
            try sound.insert(db)
            return sound.id ?? 0
        }
    }

    private func features(tempo: Double?, loopLike: Bool, confidence: Double = 0.9) -> AcousticFeatures {
        AcousticFeatures(duration: 4, sampleRate: 44_100, channelCount: 2,
                         peak: 0.9, rms: 0.2, crestFactor: 4.5,
                         attackTime: 0.01, decayTime: 0.3, sustainRatio: 0.6,
                         zeroCrossingRate: 0.1, spectralCentroid: 2000,
                         spectralRolloff: 4000, spectralFlatness: 0.3,
                         lowEnergyRatio: 0.3, midEnergyRatio: 0.4, highEnergyRatio: 0.3,
                         centroidSlope: 0, onsetCount: 8,
                         leadingSilence: 0, trailingSilence: 0,
                         tempo: tempo, tempoConfidence: tempo == nil ? 0 : confidence,
                         isLoopLike: loopLike)
    }

    private func request(_ path: String) -> OrganizerRequest {
        OrganizerRequest(soundId: 1,
                         audioURL: URL(fileURLWithPath: "/tmp/\(path)"),
                         filename: (path as NSString).lastPathComponent,
                         relativePath: path,
                         fileFormat: "wav")
    }

    // MARK: - 字面與量測的交叉驗證

    func testLiteralAndMeasuredAgreeing() {
        let facts = engine.musicalFacts(features: features(tempo: 116, loopLike: true),
                                        request: request("LOB_116_Drums_Cushdy_Full_1.wav"))
        XCTAssertEqual(facts.bpm, 116)
        XCTAssertFalse(facts.conflict)
        XCTAssertEqual(facts.note?.contains("一致"), true)
    }

    func testAnOctaveApartIsNotAConflict() {
        // 87 與 174 在訊號上是同一件事，不該被當成矛盾。
        let facts = engine.musicalFacts(features: features(tempo: 174, loopLike: true),
                                        request: request("loop 87 BPM.wav"))
        XCTAssertEqual(facts.bpm, 87)
        XCTAssertFalse(facts.conflict)
        XCTAssertEqual(facts.note?.contains("八度"), true)
    }

    func testRealDisagreementIsFlagged() {
        let facts = engine.musicalFacts(features: features(tempo: 128, loopLike: true),
                                        request: request("loop 90 BPM.wav"))
        XCTAssertEqual(facts.bpm, 90, "衝突時採信檔名——廠商比我們清楚")
        XCTAssertTrue(facts.conflict, "但要標記，讓人看一眼")
    }

    func testMeasurementAloneNeedsHighConfidence() {
        let confident = engine.musicalFacts(features: features(tempo: 120, loopLike: true, confidence: 0.9),
                                            request: request("untitled.wav"))
        XCTAssertEqual(confident.bpm, 120)

        let unsure = engine.musicalFacts(features: features(tempo: 120, loopLike: true, confidence: 0.5),
                                         request: request("untitled.wav"))
        XCTAssertNil(unsure.bpm, "沒有字面可以對照時，量測單獨採用的門檻要高")
    }

    func testNoEvidenceLeavesItEmpty() {
        let facts = engine.musicalFacts(features: features(tempo: nil, loopLike: false),
                                        request: request("Cymatics - Flaws Crash.wav"))
        XCTAssertNil(facts.bpm)
        XCTAssertNil(facts.isLoop, "證據不足就是 nil，不猜")
    }

    func testPathHintBeatsAcousticsForLoopDetection() {
        // 資料夾叫 One_Shots 就不是 loop，即使聲學上像。
        let facts = engine.musicalFacts(features: features(tempo: 120, loopLike: true),
                                        request: request("Pack/One_Shots/Kicks/a.wav"))
        XCTAssertEqual(facts.isLoop, false)
    }

    // MARK: - 能篩

    func testFilteringByTempoBand() throws {
        let slow = try sound("slow.wav", bpm: 75, isLoop: true)
        let mid = try sound("mid.wav", bpm: 110, isLoop: true)
        try sound("fast.wav", bpm: 174, isLoop: true)
        try sound("none.wav", bpm: nil, isLoop: nil)

        var filters = SoundFilters()
        filters.tempo = .slow
        XCTAssertEqual(try repository.fetch(filter: .all, filters: filters, limit: 20).compactMap(\.id),
                       [slow])
        filters.tempo = .mid
        XCTAssertEqual(try repository.fetch(filter: .all, filters: filters, limit: 20).compactMap(\.id),
                       [mid])
    }

    func testSoundsWithoutTempoAreNotTreatedAsZero() throws {
        try sound("none.wav", bpm: nil, isLoop: nil)
        var filters = SoundFilters()
        filters.tempo = .slow    // 0–90
        XCTAssertTrue(try repository.fetch(filter: .all, filters: filters, limit: 20).isEmpty,
                      "「沒有節拍」不等於「節拍是 0」")
    }

    func testFilteringLoopsAndOneShots() throws {
        let loop = try sound("loop.wav", bpm: 120, isLoop: true)
        let shot = try sound("shot.wav", bpm: nil, isLoop: false)
        try sound("unknown.wav", bpm: nil, isLoop: nil)

        var filters = SoundFilters()
        filters.loop = .loops
        XCTAssertEqual(try repository.fetch(filter: .all, filters: filters, limit: 20).compactMap(\.id),
                       [loop])
        filters.loop = .oneShots
        XCTAssertEqual(try repository.fetch(filter: .all, filters: filters, limit: 20).compactMap(\.id),
                       [shot])
    }

    func testFiltersCombineWithEachOther() throws {
        let wanted = try sound("a.wav", bpm: 95, isLoop: true)
        try sound("b.wav", bpm: 95, isLoop: false)
        try sound("c.wav", bpm: 160, isLoop: true)

        var filters = SoundFilters()
        filters.loop = .loops
        filters.tempo = .mid
        XCTAssertEqual(try repository.fetch(filter: .all, filters: filters, limit: 20).compactMap(\.id),
                       [wanted])
    }

    func testTempoAndLoopCountAsActiveFilters() {
        var filters = SoundFilters()
        XCTAssertFalse(filters.isActive)
        filters.tempo = .fast
        XCTAssertTrue(filters.isActive, "不然 clear 按鈕不會出現，使用者清不掉")
        filters.clear()
        filters.loop = .loops
        XCTAssertTrue(filters.isActive)
    }

    // MARK: - 能搜

    func testSearchFindsSoundsByKey() throws {
        let id = try sound("xk_0042.wav", bpm: 90, isLoop: true, key: "Am")
        XCTAssertEqual(try repository.fetch(filter: .all, search: "Am", limit: 20).compactMap(\.id),
                       [id])
    }
}
