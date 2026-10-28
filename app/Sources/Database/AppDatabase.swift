import Foundation
import GRDB

/// Swift 應用程式獨佔資料庫的擁有權（AGENTS.md §26）。
final class AppDatabase {
    let writer: any DatabaseWriter
    /// 檔案路徑。備份要用（in-memory 資料庫沒有路徑，所以是 optional）。
    private(set) var path: String?

    init(_ writer: any DatabaseWriter, path: String? = nil, seedTaxonomy taxonomy: Taxonomy? = nil) throws {
        self.writer = writer
        self.path = path
        try AppMigrations.migrator.migrate(writer)
        if let taxonomy {
            try writer.write { db in
                _ = try CategorySeeder.seedIfNeeded(taxonomy: taxonomy, in: db)
            }
        }
    }

    /// 正式路徑：~/Library/Application Support/<bundle id>/library.sqlite
    static func makeShared(taxonomy: Taxonomy?) throws -> AppDatabase {
        let fm = FileManager.default
        let support = try fm.url(for: .applicationSupportDirectory,
                                 in: .userDomainMask,
                                 appropriateFor: nil,
                                 create: true)
        let bundleId = Bundle.main.bundleIdentifier ?? "com.manfredsun.foleylibrary"
        let folder = support.appendingPathComponent(bundleId, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let url = folder.appendingPathComponent("library.sqlite")
        var config = Configuration()
        config.foreignKeysEnabled = true

        AppLog.database.info("開啟資料庫：\(url.path, privacy: .public)")
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        return try AppDatabase(queue, path: url.path, seedTaxonomy: taxonomy)
    }

    /// 測試用。絕不使用使用者的真實音色庫（CLAUDE.md §41）。
    static func makeInMemory(taxonomy: Taxonomy? = nil) throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        return try AppDatabase(queue, seedTaxonomy: taxonomy)
    }
}

/// 把受控 taxonomy 寫進 categories 表。執行期的 AI 不得新增分類（AGENTS.md §20）。
enum CategorySeeder {
    @discardableResult
    static func seedIfNeeded(taxonomy: Taxonomy, in db: Database) throws -> Int {
        var inserted = 0
        for (topIndex, top) in taxonomy.topLevel.enumerated() {
            let parentId: Int64
            if let existing = try Category.filter(Category.Columns.path == top).fetchOne(db) {
                parentId = existing.id ?? 0
            } else {
                var category = Category(name: top, parentId: nil, path: top, sortOrder: topIndex)
                try category.insert(db)
                parentId = category.id ?? 0
                inserted += 1
            }

            for (subIndex, sub) in (taxonomy.categories[top] ?? []).enumerated() {
                let path = "\(top)/\(sub)"
                if try Category.filter(Category.Columns.path == path).fetchOne(db) != nil { continue }
                var child = Category(name: sub, parentId: parentId, path: path, sortOrder: subIndex)
                try child.insert(db)
                inserted += 1
            }
        }
        if inserted > 0 {
            AppLog.database.info("seed 分類 \(inserted, privacy: .public) 筆")
        }
        return inserted
    }
}
