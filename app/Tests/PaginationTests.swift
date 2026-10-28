import XCTest
@testable import FoleyLibrary

/// 頁碼視窗的真值表。
///
/// 這是純邏輯，沒有藉口不把邊界全部列出來。
final class PaginationTests: XCTestCase {

    private func render(_ total: Int, _ current: Int, window: Int = 2) -> String {
        Pagination.tokens(total: total, current: current, window: window).map {
            switch $0 {
            case .page(let n): return "\(n)"
            case .gap: return "…"
            }
        }.joined(separator: " ")
    }

    func testEmptyWhenThereAreNoPages() {
        XCTAssertTrue(Pagination.tokens(total: 0, current: 1).isEmpty)
        XCTAssertTrue(Pagination.tokens(total: -3, current: 1).isEmpty)
    }

    func testSinglePage() {
        XCTAssertEqual(render(1, 1), "1")
    }

    func testShortRunsShowEveryPage() {
        XCTAssertEqual(render(5, 1), "1 2 3 4 5")
        XCTAssertEqual(render(5, 3), "1 2 3 4 5")
        XCTAssertEqual(render(5, 5), "1 2 3 4 5")
    }

    func testAtTheStartOfALongRun() {
        XCTAssertEqual(render(2065, 1), "1 2 3 … 2065")
    }

    func testInTheMiddleOfALongRun() {
        XCTAssertEqual(render(2065, 201), "1 … 199 200 201 202 203 … 2065")
    }

    func testAtTheEndOfALongRun() {
        XCTAssertEqual(render(2065, 2065), "1 … 2063 2064 2065")
    }

    func testEllipsisIsNotUsedWhenItWouldHideExactlyOnePage() {
        // 「1 … 3 4 5」裡的 … 就是第 2 頁，顯示出來比省略好。
        XCTAssertEqual(render(20, 4), "1 2 3 4 5 6 … 20")
        XCTAssertFalse(render(20, 4).contains("…1"))
    }

    func testEllipsisAppearsOnBothSidesWhenNeeded() {
        let output = render(100, 50)
        XCTAssertEqual(output, "1 … 48 49 50 51 52 … 100")
        XCTAssertEqual(output.filter { $0 == "…" }.count, 2)
    }

    func testCurrentPageIsAlwaysPresent() {
        for total in [1, 2, 7, 13, 404, 2065] {
            for current in [1, total / 2, total] where current >= 1 {
                let tokens = Pagination.tokens(total: total, current: current)
                XCTAssertTrue(tokens.contains(.page(current)),
                              "total=\(total) current=\(current) 少了目前頁")
                XCTAssertTrue(tokens.contains(.page(1)), "total=\(total) 少了第一頁")
                XCTAssertTrue(tokens.contains(.page(total)), "total=\(total) 少了最後一頁")
            }
        }
    }

    func testOutOfRangeCurrentIsClamped() {
        XCTAssertEqual(render(10, 0), render(10, 1))
        XCTAssertEqual(render(10, 999), render(10, 10))
    }

    func testPageNumbersAreStrictlyIncreasingAndUnique() {
        for total in [3, 9, 50, 2065] {
            for current in stride(from: 1, through: total, by: max(1, total / 7)) {
                let pages = Pagination.tokens(total: total, current: current).compactMap {
                    if case .page(let n) = $0 { return n } else { return nil }
                }
                XCTAssertEqual(pages, pages.sorted(), "total=\(total) current=\(current) 順序不對")
                XCTAssertEqual(Set(pages).count, pages.count, "total=\(total) current=\(current) 有重複")
            }
        }
    }

    func testNoGapSitsAtEitherEnd() {
        for total in [1, 5, 40, 2065] {
            for current in [1, total] {
                let tokens = Pagination.tokens(total: total, current: current)
                XCTAssertNotEqual(tokens.first, .gap)
                XCTAssertNotEqual(tokens.last, .gap)
            }
        }
    }

    func testWiderWindowShowsMoreNeighbours() {
        XCTAssertEqual(render(100, 50, window: 4), "1 … 46 47 48 49 50 51 52 53 54 … 100")
    }
}
