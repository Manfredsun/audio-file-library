import XCTest
@testable import FoleyLibrary

/// 命名計畫。**純計算**——不寫資料庫、不碰磁碟。
final class NamingPlanTests: XCTestCase {

    private func input(_ id: Int64,
                       path: String,
                       category: String? = nil,
                       style: String? = nil,
                       descriptor: String? = nil,
                       bpm: Double? = nil,
                       key: String? = nil,
                       isLoop: Bool? = false,
                       frozen: Int? = nil) -> NamingInput {
        NamingInput(soundId: id,
                    relativePath: path,
                    filename: (path as NSString).lastPathComponent,
                    fileExtension: "wav",
                    category: category,
                    style: style,
                    bpm: bpm,
                    musicalKey: key,
                    isLoop: isLoop,
                    descriptor: descriptor,
                    frozenNumber: frozen)
    }

    // MARK: - 模板

    func testOneShotTemplate() {
        let plan = NamingPlanner.plan([
            input(1, path: "AU/AU_FP_kick_one_shot_dirt.wav",
                  category: "Drums/Kick", style: "Boom Bap", descriptor: "dirt")
        ])
        XCTAssertEqual(plan.entries[0].newName, "Boom Bap Kick dirt 01.wav")
        XCTAssertEqual(plan.entries[0].folder, "Drums/Kick")
    }

    func testLoopTemplateUsesTempoAndKeyInsteadOfDescriptor() {
        let plan = NamingPlanner.plan([
            input(1, path: "Cymatics/Lofi Top Loop 87 BPM Fmin.wav",
                  category: "Drums/Drum Loop", style: "Lo-Fi",
                  descriptor: "Top", bpm: 87, key: "Fmin", isLoop: true)
        ])
        XCTAssertEqual(plan.entries[0].newName, "Lo-Fi Drum Loop 87bpm Fmin 01.wav")
    }

    // MARK: - 沒有的欄位整段略過

    func testMissingFieldsAreSkippedRatherThanFilledWithPlaceholders() {
        // `Unknown Kick 01.wav` 比 `Kick 01.wav` 更糟：
        // 它把「我們不知道」寫成一個看起來像資訊的字。
        let plan = NamingPlanner.plan([
            input(1, path: "FTH/FTH_Kick_19.wav", category: "Drums/Kick")
        ])
        XCTAssertEqual(plan.entries[0].newName, "Kick 01.wav")
        XCTAssertTrue(plan.entries[0].issues.contains(.noStyle))
        XCTAssertTrue(plan.entries[0].issues.contains(.noDescriptor))
    }

    func testNoCategoryFallsBackToAnUnclassifiedFolder() {
        let plan = NamingPlanner.plan([input(1, path: "misc/4.wav")])
        XCTAssertEqual(plan.entries[0].folder, NamingPlanner.unclassifiedFolder)
        XCTAssertTrue(plan.entries[0].issues.contains(.noCategory))
    }

    func testLoopWithoutTempoIsFlagged() {
        // 挑 loop 第一個要看的就是 BPM。
        let plan = NamingPlanner.plan([
            input(1, path: "loops/x.wav", category: "Drums/Drum Loop", isLoop: true)
        ])
        XCTAssertTrue(plan.entries[0].issues.contains(.loopWithoutTempo))
    }

    // MARK: - 編號

    func testNumbersComeFromTheOriginalPathOrderNotTheInputOrder() {
        // 依處理順序編號的話，每重跑一次整棵樹的名字都會變，
        // 第二次執行就製造出一整批假的「變更」。
        let shuffled = [
            input(3, path: "a/c.wav", category: "Drums/Kick"),
            input(1, path: "a/a.wav", category: "Drums/Kick"),
            input(2, path: "a/b.wav", category: "Drums/Kick"),
        ]
        let plan = NamingPlanner.plan(shuffled)
        XCTAssertEqual(plan.entries.map(\.soundId), [1, 2, 3])
        XCTAssertEqual(plan.entries.map(\.number), [1, 2, 3])
    }

    func testNumbersAreCountedPerDestinationFolder() {
        let plan = NamingPlanner.plan([
            input(1, path: "a/a.wav", category: "Drums/Kick"),
            input(2, path: "a/b.wav", category: "Drums/Snare"),
        ])
        XCTAssertEqual(plan.entries.map(\.number), [1, 1])
    }

    func testAFrozenNumberIsHonouredAndNewFilesTakeTheNextOne() {
        // 在排序中間插進一個新檔案，既有檔案的號碼不可以位移。
        let plan = NamingPlanner.plan([
            input(1, path: "a/a.wav", category: "Drums/Kick", frozen: 1),
            input(9, path: "a/a2.wav", category: "Drums/Kick"),
            input(2, path: "a/b.wav", category: "Drums/Kick", frozen: 2),
        ])
        let numbers = Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.soundId, $0.number) })
        XCTAssertEqual(numbers[1], 1)
        XCTAssertEqual(numbers[2], 2)
        // 這一條原本寫的是 2，那是**錯的**：2 已經被 sound 2 凍結了，
        // 再發一次就是兩個檔案同名。M32c 改成先收齊凍結的號碼再發號，
        // 新檔案拿的是還沒被用掉的那一個。
        XCTAssertEqual(numbers[9], 3, "新檔案不可以拿到已經被凍結的號碼")
    }

    // MARK: - 碰撞

    func testBothSidesOfACollisionAreMarked() {
        // 只標一邊的話，人看到的是「這一筆有問題」，
        // 但真正要決定的是「這兩筆哪一個該改」。
        let plan = NamingPlanner.plan([
            input(1, path: "a/a.wav", category: "Drums/Kick", frozen: 1),
            input(2, path: "a/b.wav", category: "Drums/Kick", frozen: 1),
        ])
        XCTAssertTrue(plan.entries.allSatisfy { $0.issues.contains(.collision) })
        XCTAssertFalse(plan.canExecute, "有碰撞就不准執行")
    }

    func testAnAlreadyOccupiedDestinationCounts() {
        let plan = NamingPlanner.plan(
            [input(1, path: "a/a.wav", category: "Drums/Kick")],
            existingDestinations: ["Drums/Kick/Kick 01.wav"])
        XCTAssertTrue(plan.entries[0].issues.contains(.collision))
    }

    func testANormalPlanHasNoCollisions() {
        let plan = NamingPlanner.plan([
            input(1, path: "a/a.wav", category: "Drums/Kick"),
            input(2, path: "a/b.wav", category: "Drums/Kick"),
        ])
        XCTAssertTrue(plan.canExecute)
        XCTAssertEqual(plan.entries.map(\.newName), ["Kick 01.wav", "Kick 02.wav"])
    }

    // MARK: - D-017 的硬約束

    func testADescriptorWordThatIsNotInTheSourceIsCaughtAndBlocks() {
        // 本機規則不會產生這種東西（它只做刪除），但接上 AI 之後
        // 這條檢查是唯一的保險：它編出來的字會在這裡被當場抓到。
        let plan = NamingPlanner.plan([
            input(1, path: "FTH/FTH_Kick_19.wav", category: "Drums/Kick",
                  descriptor: "Aggressive")
        ])
        XCTAssertTrue(plan.entries[0].issues.contains(.wordNotInSource))
        XCTAssertFalse(plan.canExecute)
    }

    func testADescriptorTakenFromTheSourcePasses() {
        let plan = NamingPlanner.plan([
            input(1, path: "SD/SD_Snare_WoodBlock.wav", category: "Drums/Snare",
                  descriptor: "WoodBlock")
        ])
        XCTAssertFalse(plan.entries[0].issues.contains(.wordNotInSource))
    }

    func testTheCheckLooksAtTheWholePathNotJustTheFilename() {
        // 描述常常寫在資料夾名上。
        let plan = NamingPlanner.plan([
            input(1, path: "Vintage Tape/kick_01.wav", category: "Drums/Kick",
                  descriptor: "Vintage")
        ])
        XCTAssertFalse(plan.entries[0].issues.contains(.wordNotInSource))
    }

    // MARK: - 逐資料夾算 descriptor

    func testDescriptorsAreDetectedPerFolderNotAcrossTheWholeLibrary() throws {
        // 命名慣例活在資料夾那一層。把整個庫當成一群，
        // 共同前綴會變成空的，descriptor 就全是廠商名。
        func row(_ id: Int64, _ path: String) -> NamingRow {
            NamingRow(id: id,
                      relativePath: path,
                      filename: (path as NSString).lastPathComponent,
                      fileExtension: "wav",
                      category: "Drums/Kick",
                      style: nil, bpm: nil, musicalKey: nil, isLoop: false)
        }
        let rows = [
            row(1, "AU Pack/AU_FP_kick_one_shot_dirt.wav"),
            row(2, "AU Pack/AU_FP_kick_one_shot_crisp.wav"),
            row(3, "AU Pack/AU_FP_kick_one_shot_tight.wav"),
            row(4, "AU Pack/AU_FP_kick_one_shot_wide.wav"),
            row(5, "SD Pack/SD_Kick_RoundThud.wav"),
            row(6, "SD Pack/SD_Kick_BigThud.wav"),
            row(7, "SD Pack/SD_Kick_Belly.wav"),
            row(8, "SD Pack/SD_Kick_SaySo.wav"),
        ]
        let plan = NamingPlanBuilder.build(
            rows: rows,
            roleTerms: NamingConventionDetector.roleTerms(from: PathEvidenceReader.rules),
            styleTerms: NamingConventionDetector.styleTerms(from: try TestSupport.styles()))

        let names = Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.soundId, $0.newName) })
        XCTAssertEqual(names[1], "Kick dirt 02.wav")
        XCTAssertEqual(names[5], "Kick RoundThud 07.wav")
        XCTAssertEqual(plan.withDescriptor, 8)
        XCTAssertTrue(plan.canExecute)
    }

    // MARK: - 統計與匯出

    func testCoverageCountsFilesThatGotADescriptor() {
        let plan = NamingPlanner.plan([
            input(1, path: "a/a.wav", category: "Drums/Kick", descriptor: nil),
            input(2, path: "a/b_dusty.wav", category: "Drums/Kick", descriptor: "dusty"),
        ])
        XCTAssertEqual(plan.total, 2)
        XCTAssertEqual(plan.withDescriptor, 1)
    }

    func testCsvPutsTheOriginalPathFirst() {
        let plan = NamingPlanner.plan([input(1, path: "a/a.wav", category: "Drums/Kick")])
        let csv = NamingPlanner.csv(plan)
        XCTAssertTrue(csv.hasPrefix("原始路徑,"))
        XCTAssertTrue(csv.contains("a/a.wav"))
        XCTAssertTrue(csv.contains("Kick 01.wav"))
    }

    func testCsvEscapesCommasInFilenames() {
        let plan = NamingPlanner.plan([
            input(1, path: "a/Steam Train, Brakes.wav", category: "Vehicles")
        ])
        XCTAssertTrue(NamingPlanner.csv(plan).contains("\"a/Steam Train, Brakes.wav\""))
    }
}

/// 編號凍結（M32c）。
///
/// 編號若每次重算，在排序中間插進一個新檔案，它後面每一個的號碼都會位移，
/// 整棵樹跟著改名——樹裡會多出一批名字不同、指向同一份資料的連結。
final class FrozenNumberTests: XCTestCase {

    private func input(_ id: Int64, path: String, category: String?, frozen: Int? = nil) -> NamingInput {
        NamingInput(soundId: id,
                    relativePath: path,
                    filename: (path as NSString).lastPathComponent,
                    fileExtension: "wav",
                    category: category,
                    style: nil, bpm: nil, musicalKey: nil, isLoop: false,
                    descriptor: nil,
                    frozenNumber: frozen)
    }

    func testANewFileInsertedInTheMiddleDoesNotShiftTheOnesAfterIt() {
        // 這就是凍結存在的理由。b 插在 a 與 c 中間，c 的號碼不可以從 2 變成 3。
        let plan = NamingPlanner.plan([
            input(1, path: "a.wav", category: "Drums/Kick", frozen: 1),
            input(2, path: "b.wav", category: "Drums/Kick"),
            input(3, path: "c.wav", category: "Drums/Kick", frozen: 2),
        ])
        let numbers = Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.soundId, $0.number) })
        XCTAssertEqual(numbers[1], 1)
        XCTAssertEqual(numbers[3], 2, "既有檔案的號碼不可以位移")
        XCTAssertEqual(numbers[2], 3, "新檔案拿的是還沒被用掉的號碼")
    }

    func testANewFileNeverTakesANumberThatIsFrozenLaterInTheOrder() {
        // 邊走邊發號的話，排在最前面的新檔案會拿到 1，
        // 但 1 已經被排在後面的某個檔案凍結了 → 兩個檔案同名。
        let plan = NamingPlanner.plan([
            input(1, path: "a.wav", category: "Drums/Kick"),
            input(2, path: "b.wav", category: "Drums/Kick", frozen: 1),
        ])
        XCTAssertTrue(plan.canExecute, "發出重複的號碼就會變成碰撞")
        let numbers = Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.soundId, $0.number) })
        XCTAssertNotEqual(numbers[1], numbers[2])
    }

    func testFrozenNumbersAreCountedPerFolder() {
        // 不同資料夾的 01 互不相干。
        let plan = NamingPlanner.plan([
            input(1, path: "a.wav", category: "Drums/Kick", frozen: 1),
            input(2, path: "b.wav", category: "Drums/Snare"),
        ])
        let numbers = Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.soundId, $0.number) })
        XCTAssertEqual(numbers[2], 1)
    }

    func testRunningTheSamePlanTwiceGivesTheSameNames() {
        // 第二次執行不該製造出一整批假的「變更」。
        let inputs = [
            input(1, path: "a.wav", category: "Drums/Kick", frozen: 1),
            input(2, path: "b.wav", category: "Drums/Kick", frozen: 2),
        ]
        XCTAssertEqual(NamingPlanner.plan(inputs).entries.map(\.newName),
                       NamingPlanner.plan(inputs).entries.map(\.newName))
    }
}
