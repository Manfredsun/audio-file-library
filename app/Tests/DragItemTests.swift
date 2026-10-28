import UniformTypeIdentifiers
import XCTest
@testable import FoleyLibrary

/// 拖曳項目實際註冊了什麼型別。
///
/// 這組測試存在的理由很具體：`DragPathTests` 只驗了「拖曳給的是原始路徑」，
/// `MultiSelectStoreTests` 只驗了「放下之後會加進分頁」——中間那一段，
/// **拖曳項目帶不帶得動 URL**，從來沒有人驗過，而它正是壞掉的那一段。
///
/// `NSItemProvider(contentsOf:)` 只註冊檔案自己的型別，不註冊 public.file-url，
/// 所以 `dropDestination(for: URL.self)` 永遠收不到東西。拖進 Logic 好好的，
/// 拖進分頁沒反應，看起來像「複選壞了」，其實兩者無關。
final class DragItemTests: XCTestCase {

    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("drag-\(UUID().uuidString).wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: fileURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testDragItemCanBeLoadedAsAURL() {
        // 這一條就是壞掉的那一段。分頁的 dropDestination(for: URL.self) 靠它。
        let provider = FileActions.dragItem(path: fileURL.path)
        XCTAssertTrue(provider.canLoadObject(ofClass: URL.self),
                      "拖不出 URL 的話，分頁那一端永遠收不到東西")
    }

    func testDragItemRegistersTheFileUrlType() {
        let provider = FileActions.dragItem(path: fileURL.path)
        XCTAssertTrue(
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
            "public.file-url 是 SwiftUI 的 dropDestination 認的型別")
    }

    func testDragItemStillCarriesTheFileItselfForLogic() {
        // Logic 與 Finder 吃的是檔案本身的型別。修好分頁不可以把 DAW 弄壞。
        let provider = FileActions.dragItem(path: fileURL.path)
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains { $0 != UTType.fileURL.identifier },
                      "除了 file-url 之外還要有檔案本身的型別")
    }

    func testTheFileTypeIsOfferedBeforeTheUrlType() {
        // 先註冊的優先。檔案型別要排在前面，Logic 拿到的東西才跟以前一樣。
        let provider = FileActions.dragItem(path: fileURL.path)
        let identifiers = provider.registeredTypeIdentifiers
        guard let urlIndex = identifiers.firstIndex(of: UTType.fileURL.identifier) else {
            return XCTFail("沒有註冊 public.file-url")
        }
        XCTAssertGreaterThan(urlIndex, 0, "file-url 排到第一個的話會改變 DAW 拿到的東西")
    }

    func testAMissingFileGivesAnEmptyProviderInsteadOfCrashing() {
        let provider = FileActions.dragItem(path: "/tmp/does-not-exist-\(UUID().uuidString).wav")
        XCTAssertTrue(provider.registeredTypeIdentifiers.isEmpty)
    }

    func testTheDraggedUrlIsTheOriginalPath() {
        // D-019：拖曳永遠給原始路徑。修拖曳的時候最容易順手改掉這件事。
        let provider = FileActions.dragItem(path: fileURL.path)
        let expectation = expectation(description: "載入 URL")
        var loaded: URL?
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            loaded = url
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(loaded?.resolvingSymlinksInPath().path,
                       fileURL.resolvingSymlinksInPath().path)
    }
}
