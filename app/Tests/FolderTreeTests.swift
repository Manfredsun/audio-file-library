import XCTest
@testable import FoleyLibrary

final class FolderTreeTests: XCTestCase {

    func testBuildsTopLevelFolders() {
        let tree = FolderTree.build(from: [
            (path: "Noise", count: 512),
            (path: "Whoosh", count: 54),
            (path: "Foley", count: 22)
        ])

        XCTAssertEqual(tree.map(\.name), ["Foley", "Noise", "Whoosh"], "應該照名稱排序")
        XCTAssertEqual(tree.first(where: { $0.name == "Noise" })?.count, 512)
    }

    func testNestedFoldersRollUpCounts() {
        let tree = FolderTree.build(from: [
            (path: "Foley/Doors", count: 10),
            (path: "Foley/Footsteps", count: 5),
            (path: "Foley", count: 2)
        ])

        let foley = try? XCTUnwrap(tree.first)
        XCTAssertEqual(foley?.name, "Foley")
        XCTAssertEqual(foley?.count, 17, "父資料夾的數量應該含子資料夾")
        XCTAssertEqual(foley?.children.map(\.name), ["Doors", "Footsteps"])
        XCTAssertEqual(foley?.children.first?.count, 10)
    }

    /// 中間層自己沒有檔案時仍然必須出現，否則使用者點不進去。
    func testIntermediateFolderWithoutOwnFilesStillAppears() {
        let tree = FolderTree.build(from: [
            (path: "A/B/C", count: 3)
        ])

        let a = try? XCTUnwrap(tree.first)
        XCTAssertEqual(a?.name, "A")
        XCTAssertEqual(a?.count, 3)
        let b = try? XCTUnwrap(a?.children.first)
        XCTAssertEqual(b?.name, "B")
        XCTAssertEqual(b?.children.first?.name, "C")
        XCTAssertEqual(b?.children.first?.path, "A/B/C")
    }

    func testRootLevelFilesAreNotAFolder() {
        let tree = FolderTree.build(from: [
            (path: "", count: 9),
            (path: "Noise", count: 1)
        ])

        XCTAssertEqual(tree.count, 1, "根目錄的檔案不該變成一個資料夾節點")
        XCTAssertEqual(tree.first?.name, "Noise")
    }

    func testFolderPathExtraction() {
        XCTAssertEqual(FolderPath.folder(of: "Noise/a.wav"), "Noise")
        XCTAssertEqual(FolderPath.folder(of: "A/B/C/x.wav"), "A/B/C")
        XCTAssertEqual(FolderPath.folder(of: "root.wav"), "")
    }
}
