import Foundation
import GRDB

/// Sidebar 的篩選條件。組合式設計，不要寫死組合（CLAUDE.md §25）。
/// 顯示用的標籤，帶來源。
struct SoundTagView: Identifiable, Equatable, Hashable {
    let id: Int64
    let name: String
    let canonicalName: String
    let source: MetadataSource
}

enum SoundFilter: Equatable, Hashable {
    case all
    case favorites
    case needsReview
    case unclassified
    case analysisFailed
    case library(Int64)
    /// 一個資料夾及其所有子資料夾。
    case folder(libraryId: Int64, path: String)
    /// 虛擬資料夾（分頁）。內容與順序都是使用者手動決定的。
    case collection(Int64)
    /// 一個音樂風格。風格是獨立面向，跟分類正交（D-014）。
    case style(String)
    case texture(String)
    /// 一個分類路徑及其子分類（M41）。
    ///
    /// 包含兩種音效，**兩者不重疊**：
    ///   - 已確定：`category_id` 指向這個分類（人工或已接受的建議）
    ///   - 建議：還沒有任何已確定分類，而最新一次分析的待處理建議落在這個分類
    /// 已確定分類永遠優先：人工設成 Foley/Props 的音效，就算建議是 Foley/Doors，
    /// 也只會出現在 Props 底下；人工明確設成「未分類」的也不會被建議拉進來
    /// （D-007 的延伸）。這個篩選只是檢視，不寫任何欄位。
    case category(String)

    var title: String {
        switch self {
        case .all:            return L10n.tr("All Sounds")
        case .favorites:      return L10n.tr("Favorites")
        case .needsReview:    return L10n.tr("Needs Review")
        case .unclassified:   return L10n.tr("Unclassified")
        case .analysisFailed: return L10n.tr("Analysis Failed")
        case .library:        return L10n.tr("Library")
        case .folder(_, let path):
            return path.isEmpty ? L10n.tr("Root") : (path.split(separator: "/").last.map(String.init) ?? path)
        case .collection:     return L10n.tr("Collection")
        case .style(let name): return BuiltinNames.style(name)
        case .texture(let name): return BuiltinNames.texture(name)
        case .category(let path): return BuiltinNames.category(path)
        }
    }

    var systemImage: String {
        switch self {
        case .all:            return "waveform"
        case .favorites:      return "star"
        case .needsReview:    return "exclamationmark.triangle"
        case .unclassified:   return "questionmark.folder"
        case .analysisFailed: return "xmark.octagon"
        case .library:        return "externaldrive"
        case .folder:         return "folder"
        case .collection:     return "tray.full"
        case .style:          return "guitars"
        case .texture:        return "square.grid.3x3"
        case .category:       return "tag"
        }
    }
}

/// 判斷一個音效是否屬於某個分頁。
private let EXISTS_IN_COLLECTION = """
    EXISTS (SELECT 1 FROM collection_sounds cs
             WHERE cs.sound_id = sounds.id AND cs.collection_id = ?)
    """

/// 分類篩選（M41）。參數依序：path、path 的子分類下界、上界，兩組。
///
/// 子分類用範圍比較（`>= 'Drums/' AND < 'Drums0'`，'0' 是 '/' 的下一個字元）而不是 LIKE：
/// LIKE 預設不分大小寫，用不到 BINARY 索引。
///
/// 建議那一半只看**最新一次分析**，跟 ReviewService 的批次接受同一個定義——
/// 重跑過的音效不能被舊分析的建議拉進來。
private let IN_CATEGORY = """
    (sounds.category_id IN (SELECT c.id FROM categories c
                             WHERE c.path = ? OR (c.path >= ? AND c.path < ?))
     OR (sounds.category_id IS NULL
         AND (sounds.category_source IS NULL OR sounds.category_source <> 'manual')
         AND sounds.id IN (
           SELECT a.sound_id
             FROM organizer_suggestions g
             JOIN organizer_analysis a ON a.id = g.analysis_id
             JOIN categories c ON c.path = g.value
            WHERE g.field = 'category' AND g.status = 'suggested'
              AND (g.value = ? OR (g.value >= ? AND g.value < ?))
              AND a.id = (SELECT b.id FROM organizer_analysis b
                           WHERE b.sound_id = a.sound_id
                           ORDER BY b.started_at DESC, b.id DESC LIMIT 1))))
    """

/// `IN_CATEGORY` 的參數。
private func categoryArguments(_ path: String) -> StatementArguments {
    let lower = path + "/"
    let upper = path + "0"
    return [path, lower, upper, path, lower, upper]
}

/// 分頁內的手動排序。
private let COLLECTION_ORDER = """
    (SELECT cs.sort_order FROM collection_sounds cs
      WHERE cs.sound_id = sounds.id AND cs.collection_id = ?)
    """

struct SoundRepository {
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func insert(_ sound: Sound) throws -> Sound {
        try database.writer.write { db in
            var copy = sound
            try copy.insert(db)
            return copy
        }
    }

    private func request(filter: SoundFilter,
                         search: String,
                         filters: SoundFilters) -> QueryInterfaceRequest<Sound> {
        var request = Sound.all()

        switch filter {
        case .all:
            break
        case .favorites:
            request = request.filter(Sound.Columns.favorite == true)
        case .needsReview:
            request = request.filter(Sound.Columns.needsReview == true)
        case .unclassified:
            request = request.filter(Sound.Columns.categoryId == nil)
        case .analysisFailed:
            request = request.filter(Sound.Columns.analysisStatus == AnalysisStatus.failed.rawValue)
        case .library(let id):
            request = request.filter(Sound.Columns.libraryId == id)
        case .folder(let libraryId, let path):
            request = request.filter(Sound.Columns.libraryId == libraryId)
            if !path.isEmpty {
                request = request.filter(
                    Sound.Columns.folderPath == path
                    || Sound.Columns.folderPath.like("\(path)/%")
                )
            }
        case .collection(let id):
            request = request.filter(sql: EXISTS_IN_COLLECTION, arguments: [id])
        case .style(let name):
            request = request.filter(Sound.Columns.style == name)
        case .texture(let name):
            request = request.filter(Sound.Columns.texture == name)
        case .category(let path):
            request = request.filter(sql: IN_CATEGORY, arguments: categoryArguments(path))
        }

        // --- 屬性篩選 ---
        if filters.favoritesOnly {
            request = request.filter(Sound.Columns.favorite == true)
        }
        if filters.minRating > 0 {
            request = request.filter(sql: "rating >= ?", arguments: [filters.minRating])
        }
        if let range = filters.duration.range {
            request = request.filter(sql: "duration IS NOT NULL AND duration >= ? AND duration < ?",
                                     arguments: [range.lower, range.upper])
        }
        if !filters.fileTypes.isEmpty {
            request = request.filter(filters.fileTypes.contains(Column("file_extension")))
        }
        switch filters.loop {
        case .any:      break
        case .loops:    request = request.filter(Sound.Columns.isLoop == true)
        case .oneShots: request = request.filter(Sound.Columns.isLoop == false)
        }
        if let range = filters.tempo.range {
            // bpm IS NULL 的不算——「沒有節拍」不等於「節拍是 0」。
            request = request.filter(sql: "bpm IS NOT NULL AND bpm >= ? AND bpm < ?",
                                     arguments: [range.lower, range.upper])
        }

        // --- 搜尋：詞與詞之間是 AND，欄位之間是 OR ---
        for term in SearchQuery.terms(search) {
            let pattern = "%\(term)%"
            let aliases = BuiltinNames.matching(term)
            func member(_ column: String, _ values: [String]) -> String {
                values.isEmpty ? "0" : column + " IN (" + Array(repeating: "?", count: values.count).joined(separator: ",") + ")"
            }
            let categoryAlias = aliases.categories.isEmpty ? "0" : "sounds.category_id IN (SELECT id FROM categories WHERE " + member("path", aliases.categories) + ")"
            let styleAlias = member("sounds.style", aliases.styles)
            let textureAlias = member("sounds.texture", aliases.textures)
            request = request.filter(sql: """
                (sounds.filename LIKE ?
                 OR sounds.display_name LIKE ?
                 OR sounds.relative_path LIKE ?
                 OR sounds.subcategory LIKE ?
                 OR sounds.style LIKE ?
                 OR sounds.texture LIKE ?
                 OR sounds.musical_key LIKE ?
                 OR sounds.notes LIKE ?
                 OR EXISTS (SELECT 1 FROM categories c
                             WHERE c.id = sounds.category_id AND c.path LIKE ?)
                 OR EXISTS (SELECT 1 FROM sound_tags st
                              JOIN tags t ON t.id = st.tag_id
                             WHERE st.sound_id = sounds.id AND t.canonical_name LIKE ?)
                 OR \(categoryAlias) OR \(styleAlias) OR \(textureAlias))
                """,
                arguments: StatementArguments(Array(repeating: pattern, count: 10) + aliases.categories + aliases.styles + aliases.textures))
        }

        return request
    }

    /// 排序跟著篩選條件走。
    ///
    /// 一般檢視依相對路徑排，讓子資料夾在清單上聚在一起——照檔名排的話，
    /// 巢狀結構會被打散成看不出來源的一長串。
    ///
    /// 分頁例外：照使用者手動排的 sort_order。**這是規格不是偏好**——
    /// 分頁存在的意義就是你自己決定順序，程式把它重排掉就毀了整個功能。
    private func ordered(_ request: QueryInterfaceRequest<Sound>,
                         filter: SoundFilter) -> QueryInterfaceRequest<Sound> {
        switch filter {
        case .collection(let id):
            return request.order(sql: COLLECTION_ORDER, arguments: [id])
        default:
            return request.order(Column("relative_path").asc, Sound.Columns.filename.asc)
        }
    }

    func fetch(filter: SoundFilter,
               search: String = "",
               filters: SoundFilters = SoundFilters(),
               limit: Int = 20,
               offset: Int = 0) throws -> [Sound] {
        try database.writer.read { db in
            try ordered(request(filter: filter, search: search, filters: filters), filter: filter)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }

    /// 目前檢視的**全部** id，不分頁。
    ///
    /// 「把這個檢視加進分頁」需要整份清單而不是當前這 20 筆。
    /// 41,293 筆的 id 陣列約 330 KB，記憶體吃得下。
    func allIds(filter: SoundFilter,
                search: String = "",
                filters: SoundFilters = SoundFilters()) throws -> [Int64] {
        try database.writer.read { db in
            try ordered(request(filter: filter, search: search, filters: filters), filter: filter)
                .fetchAll(db)
                .compactMap(\.id)
        }
    }

    /// 命名預覽要的東西：整份清單 + 分類路徑，一次 SQL 取完。
    ///
    /// 不重用 `fetch` 是因為它回的是 `Sound`，裡面只有 `categoryId`；
    /// 41,293 筆逐筆再查一次分類路徑是四萬次查詢。
    func namingRows(filter: SoundFilter,
                    search: String = "",
                    filters: SoundFilters = SoundFilters()) throws -> [NamingRow] {
        let ids = try allIds(filter: filter, search: search, filters: filters)
        guard ids.isEmpty == false else { return [] }
        return try database.writer.read { db in
            var rows: [NamingRow] = []
            rows.reserveCapacity(ids.count)
            // id 一次全塞進 IN 會超出 SQLite 的變數上限，分批取。
            for chunk in stride(from: 0, to: ids.count, by: 500).map({
                Array(ids[$0..<min($0 + 500, ids.count)])
            }) {
                let placeholders = chunk.map { _ in "?" }.joined(separator: ",")
                let fetched = try Row.fetchAll(db, sql: """
                    SELECT s.id, s.relative_path, s.filename, s.file_extension,
                           s.style, s.bpm, s.musical_key, s.is_loop, s.file_path,
                           s.library_id, s.organized_number, s.organized_folder,
                           c.path AS category_path, l.root_path AS library_root
                      FROM sounds s
                      LEFT JOIN categories c ON c.id = s.category_id
                      LEFT JOIN libraries l ON l.id = s.library_id
                     WHERE s.id IN (\(placeholders))
                    """, arguments: StatementArguments(chunk))
                rows.append(contentsOf: fetched.map(NamingRow.init(row:)))
            }
            // 順序要穩定：編號依原始路徑排序決定（dev-plan §6）。
            return rows.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        }
    }

    /// 實際出現過的風格與各自的數量，多的在前。
    ///
    /// 側欄要靠這個列出風格。M27 算出了 4,565 個音效的風格，
    /// 但在這個方法出現之前，介面上沒有任何地方用得到它。
    func styleCounts() throws -> [(style: String, count: Int)] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT style, COUNT(*) AS n FROM sounds
                 WHERE style IS NOT NULL AND style <> ''
                 GROUP BY style ORDER BY n DESC, style
                """)
                .map { (style: $0["style"] ?? "", count: $0["n"] ?? 0) }
        }
    }

    /// 實際出現過的材質與各自的數量，多的在前。側欄靠這個列出材質。
    func textureCounts() throws -> [(texture: String, count: Int)] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT texture, COUNT(*) AS n FROM sounds
                 WHERE texture IS NOT NULL AND texture <> ''
                 GROUP BY texture ORDER BY n DESC, texture
                """)
                .map { (texture: $0["texture"] ?? "", count: $0["n"] ?? 0) }
        }
    }

    /// 每個分類路徑的音效數，分成已確定與建議兩欄（M41）。
    ///
    /// 只回傳至少有一筆的路徑。「建議」只算還沒有已確定分類的音效，
    /// 所以同一個音效不會同時算在兩欄——跟 `.category` 篩選的定義一致。
    func categoryCounts() throws -> [CategoryCount] {
        try database.writer.read { db in
            var byPath: [String: CategoryCount] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT c.path AS path, COUNT(*) AS n
                  FROM sounds s JOIN categories c ON c.id = s.category_id
                 GROUP BY c.path
                """) {
                let path: String = row["path"]
                byPath[path, default: CategoryCount(path: path)].confirmed = row["n"]
            }
            for row in try Row.fetchAll(db, sql: """
                SELECT g.value AS path, COUNT(*) AS n
                  FROM organizer_suggestions g
                  JOIN organizer_analysis a ON a.id = g.analysis_id
                  JOIN categories c ON c.path = g.value
                  JOIN sounds s ON s.id = a.sound_id
                 WHERE g.field = 'category' AND g.status = 'suggested'
                   AND s.category_id IS NULL
                   AND (s.category_source IS NULL OR s.category_source <> 'manual')
                   AND a.id = (SELECT b.id FROM organizer_analysis b
                                WHERE b.sound_id = a.sound_id
                                ORDER BY b.started_at DESC, b.id DESC LIMIT 1)
                 GROUP BY g.value
                """) {
                let path: String = row["path"]
                byPath[path, default: CategoryCount(path: path)].suggested = row["n"]
            }
            return byPath.values.sorted { $0.path < $1.path }
        }
    }

    /// 這個音色庫裡實際存在的副檔名，給篩選列用。
    func availableFileTypes() throws -> [String] {
        try database.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT file_extension FROM sounds
                 WHERE file_extension != ''
                 ORDER BY file_extension
                """)
        }
    }

    /// 真正的 SQL COUNT。大型音色庫不能靠抓回全部再數。
    func count(filter: SoundFilter,
               search: String = "",
               filters: SoundFilters = SoundFilters()) throws -> Int {
        try database.writer.read { db in
            try request(filter: filter, search: search, filters: filters).fetchCount(db)
        }
    }

    func sound(id: Int64) throws -> Sound? {
        try database.writer.read { db in try Sound.fetchOne(db, key: id) }
    }

    func latestAnalysis(soundId: Int64) throws -> OrganizerAnalysis? {
        try database.writer.read { db in
            try OrganizerAnalysis
                .filter(OrganizerAnalysis.Columns.soundId == soundId)
                .order(OrganizerAnalysis.Columns.startedAt.desc)
                .fetchOne(db)
        }
    }

    func suggestions(analysisId: Int64) throws -> [OrganizerSuggestion] {
        try database.writer.read { db in
            try OrganizerSuggestion
                .filter(OrganizerSuggestion.Columns.analysisId == analysisId)
                .filter(OrganizerSuggestion.Columns.status != OrganizerSuggestion.Status.superseded.rawValue)
                .fetchAll(db)
        }
    }

    /// 還沒分析過的音效。批次分析從這裡取工作。
    ///
    /// 只取 status 正常的檔案：離線磁碟上的檔案讀不到內容，
    /// 送進引擎只會一路寫 failed，把真正的失敗淹沒在雜訊裡。
    /// `includeAnalysed` 只在規則或分類法改過、需要整批重跑時才設 true。
    /// 平常不重跑是因為重跑會覆蓋掉使用者已經審核過的建議。
    func soundsPendingAnalysis(libraryId: Int64? = nil,
                               includeAnalysed: Bool = false,
                               limit: Int? = nil) throws -> [Sound] {
        try database.writer.read { db in
            var request = Sound
                .filter(Sound.Columns.status == FileStatus.ok.rawValue)
                .order(Sound.Columns.relativePath)
            if includeAnalysed == false {
                request = request.filter([AnalysisStatus.none.rawValue, AnalysisStatus.queued.rawValue]
                    .contains(Sound.Columns.analysisStatus))
            }
            if let libraryId {
                request = request.filter(Sound.Columns.libraryId == libraryId)
            }
            if let limit {
                request = request.limit(limit)
            }
            return try request.fetchAll(db)
        }
    }

    /// 每個資料夾的直接檔案數。一次 GROUP BY 就夠，不用把路徑全部拉出來算。
    func folderCounts(libraryId: Int64) throws -> [(path: String, count: Int)] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT folder_path AS path, COUNT(*) AS n
                  FROM sounds
                 WHERE library_id = ?
                 GROUP BY folder_path
                 ORDER BY folder_path
                """, arguments: [libraryId])
                .map { (path: $0["path"] ?? "", count: $0["n"] ?? 0) }
        }
    }

    /// 一個音效目前的標籤，含來源。
    func tags(soundId: Int64) throws -> [SoundTagView] {
        try database.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.id AS id, t.name AS name, t.canonical_name AS canonical_name,
                       st.source AS source
                  FROM sound_tags st
                  JOIN tags t ON t.id = st.tag_id
                 WHERE st.sound_id = ?
                 ORDER BY t.canonical_name
                """, arguments: [soundId])

            return rows.compactMap { row in
                guard let id: Int64 = row["id"],
                      let source = MetadataSource(rawValue: row["source"] ?? "") else { return nil }
                return SoundTagView(id: id,
                                    name: row["name"] ?? "",
                                    canonicalName: row["canonical_name"] ?? "",
                                    source: source)
            }
        }
    }

    /// 全部分類路徑，照 taxonomy 的順序。
    func categoryPaths() throws -> [String] {
        try database.writer.read { db in
            try Category
                .order(Column("sort_order").asc, Column("path").asc)
                .fetchAll(db)
                .map(\.path)
        }
    }

    func category(id: Int64) throws -> Category? {
        try database.writer.read { db in try Category.fetchOne(db, key: id) }
    }
}

/// 命名預覽用的扁平列。只有組名字需要的欄位。
struct NamingRow {
    var id: Int64
    var relativePath: String
    var filename: String
    var fileExtension: String
    var category: String?
    var style: String?
    var bpm: Double?
    var musicalKey: String?
    var isLoop: Bool?
    /// 原始檔案的絕對路徑。M32 建硬連結的來源。
    var filePath: String = ""
    var libraryId: Int64 = 0
    /// 這個音色庫的根目錄。整理樹建在它底下的 `_Organized/`——
    /// 硬連結**必須跟原檔在同一顆碟上**，放在庫根目錄自然滿足這條。
    var libraryRoot: String = ""
    /// 上一次整理時凍結的編號，以及當時的資料夾。
    /// 資料夾不一樣就代表分類改過了，舊號碼不適用。
    var organizedNumber: Int?
    var organizedFolder: String?

    init(id: Int64, relativePath: String, filename: String, fileExtension: String,
         category: String?, style: String?, bpm: Double?, musicalKey: String?, isLoop: Bool?,
         filePath: String = "", libraryId: Int64 = 0, libraryRoot: String = "",
         organizedNumber: Int? = nil, organizedFolder: String? = nil) {
        self.id = id
        self.relativePath = relativePath
        self.filename = filename
        self.fileExtension = fileExtension
        self.category = category
        self.style = style
        self.bpm = bpm
        self.musicalKey = musicalKey
        self.isLoop = isLoop
        self.filePath = filePath
        self.libraryId = libraryId
        self.libraryRoot = libraryRoot
        self.organizedNumber = organizedNumber
        self.organizedFolder = organizedFolder
    }

    init(row: Row) {
        id = row["id"]
        relativePath = row["relative_path"] ?? ""
        filename = row["filename"] ?? ""
        fileExtension = row["file_extension"] ?? ""
        category = row["category_path"]
        style = row["style"]
        bpm = row["bpm"]
        musicalKey = row["musical_key"]
        isLoop = row["is_loop"]
        filePath = row["file_path"] ?? ""
        libraryId = row["library_id"] ?? 0
        libraryRoot = row["library_root"] ?? ""
        organizedNumber = row["organized_number"]
        organizedFolder = row["organized_folder"]
    }
}

/// 一個分類路徑底下的音效數（不含子分類；加總由 `CategoryTree` 做）。
struct CategoryCount: Equatable, Hashable {
    let path: String
    var confirmed: Int = 0
    var suggested: Int = 0

    var total: Int { confirmed + suggested }
}
