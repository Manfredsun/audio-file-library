import Foundation
import GRDB
import XCTest
@testable import FoleyLibrary

private final class BundleMarker {}

enum TestSupport {
    static var bundle: Bundle { Bundle(for: BundleMarker.self) }

    static func taxonomy() throws -> Taxonomy {
        try Taxonomy.load(from: bundle)
    }

    static func vocabulary() throws -> TagVocabulary {
        try TagVocabulary.load(from: bundle)
    }

    static func styles() throws -> StyleVocabulary {
        try StyleVocabulary.load(from: bundle)
    }

    static func textures() throws -> TextureVocabulary {
        try TextureVocabulary.load(from: bundle)
    }

    static func validator() throws -> OrganizerSchemaValidator {
        OrganizerSchemaValidator(taxonomy: try taxonomy(), vocabulary: try vocabulary())
    }

    /// 全新的 in-memory 資料庫。絕不碰使用者的真實音色庫（CLAUDE.md §41）。
    static func database(seeded: Bool = true) throws -> AppDatabase {
        try AppDatabase.makeInMemory(taxonomy: seeded ? taxonomy() : nil)
    }

    @discardableResult
    static func insertSound(into database: AppDatabase,
                            filename: String = "metal_door_04.wav") throws -> Sound {
        try database.writer.write { db in
            var library = Library(name: "Test", rootPath: "/tmp/test")
            try library.insert(db)
            var sound = Sound(libraryId: library.id ?? 0,
                              filePath: "/tmp/test/\(filename)",
                              relativePath: filename,
                              filename: filename,
                              fileExtension: "wav",
                              duration: 1.2)
            try sound.insert(db)
            return sound
        }
    }

    static func markdown(named name: String) throws -> String {
        guard let url = bundle.url(forResource: name, withExtension: "md") else {
            throw AppError.databaseError("測試資源缺少 \(name).md")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
