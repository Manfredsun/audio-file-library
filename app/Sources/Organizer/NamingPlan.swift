import Foundation

/// 一個檔案的命名計畫。
///
/// **這一層只計算，不寫資料庫、不碰磁碟。** 產出是一份可以整份看完、
/// 匯成 CSV 拿去對的清單。要不要把它變成真的硬連結樹是 M32 的事。
struct PlannedName: Equatable {
    var soundId: Int64
    /// 原始路徑。這是這個專案唯一承諾永不改變的東西（D-019）。
    var originalPath: String
    var originalName: String
    /// 整理後的樹裡的相對資料夾，例如 `Drums/Kick`。
    var folder: String
    /// 整理後的檔名，含副檔名。
    var newName: String
    /// 這一群裡的編號。
    var number: Int
    var issues: [NamingIssue]

    var destination: String { folder.isEmpty ? newName : "\(folder)/\(newName)" }
}

/// 計畫裡值得讓人看一眼的狀況。**不是錯誤**——多數是「資訊本來就不存在」。
enum NamingIssue: String, Equatable {
    /// 抽不出 descriptor。整段留空，不填佔位字（使用者的決定）。
    case noDescriptor
    case noStyle
    /// 沒有分類就沒有目的地資料夾，只能落到未分類。
    case noCategory
    /// loop 但沒有 BPM——挑 loop 第一個要看的就是它。
    case loopWithoutTempo
    /// 兩個檔案算出同一個目的地。這個**是**錯誤，M32 不得在有碰撞時執行。
    case collision
    /// 新檔名裡出現了原路徑沒有的字。這條是 D-017 的硬約束。
    case wordNotInSource

    var isBlocking: Bool { self == .collision || self == .wordNotInSource }
}

/// 一個檔案的輸入。全部來自已經算好、或人工確認過的欄位。
struct NamingInput: Equatable {
    var soundId: Int64
    var relativePath: String
    var filename: String
    var fileExtension: String
    /// 分類路徑，例如 `Drums/Kick`。
    var category: String?
    var style: String?
    var bpm: Double?
    var musicalKey: String?
    var isLoop: Bool?
    /// `NamingConventionDetector` 抽出來的描述詞；抽不出來就是 nil。
    var descriptor: String?
    /// 已經凍結在資料庫裡的編號。M31 不寫，但接受既有的值，
    /// 這樣 M32 接上去時同一支函式不用改。
    var frozenNumber: Int?
}

struct NamingPlan: Equatable {
    var entries: [PlannedName]

    var total: Int { entries.count }
    var withDescriptor: Int { entries.filter { $0.issues.contains(.noDescriptor) == false }.count }
    var blocking: [PlannedName] { entries.filter { $0.issues.contains(where: \.isBlocking) } }
    var canExecute: Bool { blocking.isEmpty }
}

enum NamingPlanner {

    static let unclassifiedFolder = "Unclassified"

    /// 組出整份計畫。
    ///
    /// 編號依**原始路徑排序**指派，不是依處理順序——處理順序會讓每次重跑
    /// 整棵樹的名字都變，第二次執行就製造出一整批假的「變更」。
    ///
    /// `existingDestinations` 是整理樹裡已經佔用的位置（M32 會給；M31 傳空）。
    static func plan(_ inputs: [NamingInput],
                     existingDestinations: Set<String> = []) -> NamingPlan {
        // 先依原始路徑排序，編號才穩定。
        let ordered = inputs.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }

        // 先把每個資料夾已經凍結的號碼收齊，新檔案才不會跟它們撞。
        //
        // 一輪掃完再發號是必要的：凍結的號碼可能落在排序的任何位置，
        // 邊走邊發的話，排在前面的新檔案會拿到後面某個凍結號碼。
        var taken: [String: Set<Int>] = [:]
        for input in ordered {
            guard let frozen = input.frozenNumber else { continue }
            taken[input.category ?? unclassifiedFolder, default: []].insert(frozen)
        }

        var counters: [String: Int] = [:]
        var entries: [PlannedName] = []

        for input in ordered {
            let folder = input.category ?? unclassifiedFolder
            let number: Int
            if let frozen = input.frozenNumber {
                number = frozen
            } else {
                var candidate = (counters[folder] ?? 0) + 1
                while taken[folder]?.contains(candidate) == true { candidate += 1 }
                number = candidate
                counters[folder] = candidate
            }

            var issues: [NamingIssue] = []
            if input.category == nil { issues.append(.noCategory) }
            if input.style == nil { issues.append(.noStyle) }
            if input.descriptor == nil { issues.append(.noDescriptor) }
            if input.isLoop == true, input.bpm == nil { issues.append(.loopWithoutTempo) }

            let name = filename(for: input, number: number)
            if descriptorWordsNotInSource(input.descriptor, source: input.relativePath).isEmpty == false {
                issues.append(.wordNotInSource)
            }

            entries.append(PlannedName(soundId: input.soundId,
                                       originalPath: input.relativePath,
                                       originalName: input.filename,
                                       folder: folder,
                                       newName: name,
                                       number: number,
                                       issues: issues))
        }

        return NamingPlan(entries: markCollisions(entries, against: existingDestinations))
    }

    /// 組檔名。
    ///
    /// ```text
    /// one-shot：{Style} {Role} {Descriptor} {NN}.wav
    /// loop：    {Style} {Role} {BPM}bpm {Key} {NN}.wav
    /// ```
    ///
    /// **每一格沒有就整段略過，不填佔位字。** `Unknown Kick 01.wav` 比
    /// `Kick 01.wav` 更糟：它把「我們不知道」寫成了一個看起來像資訊的字。
    static func filename(for input: NamingInput, number: Int) -> String {
        var parts: [String] = []
        if let style = input.style { parts.append(style) }
        if let role = role(from: input.category) { parts.append(role) }

        if input.isLoop == true {
            if let bpm = input.bpm { parts.append("\(Int(bpm.rounded()))bpm") }
            if let key = input.musicalKey { parts.append(key.replacingOccurrences(of: " ", with: "")) }
        } else if let descriptor = input.descriptor {
            parts.append(descriptor)
        }

        parts.append(String(format: "%02d", number))
        let base = parts.joined(separator: " ")
        return input.fileExtension.isEmpty ? base : "\(base).\(input.fileExtension)"
    }

    /// 分類路徑的最後一段就是角色：`Drums/Kick` → `Kick`。
    static func role(from category: String?) -> String? {
        guard let category, category.isEmpty == false else { return nil }
        return category.split(separator: "/").last.map(String.init)
    }

    /// D-017 的硬約束：descriptor 裡的每個字都必須在原路徑裡找得到。
    ///
    /// 只檢查 descriptor，因為只有它是自由文字。風格、角色、BPM、調性
    /// 都來自受控白名單或量測，是模板的一部分。
    ///
    /// 本機這一層天生滿足這條（只做刪除不做生成），但它是**接上 AI 時
    /// 唯一的保險**——AI 編出來的字會在這裡被當場抓到。
    static func descriptorWordsNotInSource(_ descriptor: String?, source: String) -> [String] {
        guard let descriptor else { return [] }
        let haystack = PathEvidenceReader.normalise(source)
        return descriptor.split(separator: " ").map(String.init).filter { word in
            let lower = word.lowercased()
            if lower.allSatisfy({ $0.isNumber }) { return false }
            return haystack.contains(lower) == false
        }
    }

    /// 兩個檔案算出同一個目的地時，兩個都標起來。
    ///
    /// 只標其中一個的話，人看到的是「這一筆有問題」，
    /// 但真正要決定的是「這兩筆哪一個該改」。
    static func markCollisions(_ entries: [PlannedName],
                               against existing: Set<String>) -> [PlannedName] {
        var seen: [String: Int] = [:]
        for entry in entries {
            seen[entry.destination, default: 0] += 1
        }
        return entries.map { entry in
            var entry = entry
            let clashes = (seen[entry.destination] ?? 0) > 1 || existing.contains(entry.destination)
            if clashes, entry.issues.contains(.collision) == false {
                entry.issues.append(.collision)
            }
            return entry
        }
    }

    /// 匯出成 CSV。原檔名永遠在第一欄——要對照的人先看的是它。
    static func csv(_ plan: NamingPlan) -> String {
        func escape(_ field: String) -> String {
            field.contains(",") || field.contains("\"") || field.contains("\n")
                ? "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
                : field
        }
        var lines = ["原始路徑,原始檔名,新資料夾,新檔名,編號,狀況"]
        for entry in plan.entries {
            let notes = entry.issues.map(\.rawValue).joined(separator: " ")
            lines.append([entry.originalPath, entry.originalName, entry.folder,
                          entry.newName, String(entry.number), notes]
                .map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
