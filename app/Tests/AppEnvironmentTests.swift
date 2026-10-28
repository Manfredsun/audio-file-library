import XCTest
@testable import FoleyLibrary

final class AppEnvironmentTests: XCTestCase {
    @MainActor
    func testHostDoesNotOpenPersistentServices() async {
        XCTAssertEqual(ProcessInfo.processInfo.environment["FOLEY_TEST_HOST"], "1")
        let environment = AppEnvironment()
        XCTAssertNil(environment.services, "測試宿主不得開啟或遷移正式資料庫")
        XCTAssertNil(environment.startupError)
    }
}
