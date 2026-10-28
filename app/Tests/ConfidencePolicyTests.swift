import XCTest
@testable import FoleyLibrary

final class ConfidencePolicyTests: XCTestCase {

    func testBands() {
        let policy = ConfidencePolicy.default
        XCTAssertEqual(policy.band(for: 0.95), .strong)
        XCTAssertEqual(policy.band(for: 0.70), .moderate)
        XCTAssertEqual(policy.band(for: 0.50), .weak)
        XCTAssertEqual(policy.band(for: 0.10), .veryWeak)
    }

    /// 政策只能把 needsReview 由 false 提升為 true，永遠不能降級。
    func testPolicyNeverDowngradesOrganizerReviewFlag() {
        let policy = ConfidencePolicy.default
        // examples.md 第 4 例：高信心但 Organizer 明確要求複查
        XCTAssertTrue(policy.effectiveNeedsReview(for: MockOrganizerEngine.footsteps))
    }

    func testLowConfidenceTriggersReviewEvenWhenOrganizerSaysNo() {
        let policy = ConfidencePolicy.default
        let result = OrganizerResult(status: .suggested,
                                     displayName: "Small Ceramic Object Tap",
                                     category: "Foley/Props",
                                     tags: ["ceramic", "tap"],
                                     confidence: 0.55,
                                     needsReview: false)
        XCTAssertTrue(policy.effectiveNeedsReview(for: result))
    }

    func testHighConfidenceRecognizedDoesNotNeedReview() {
        let policy = ConfidencePolicy.default
        XCTAssertFalse(policy.effectiveNeedsReview(for: MockOrganizerEngine.doorSlam))
    }

    func testThresholdsAreConfigurable() {
        var strict = ConfidencePolicy()
        strict.reviewBelow = 0.99
        XCTAssertTrue(strict.effectiveNeedsReview(for: MockOrganizerEngine.doorSlam))
    }
}
