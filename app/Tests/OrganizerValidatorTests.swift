import XCTest
@testable import FoleyLibrary

/// 不合法的輸出必須在落庫之前就被擋下來（output-contract.md §6）。
final class OrganizerValidatorTests: XCTestCase {

    private func validator() throws -> OrganizerSchemaValidator {
        try TestSupport.validator()
    }

    private func assertRejects(_ json: String,
                               _ expected: OrganizerValidationError,
                               file: StaticString = #filePath,
                               line: UInt = #line) throws {
        let validator = try self.validator()
        do {
            _ = try validator.decodeAndValidate(Data(json.utf8))
            XCTFail("應該被拒絕但通過了", file: file, line: line)
        } catch let error as OrganizerValidationError {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    private func base(status: String = "recognized",
                      category: String = "Foley/Doors",
                      tags: String = "[\"metal\"]",
                      confidence: String = "0.9",
                      needsReview: String = "false",
                      alternatives: String = "[]",
                      displayName: String = "\"Heavy Metal Door Slam\"",
                      description: String = "\"A door.\"",
                      extra: String = "") -> String {
        """
        {
          "status": "\(status)",
          "display_name": \(displayName),
          "category": "\(category)",
          "subcategory": null,
          "tags": \(tags),
          "description": \(description),
          "confidence": \(confidence),
          "needs_review": \(needsReview),
          "alternative_categories": \(alternatives)\(extra)
        }
        """
    }

    func testRejectsUnexpectedField() throws {
        try assertRejects(base(extra: ",\n  \"rename_file\": true"),
                          .unexpectedFields(["rename_file"]))
    }

    func testRejectsMissingField() throws {
        let json = """
        {"status": "recognized", "category": "Foley/Doors", "tags": [], "confidence": 0.9}
        """
        let validator = try self.validator()
        XCTAssertThrowsError(try validator.decodeAndValidate(Data(json.utf8)))
    }

    func testRejectsUnknownStatus() throws {
        try assertRejects(base(status: "probably"), .invalidStatus("probably"))
    }

    func testRejectsConfidenceAboveOne() throws {
        try assertRejects(base(confidence: "1.5"), .confidenceOutOfRange(1.5))
    }

    func testRejectsDuplicateTags() throws {
        try assertRejects(base(tags: "[\"metal\", \"Metal\"]"), .duplicateTags(["metal"]))
    }

    func testRejectsTooManyTags() throws {
        let many = (1...13).map { "\"tag\($0)\"" }.joined(separator: ", ")
        try assertRejects(base(tags: "[\(many)]"), .tooManyTags(13))
    }

    func testRejectsCategoryOutsideTaxonomy() throws {
        try assertRejects(base(category: "Foley/Spaceship"), .unknownCategory("Foley/Spaceship"))
    }

    func testRejectsInventedTopLevelCategory() throws {
        try assertRejects(base(category: "Spaceships"), .unknownCategory("Spaceships"))
    }

    func testRejectsAlternativeOutsideTaxonomy() throws {
        try assertRejects(base(alternatives: "[\"Impacts/Lasers\"]"),
                          .unknownAlternativeCategory("Impacts/Lasers"))
    }

    func testRejectsTooManyAlternatives() throws {
        try assertRejects(base(alternatives: "[\"Foley\", \"Impacts\", \"Machines\", \"Nature\"]"),
                          .tooManyAlternatives(4))
    }

    func testRejectsFailedWithConfidence() throws {
        try assertRejects(base(status: "failed",
                               category: "Unclassified",
                               tags: "[]",
                               confidence: "0.4",
                               needsReview: "true",
                               displayName: "null",
                               description: "null"),
                          .failedMustHaveZeroConfidence(0.4))
    }

    func testRejectsFailedThatInterpretsAudio() throws {
        try assertRejects(base(status: "failed",
                               category: "Unclassified",
                               tags: "[]",
                               confidence: "0",
                               needsReview: "true",
                               displayName: "\"Heavy Metal Door Slam\"",
                               description: "null"),
                          .failedMustNotInterpretAudio)
    }

    func testRejectsUnknownWithRealCategory() throws {
        try assertRejects(base(status: "unknown",
                               category: "Foley/Doors",
                               tags: "[]",
                               confidence: "0.2",
                               needsReview: "true",
                               displayName: "null",
                               description: "null"),
                          .unknownMustBeUnclassified("Foley/Doors"))
    }

    func testRejectsUncertainWithoutReview() throws {
        try assertRejects(base(status: "uncertain",
                               category: "Unclassified",
                               tags: "[\"metal\"]",
                               confidence: "0.45",
                               needsReview: "false",
                               displayName: "\"Metallic Impact\"",
                               description: "\"Unclear.\""),
                          .uncertainMustNeedReview)
    }

    func testAcceptsValidResult() throws {
        let validator = try self.validator()
        XCTAssertNoThrow(try validator.decodeAndValidate(Data(base().utf8)))
    }

    func testNonCanonicalTagsAreFlaggedNotRejected() throws {
        let validator = try self.validator()
        let result = OrganizerResult(status: .recognized,
                                     displayName: "Odd Sound",
                                     category: "Foley/Props",
                                     tags: ["metal", "clanky"],
                                     confidence: 0.8,
                                     needsReview: false)
        XCTAssertNoThrow(try validator.validate(result))
        XCTAssertEqual(validator.nonCanonicalTags(in: result), ["clanky"])
    }
}
