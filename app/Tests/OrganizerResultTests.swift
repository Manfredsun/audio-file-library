import XCTest
@testable import FoleyLibrary

/// 直接使用 output-contract.md 中的官方範例。
final class OrganizerResultTests: XCTestCase {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    private let recognized = """
    {
      "status": "recognized",
      "display_name": "Heavy Metal Door Slam",
      "category": "Foley/Doors",
      "subcategory": "Metal Door",
      "tags": ["metal", "heavy", "slam", "indoor", "short"],
      "description": "Heavy metal door slam with a short resonant tail.",
      "confidence": 0.93,
      "needs_review": false,
      "alternative_categories": []
    }
    """

    private let uncertain = """
    {
      "status": "uncertain",
      "display_name": "Short Metallic Mechanical Impact",
      "category": "Unclassified",
      "subcategory": null,
      "tags": ["metal", "mechanical", "short"],
      "description": "Short metallic mechanical impact; the exact source is unclear.",
      "confidence": 0.46,
      "needs_review": true,
      "alternative_categories": ["Impacts/Metal", "Machines/Mechanical", "Foley/Doors"]
    }
    """

    private let unknown = """
    {
      "status": "unknown",
      "display_name": null,
      "category": "Unclassified",
      "subcategory": null,
      "tags": [],
      "description": null,
      "confidence": 0.18,
      "needs_review": true,
      "alternative_categories": []
    }
    """

    func testDecodesRecognizedExample() throws {
        let validator = try TestSupport.validator()
        let result = try validator.decodeAndValidate(data(recognized))
        XCTAssertEqual(result.status, .recognized)
        XCTAssertEqual(result.category, "Foley/Doors")
        XCTAssertEqual(result.subcategory, "Metal Door")
        XCTAssertEqual(result.tags.count, 5)
        XCTAssertFalse(result.needsReview)
    }

    func testDecodesUncertainExample() throws {
        let validator = try TestSupport.validator()
        let result = try validator.decodeAndValidate(data(uncertain))
        XCTAssertEqual(result.status, .uncertain)
        XCTAssertEqual(result.category, Taxonomy.unclassified)
        XCTAssertTrue(result.needsReview)
        XCTAssertEqual(result.alternativeCategories.count, 3)
    }

    func testDecodesUnknownExample() throws {
        let validator = try TestSupport.validator()
        let result = try validator.decodeAndValidate(data(unknown))
        XCTAssertEqual(result.status, .unknown)
        XCTAssertNil(result.displayName)
        XCTAssertNil(result.summary)
        XCTAssertTrue(result.tags.isEmpty)
        XCTAssertTrue(result.needsReview)
    }

    func testMockEngineFixturesAreAllValid() async throws {
        let validator = try TestSupport.validator()
        for fixture in MockOrganizerEngine.defaultFixtures {
            XCTAssertNoThrow(try validator.validate(fixture),
                             "假引擎的樣本必須符合契約：\(fixture.displayName ?? "nil")")
        }
    }

    /// examples.md 第 4 例：檔名與音訊衝突時，status 是 recognized 但仍需複查。
    /// 這就是 needs_review 不能由 status 推導的證據（DECISIONS D-004）。
    func testNeedsReviewIsIndependentOfStatus() throws {
        let fixture = MockOrganizerEngine.footsteps
        XCTAssertEqual(fixture.status, .recognized)
        XCTAssertTrue(fixture.needsReview)
    }
}
