import XCTest
import CryptoKit
@testable import FoleyLibrary

/// markdown 是 source of truth，json 由它產生。
/// 這個測試確保兩者沒有漂移——漂移不會有其他徵兆，只能靠測試擋（CLAUDE.md §53）。
final class TaxonomySyncTests: XCTestCase {

    private func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func testTaxonomyJSONMatchesMarkdown() throws {
        let taxonomy = try TestSupport.taxonomy()
        let markdown = try TestSupport.markdown(named: "taxonomy")
        XCTAssertEqual(taxonomy.sourceSHA256, sha256(markdown),
                       "taxonomy.md 已變更但 taxonomy.json 沒有重新產生。執行：python3 scripts/generate-schemas.py")
    }

    func testTagVocabularyJSONMatchesMarkdown() throws {
        let vocabulary = try TestSupport.vocabulary()
        let markdown = try TestSupport.markdown(named: "tagging-rules")
        XCTAssertEqual(vocabulary.sourceSHA256, sha256(markdown),
                       "tagging-rules.md 已變更但 tag-vocabulary.json 沒有重新產生。執行：python3 scripts/generate-schemas.py")
    }

    func testTaxonomyShape() throws {
        let taxonomy = try TestSupport.taxonomy()
        XCTAssertEqual(taxonomy.topLevel.count, 15)
        XCTAssertTrue(taxonomy.topLevel.contains("Unclassified"))
        XCTAssertTrue(taxonomy.topLevel.contains("Designed"),
                      "設計音（whoosh／riser／texture）在原本的 12 類裡沒有家")
        XCTAssertTrue(taxonomy.isValidPath("Designed/Whoosh"))
        XCTAssertTrue(taxonomy.topLevel.contains("Drums"),
                      "sample pack 的鼓在原本的分類裡沒有家")
        XCTAssertTrue(taxonomy.isValidPath("Drums/Kick"))
        XCTAssertTrue(taxonomy.isValidPath("Instruments/Melodic Loop"))
        XCTAssertTrue(taxonomy.isValidPath("Foley"))
        XCTAssertTrue(taxonomy.isValidPath("Foley/Doors"))
        XCTAssertTrue(taxonomy.isValidPath("Impacts/Metal"))
        XCTAssertFalse(taxonomy.isValidPath("Foley/Spaceship"))
        XCTAssertFalse(taxonomy.isValidPath("Foley/Doors/Metal"), "不支援三層路徑")
        XCTAssertFalse(taxonomy.isValidPath(""))
    }

    func testTagVocabularyContainsCanonicalTerms() throws {
        let vocabulary = try TestSupport.vocabulary()
        for tag in ["metal", "wood", "slam", "heavy", "indoor", "short"] {
            XCTAssertTrue(vocabulary.isCanonical(tag), "\(tag) 應該是 canonical 標籤")
        }
        XCTAssertFalse(vocabulary.isCanonical("metallic"), "同義詞不應該是 canonical")
    }
}
