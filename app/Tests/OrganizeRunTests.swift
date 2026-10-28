import XCTest
@testable import FoleyLibrary

/// 把命名計畫變成連結工作。
final class OrganizeRunTests: XCTestCase {

    private func row(_ id: Int64, library: Int64, root: String, path: String) -> NamingRow {
        NamingRow(id: id,
                  relativePath: path,
                  filename: (path as NSString).lastPathComponent,
                  fileExtension: "wav",
                  category: "Drums/Kick",
                  style: nil, bpm: nil, musicalKey: nil, isLoop: false,
                  filePath: "\(root)/\(path)", libraryId: library, libraryRoot: root)
    }

    private func plan(_ rows: [NamingRow]) -> NamingPlan {
        NamingPlanBuilder.build(rows: rows,
                                roleTerms: NamingConventionDetector.roleTerms(from: PathEvidenceReader.rules),
                                styleTerms: [])
    }

    func testTheTreeGoesUnderEachLibraryRoot() {
        // 硬連結必須跟原檔在同一個檔案系統上。放在庫根目錄底下自然滿足這條。
        let rows = [row(1, library: 7, root: "/Volumes/XD/Drums", path: "a/kick_dusty.wav")]
        let groups = OrganizeRun.groups(from: plan(rows), rows: rows)
        XCTAssertEqual(groups.first?.root, "/Volumes/XD/Drums/_Organized")
    }

    func testDifferentLibrariesGetSeparateGroups() {
        let rows = [
            row(1, library: 1, root: "/Volumes/XD/Drums", path: "a/kick_dusty.wav"),
            row(2, library: 2, root: "/Volumes/XD/FX", path: "b/kick_punchy.wav"),
        ]
        let groups = OrganizeRun.groups(from: plan(rows), rows: rows)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.root),
                       ["/Volumes/XD/Drums/_Organized", "/Volumes/XD/FX/_Organized"])
    }

    func testSourcePathIsTheOriginalFile() {
        // D-019：整理樹裡的名字會變，原始路徑永遠不變。連結的來源只能是原檔。
        let rows = [row(1, library: 1, root: "/Volumes/XD/Drums", path: "a/kick_dusty.wav")]
        let groups = OrganizeRun.groups(from: plan(rows), rows: rows)
        XCTAssertEqual(groups.first?.jobs.first?.sourcePath,
                       "/Volumes/XD/Drums/a/kick_dusty.wav")
    }

    func testBlockingIssuesAreLeftOutOfTheRun() {
        // 安全模型第三道：執行的只能是人看過那份 manifest 裡乾淨的部分。
        var planWithCollision = plan([
            row(1, library: 1, root: "/Volumes/XD/Drums", path: "a/kick_dusty.wav"),
            row(2, library: 1, root: "/Volumes/XD/Drums", path: "b/kick_punchy.wav"),
        ])
        planWithCollision.entries[0].issues.append(.collision)

        let rows = [row(1, library: 1, root: "/Volumes/XD/Drums", path: "a/kick_dusty.wav"),
                    row(2, library: 1, root: "/Volumes/XD/Drums", path: "b/kick_punchy.wav")]
        let groups = OrganizeRun.groups(from: planWithCollision, rows: rows)
        XCTAssertEqual(OrganizeRun.linkCount(groups), 1)
    }

    func testARowWithNoLibraryRootIsSkippedRatherThanGuessed() {
        // 不知道要建在哪就不建。猜一個位置去寫使用者的碟是不可接受的。
        var orphan = row(1, library: 0, root: "", path: "a/kick_dusty.wav")
        orphan.filePath = "/somewhere/kick_dusty.wav"
        let groups = OrganizeRun.groups(from: plan([orphan]), rows: [orphan])
        XCTAssertTrue(groups.isEmpty)
    }

    func testGroupOrderIsStable() {
        let rows = [
            row(1, library: 3, root: "/c", path: "a/kick_dusty.wav"),
            row(2, library: 1, root: "/a", path: "b/kick_punchy.wav"),
            row(3, library: 2, root: "/b", path: "c/kick_warm.wav"),
        ]
        let groups = OrganizeRun.groups(from: plan(rows), rows: rows)
        XCTAssertEqual(groups.map(\.libraryId), [1, 2, 3])
    }
}
