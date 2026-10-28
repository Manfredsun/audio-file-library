import XCTest
@testable import FoleyLibrary

/// 複選的行為。全部是純函式，不需要資料庫也不需要 UI。
final class SoundSelectionTests: XCTestCase {

    private let page: [Int64] = [1, 2, 3, 4, 5]

    func testPlainClickReplacesTheWholeSelection() {
        var selection = SoundSelection()
        selection.selectAll(page)
        selection.replace(with: 3)
        XCTAssertEqual(selection.sortedIds, [3])
        XCTAssertEqual(selection.anchor, 3)
    }

    func testCommandClickAddsAndRemovesOneAtATime() {
        var selection = SoundSelection()
        selection.toggle(2)
        selection.toggle(4)
        XCTAssertEqual(selection.sortedIds, [2, 4])
        selection.toggle(2)
        XCTAssertEqual(selection.sortedIds, [4])
    }

    func testCommandClickKeepsTheDeselectedRowAsAnchor() {
        // Finder 是這樣。取消之後接著 shift 點擊，範圍要從剛剛那一列算起。
        var selection = SoundSelection()
        selection.toggle(2)
        selection.toggle(2)
        XCTAssertTrue(selection.isEmpty)
        XCTAssertEqual(selection.anchor, 2)
    }

    func testShiftClickSelectsTheRangeFromTheAnchor() {
        var selection = SoundSelection()
        selection.replace(with: 2)
        selection.extend(to: 4, in: page)
        XCTAssertEqual(selection.sortedIds, [2, 3, 4])
    }

    func testShiftClickWorksUpwardsToo() {
        var selection = SoundSelection()
        selection.replace(with: 4)
        selection.extend(to: 2, in: page)
        XCTAssertEqual(selection.sortedIds, [2, 3, 4])
    }

    func testRepeatedShiftClicksAllMeasureFromTheSameAnchor() {
        // 第二次 shift 點擊如果從上一次的終點算，選出來的範圍就不是人想的那個。
        var selection = SoundSelection()
        selection.replace(with: 2)
        selection.extend(to: 4, in: page)
        selection.extend(to: 5, in: page)
        XCTAssertEqual(selection.anchor, 2)
        XCTAssertEqual(selection.sortedIds, [2, 3, 4, 5])
    }

    // MARK: - 換頁

    func testSelectionSurvivesAPageChange() {
        // 41,293 個檔案、每頁 20 筆。選到一半換頁就被清掉的話複選等於沒用。
        var selection = SoundSelection()
        selection.selectAll(page)
        selection.selectAll([11, 12, 13])
        XCTAssertEqual(selection.count, 8)
    }

    func testShiftClickOnANewPageAddsInsteadOfWipingTheSelection() {
        // 錨點不在新的一頁上，算不出範圍——但既有的選取不可以被清掉。
        var selection = SoundSelection()
        selection.replace(with: 2)
        selection.extend(to: 4, in: page)
        selection.extend(to: 12, in: [11, 12, 13])
        XCTAssertEqual(selection.sortedIds, [2, 3, 4, 12])
        XCTAssertEqual(selection.anchor, 12)
    }

    func testSelectAllOnlyCoversTheCurrentPage() {
        var selection = SoundSelection()
        selection.selectAll(page)
        XCTAssertEqual(selection.sortedIds, page)
    }

    // MARK: - 清理

    func testPruneDropsIdsThatNoLongerExist() {
        var selection = SoundSelection()
        selection.selectAll(page)
        selection.prune(keeping: [1, 2, 3])
        XCTAssertEqual(selection.sortedIds, [1, 2, 3])
    }

    func testPruneClearsAnAnchorThatIsGone() {
        var selection = SoundSelection()
        selection.replace(with: 5)
        selection.prune(keeping: [1, 2])
        XCTAssertNil(selection.anchor)
    }

    func testOneItemIsNotMultipleSelection() {
        // 一個的時候維持原本的單選行為，批次列不該出現。
        var selection = SoundSelection()
        selection.replace(with: 1)
        XCTAssertFalse(selection.isMultiple)
        selection.toggle(2)
        XCTAssertTrue(selection.isMultiple)
    }

    func testBatchOrderIsStable() {
        var selection = SoundSelection()
        selection.toggle(5)
        selection.toggle(1)
        selection.toggle(3)
        XCTAssertEqual(selection.sortedIds, [1, 3, 5])
    }
}
