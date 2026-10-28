import Foundation

enum OrganizerValidationError: Error, Equatable, LocalizedError {
    case notAnObject
    case unexpectedFields([String])
    case missingFields([String])
    case invalidStatus(String)
    case confidenceOutOfRange(Double)
    case emptyDisplayName
    case displayNameTooLong(Int)
    case descriptionTooLong(Int)
    case emptyTag
    case duplicateTags([String])
    case tooManyTags(Int)
    case unknownCategory(String)
    case tooManyAlternatives(Int)
    case duplicateAlternatives
    case unknownAlternativeCategory(String)
    case failedMustHaveZeroConfidence(Double)
    case failedMustNotInterpretAudio
    case unknownMustBeUnclassified(String)
    case unknownMustNeedReview
    case uncertainMustNeedReview
    case unknownStyle(String)

    var errorDescription: String? {
        switch self {
        case .notAnObject:                    return "輸出不是 JSON 物件"
        case .unexpectedFields(let f):        return "含有 schema 未定義的欄位：\(f.joined(separator: ", "))"
        case .missingFields(let f):           return "缺少必填欄位：\(f.joined(separator: ", "))"
        case .invalidStatus(let s):           return "不合法的 status：\(s)"
        case .confidenceOutOfRange(let c):    return "confidence 超出 0.0–1.0：\(c)"
        case .emptyDisplayName:               return "display_name 存在但為空字串"
        case .displayNameTooLong(let n):      return "display_name 過長：\(n) 字元（上限 120）"
        case .descriptionTooLong(let n):      return "description 過長：\(n) 字元（上限 300）"
        case .emptyTag:                       return "含有空白標籤"
        case .duplicateTags(let t):           return "標籤重複：\(t.joined(separator: ", "))"
        case .tooManyTags(let n):             return "標籤數量過多：\(n)（上限 12）"
        case .unknownCategory(let c):         return "分類不在 taxonomy 白名單內：\(c)"
        case .tooManyAlternatives(let n):     return "alternative_categories 過多：\(n)（上限 3）"
        case .duplicateAlternatives:          return "alternative_categories 有重複"
        case .unknownAlternativeCategory(let c): return "替代分類不在白名單內：\(c)"
        case .failedMustHaveZeroConfidence(let c): return "status=failed 時 confidence 必須為 0，實際為 \(c)"
        case .failedMustNotInterpretAudio:    return "status=failed 不得附帶任何音訊詮釋（名稱／分類／標籤／描述）"
        case .unknownMustBeUnclassified(let c):return "status=unknown 時 category 必須為 Unclassified，實際為 \(c)"
        case .unknownMustNeedReview:          return "status=unknown 時 needs_review 必須為 true"
        case .unknownStyle(let st):           return "風格不在 style-vocabulary 白名單內：\(st)"
        case .uncertainMustNeedReview:        return "status=uncertain 時 needs_review 必須為 true"
        }
    }
}

/// 兩層驗證（CLAUDE.md §53）：
///  第一層 organization-result.json —— 型別、必填、範圍、唯一性、不得有多餘欄位
///  第二層 output-contract.md      —— 語意規則
struct OrganizerSchemaValidator {
    let taxonomy: Taxonomy
    let vocabulary: TagVocabulary
    /// nil 時不檢查風格。舊的呼叫點與不涉及風格的測試維持原行為。
    let styles: StyleVocabulary?

    init(taxonomy: Taxonomy, vocabulary: TagVocabulary, styles: StyleVocabulary? = nil) {
        self.taxonomy = taxonomy
        self.vocabulary = vocabulary
        self.styles = styles
    }

    /// 從原始 JSON 驗證並解碼。多餘欄位只能在這裡抓到，Codable 會默默忽略它們。
    func decodeAndValidate(_ data: Data) throws -> OrganizerResult {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw OrganizerValidationError.notAnObject
        }

        let present = Set(dict.keys)
        let required = OrganizerResult.requiredKeys

        let missing = required.subtracting(present)
        if !missing.isEmpty {
            throw OrganizerValidationError.missingFields(missing.sorted())
        }
        let unexpected = present.subtracting(OrganizerResult.allowedKeys)
        if !unexpected.isEmpty {
            throw OrganizerValidationError.unexpectedFields(unexpected.sorted())
        }

        if let rawStatus = dict["status"] as? String,
           OrganizerStatus(rawValue: rawStatus) == nil {
            throw OrganizerValidationError.invalidStatus(rawStatus)
        }

        let result = try JSONDecoder().decode(OrganizerResult.self, from: data)
        try validate(result)
        return result
    }

    func validate(_ result: OrganizerResult) throws {
        // --- 第一層 ---
        guard result.confidence >= 0.0, result.confidence <= 1.0 else {
            throw OrganizerValidationError.confidenceOutOfRange(result.confidence)
        }
        if let name = result.displayName {
            if name.isEmpty { throw OrganizerValidationError.emptyDisplayName }
            if name.count > 120 { throw OrganizerValidationError.displayNameTooLong(name.count) }
        }
        if let summary = result.summary, summary.count > 300 {
            throw OrganizerValidationError.descriptionTooLong(summary.count)
        }
        if result.tags.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw OrganizerValidationError.emptyTag
        }
        if result.tags.count > vocabulary.maxTags {
            throw OrganizerValidationError.tooManyTags(result.tags.count)
        }
        let canonicalTags = result.tags.map(Tag.canonicalize)
        let duplicates = Dictionary(grouping: canonicalTags, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        if !duplicates.isEmpty {
            throw OrganizerValidationError.duplicateTags(duplicates)
        }
        // 風格必須來自白名單。這是擋住「編一個沒聽過的曲風」的那道門，
        // 也是 M30 讓 Antigravity 正規化 pack 名時唯一的保險（D-016）。
        if let styles, let style = result.style, styles.isValid(style) == false {
            throw OrganizerValidationError.unknownStyle(style)
        }
        if result.alternativeCategories.count > 3 {
            throw OrganizerValidationError.tooManyAlternatives(result.alternativeCategories.count)
        }
        if Set(result.alternativeCategories).count != result.alternativeCategories.count {
            throw OrganizerValidationError.duplicateAlternatives
        }

        // --- 分類白名單 ---
        guard taxonomy.isValidPath(result.category) else {
            throw OrganizerValidationError.unknownCategory(result.category)
        }
        for alt in result.alternativeCategories where !taxonomy.isValidPath(alt) {
            throw OrganizerValidationError.unknownAlternativeCategory(alt)
        }

        // --- 第二層：語意規則 ---
        switch result.status {
        case .failed:
            guard result.confidence == 0 else {
                throw OrganizerValidationError.failedMustHaveZeroConfidence(result.confidence)
            }
            let interprets = result.displayName != nil
                || result.summary != nil
                || !result.tags.isEmpty
                || result.category != Taxonomy.unclassified
                || result.subcategory != nil
            if interprets { throw OrganizerValidationError.failedMustNotInterpretAudio }

        case .unknown:
            guard result.category == Taxonomy.unclassified else {
                throw OrganizerValidationError.unknownMustBeUnclassified(result.category)
            }
            guard result.needsReview else { throw OrganizerValidationError.unknownMustNeedReview }

        case .uncertain:
            guard result.needsReview else { throw OrganizerValidationError.uncertainMustNeedReview }

        case .recognized, .suggested:
            break
        }
    }

    /// 非 canonical 的標籤不視為錯誤，但要標記出來供詞彙審查（tagging-rules.md §12）。
    func nonCanonicalTags(in result: OrganizerResult) -> [String] {
        result.tags.filter { !vocabulary.isCanonical($0) }
    }
}
