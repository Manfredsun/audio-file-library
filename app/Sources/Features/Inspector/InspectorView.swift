import SwiftUI

/// 沒有卡片、沒有邊框、沒有填色塊。結構全由間與內縮髮絲線構成。
struct InspectorView: View {
    @ObservedObject var store: LibraryStore
    @State private var displayNameDraft: String = ""
    @State private var notesDraft: String = ""
    @State private var tagDraft: String = ""

    var body: some View {
        Group {
            if let sound = store.selectedSound {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Ma.chapter) {
                        heading(sound)
                        metadata(sound)
                        organizer()
                        file(sound)
                    }
                    .padding(.horizontal, DS.Ma.group)
                    .padding(.top, DS.Ma.group)
                    .padding(.bottom, DS.Ma.chapter)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    displayNameDraft = sound.displayName ?? ""
                    notesDraft = sound.notes ?? ""
                }
                .onChange(of: store.selectedSoundId) {
                    displayNameDraft = store.selectedSound?.displayName ?? ""
                    notesDraft = store.selectedSound?.notes ?? ""
                    tagDraft = ""
                }
            } else {
                EmptyStateView(title: L10n.tr("未選取"),
                               message: L10n.tr("從清單選一個音效，這裡會顯示它的 metadata 與分析結果。"))
            }
        }
        .background(DS.Palette.sumi)
    }

    // MARK: - 標題

    private func heading(_ sound: Sound) -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.inline) {
            MinchoTitle(text: sound.browserTitle)
            Text(sound.relativePath)
                .font(DS.TypeScale.mono)
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(2)
            DurationMark(duration: sound.duration, emphasized: true, lane: 140)
                .padding(.top, DS.Ma.tight)
        }
    }

    // MARK: - Metadata

    private func metadata(_ sound: Sound) -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.group) {
            SectionLabel(text: L10n.tr("metadata"))

            VStack(alignment: .leading, spacing: DS.Ma.tight) {
                SectionLabel(text: L10n.tr("display name"))
                TextField("", text: $displayNameDraft)
                    .textFieldStyle(.plain)
                    .font(DS.TypeScale.value)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.bottom, DS.Ma.tight)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(DS.Palette.nezumi)
                            .frame(height: 1)
                    }
                    .onSubmit { store.setDisplayName(displayNameDraft) }

                HStack {
                    ProvenanceDot(source: sound.displayNameSource)
                    Spacer()
                    Text(L10n.tr("不改動磁碟檔名"))
                        .font(DS.TypeScale.label)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .padding(.top, DS.Ma.tight)
            }

            categoryPicker(sound)
            stylePicker(sound)
            texturePicker(sound)
            musicalFacts(sound)
            subcategoryField(sound)
            tagsSection()
            notesSection()

            HStack(spacing: DS.Ma.group) {
                Button {
                    store.toggleFavorite()
                } label: {
                    HStack(spacing: DS.Ma.tight) {
                        Circle()
                            .fill(sound.favorite ? DS.Palette.asagi : Color.clear)
                            .overlay(Circle().stroke(DS.Palette.textTertiary, lineWidth: sound.favorite ? 0 : 0.8))
                            .frame(width: 5, height: 5)
                        Text(L10n.tr("收藏"))
                            .foregroundStyle(sound.favorite ? DS.Palette.asagi : DS.Palette.textSecondary)
                    }
                }
                .buttonStyle(.actionLeading)

                Spacer()

                // 評分的記號維持 8×2 的短墨線，但每一格的點擊範圍是 20×28（D-041）。
                // 原本只能點中那條 2pt 高的線。
                HStack(spacing: 0) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            store.setRating(sound.rating == value ? 0 : value)
                        } label: {
                            Rectangle()
                                .fill(value <= sound.rating ? DS.Palette.asagi : DS.Palette.nezumi)
                                .frame(width: 8, height: 2)
                                .frame(width: 20, height: DS.Metrics.hitTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L10n.tr("評分 %@", String(describing: value)))
                    }
                }
                .padding(.trailing, -6)
            }
        }
    }

    // MARK: - 分類

    private func categoryPicker(_ sound: Sound) -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.tight) {
            SectionLabel(text: L10n.tr("category"))

            pickerField(store.selectedCategoryPath.map { BuiltinNames.category($0) } ?? L10n.tr("未分類"),
                        isEmpty: store.selectedCategoryPath == nil) {
                var entries: [MenuEntry] = [.item(L10n.tr("未分類")) { store.setCategory(nil) }, .divider]
                for top in topLevelCategories {
                    var children: [MenuEntry] = [.item(BuiltinNames.category(top)) { store.setCategory(top) }]
                    let paths = childCategories(of: top)
                    if paths.isEmpty == false {
                        children.append(.divider)
                        children += paths.map { path -> MenuEntry in
                            .item(leafName(path)) { store.setCategory(path) }
                        }
                    }
                    entries.append(.submenu(BuiltinNames.category(top), children))
                }
                return entries
            }

            ProvenanceDot(source: sound.categorySource)
        }
    }

    // MARK: - 節拍與調性

    /// 量測與字面讀到的事實。**唯讀**——這些不是意見，是數字。
    /// 人工要改的話，之後給 BPM 一個可編輯欄位，現在先讓它看得見。
    @ViewBuilder
    private func musicalFacts(_ sound: Sound) -> some View {
        if sound.bpm != nil || sound.musicalKey != nil || sound.isLoop != nil {
            VStack(alignment: .leading, spacing: DS.Ma.tight) {
                SectionLabel(text: L10n.tr("tempo"))
                HStack(spacing: DS.Ma.block) {
                    if let bpm = sound.bpm {
                        HStack(spacing: 3) {
                            Text(String(format: "%.0f", bpm))
                                .font(DS.TypeScale.monoLarge)
                                .foregroundStyle(DS.Palette.textPrimary)
                            Text("bpm")
                                .font(DS.TypeScale.label)
                                .foregroundStyle(DS.Palette.textTertiary)
                        }
                    }
                    if let key = sound.musicalKey {
                        Text(key)
                            .font(DS.TypeScale.mono)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    if let isLoop = sound.isLoop {
                        Text(isLoop ? L10n.tr("loop") : L10n.tr("one-shot"))
                            .font(DS.TypeScale.label)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    Spacer()
                }
                ProvenanceDot(source: sound.bpmSource)
            }
        }
    }

    // MARK: - 風格

    /// 風格是跟分類正交的獨立欄位（D-014），所以在 Inspector 裡也是獨立一區，
    /// 不是塞在分類選單底下。
    private func stylePicker(_ sound: Sound) -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.tight) {
            SectionLabel(text: L10n.tr("style"))

            pickerField(sound.style.map { BuiltinNames.style($0) } ?? L10n.tr("未指定"), isEmpty: sound.style == nil) {
                [.item(L10n.tr("未指定")) { store.setStyle(nil, for: sound.rowId) }, .divider]
                    + store.styleOptions.map { option -> MenuEntry in
                        .item(BuiltinNames.style(option), checked: sound.style == option) { store.setStyle(option, for: sound.rowId) }
                    }
            }

            ProvenanceDot(source: sound.styleSource)
        }
    }

    // MARK: - 材質

    /// 材質跟風格一樣是獨立欄位。
    /// 風格是「這是為哪種音樂做的」，材質是「發出聲音的東西是什麼做的」。
    private func texturePicker(_ sound: Sound) -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.tight) {
            SectionLabel(text: L10n.tr("texture"))

            pickerField(sound.texture.map { BuiltinNames.texture($0) } ?? L10n.tr("未指定"), isEmpty: sound.texture == nil) {
                [.item(L10n.tr("未指定")) { store.setTexture(nil, for: sound.rowId) }, .divider]
                    + store.availableTextures.map { option -> MenuEntry in
                        .item(BuiltinNames.texture(option), checked: sound.texture == option) { store.setTexture(option, for: sound.rowId) }
                    }
            }

            ProvenanceDot(source: sound.textureSource)
        }
    }

    /// 分類／風格／材質共用的選單欄位：整條底線都可以點，高度至少 28pt（D-041）。
    /// 不用 SwiftUI 的 `Menu`，原因見 `PopUpMenu`。
    private func pickerField(_ text: String, isEmpty: Bool,
                             entries: @escaping () -> [MenuEntry]) -> some View {
        Button {
            PopUpMenu.show(entries())
        } label: {
            HStack {
                Text(text)
                    .font(DS.TypeScale.value)
                    .foregroundStyle(isEmpty ? DS.Palette.textTertiary : DS.Palette.textPrimary)
                Spacer()
                Text("▾")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .frame(minHeight: DS.Metrics.hitTarget)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.Palette.nezumi).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var topLevelCategories: [String] {
        store.categoryPaths.filter { !$0.contains("/") }
    }

    private func childCategories(of top: String) -> [String] {
        store.categoryPaths.filter { $0.hasPrefix(top + "/") }
    }

    private func leafName(_ path: String) -> String {
        BuiltinNames.category(path, leafOnly: true)
    }

    private func subcategoryField(_ sound: Sound) -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.tight) {
            SectionLabel(text: L10n.tr("subcategory"))
            TextField("", text: Binding(
                get: { sound.subcategory ?? "" },
                set: { store.setSubcategory($0) }
            ))
            .textFieldStyle(.plain)
            .font(DS.TypeScale.value)
            .foregroundStyle(DS.Palette.textPrimary)
            .padding(.bottom, DS.Ma.tight)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.Palette.nezumi).frame(height: 1)
            }
            ProvenanceDot(source: sound.subcategorySource)
        }
    }

    // MARK: - 標籤

    private func tagsSection() -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.inline) {
            SectionLabel(text: L10n.tr("tags"))

            if store.selectedTags.isEmpty {
                Text(L10n.tr("尚無標籤"))
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.textTertiary)
            } else {
                TagFlow(tags: store.selectedTags) { store.removeTag($0) }
            }

            TextField(L10n.tr("加標籤"), text: $tagDraft)
                .textFieldStyle(.plain)
                .font(DS.TypeScale.rowMeta)
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.bottom, DS.Ma.tight)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(DS.Palette.nezumi).frame(height: 1)
                }
                .onSubmit {
                    store.addTag(tagDraft)
                    tagDraft = ""
                }

            if !tagSuggestions.isEmpty {
                HStack(spacing: 0) {
                    ForEach(tagSuggestions, id: \.self) { suggestion in
                        Button {
                            store.addTag(suggestion)
                            tagDraft = ""
                        } label: {
                            Text(suggestion)
                                .foregroundStyle(DS.Palette.asagi)
                        }
                        .buttonStyle(.action)
                    }
                }
                .padding(.leading, -DS.Ma.inline)
            }
        }
    }

    /// 從 canonical 詞彙給建議，已經有的標籤不再出現。
    private var tagSuggestions: [String] {
        let draft = tagDraft.trimmingCharacters(in: .whitespaces).lowercased()
        guard draft.count >= 1 else { return [] }
        let existing = Set(store.selectedTags.map(\.canonicalName))
        return store.tagVocabulary
            .filter { $0.hasPrefix(draft) && !existing.contains($0) }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - 備註

    private func notesSection() -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.tight) {
            SectionLabel(text: L10n.tr("notes"))
            TextEditor(text: $notesDraft)
                .scrollContentBackground(.hidden)
                .font(DS.TypeScale.rowMeta)
                .foregroundStyle(DS.Palette.textPrimary)
                .frame(height: 54)
                .padding(DS.Ma.tight)
                .background(
                    RoundedRectangle(cornerRadius: 2).fill(DS.Palette.kozumi)
                )
                .onChange(of: notesDraft) {
                    store.setNotes(notesDraft)
                }
        }
    }

    // MARK: - Organizer

    private func organizer() -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.group) {
            SectionLabel(text: L10n.tr("organizer"))

            if let analysis = store.analysis {
                HStack(alignment: .firstTextBaseline, spacing: DS.Ma.inline) {
                    Circle()
                        .fill(statusColor(analysis.status))
                        .frame(width: 5, height: 5)
                    Text(L10n.tr("status." + analysis.status.rawValue))
                        .font(DS.TypeScale.value)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Spacer()
                    Text("\(Int(analysis.confidence * 100))")
                        .font(DS.TypeScale.monoLarge)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Text("%")
                        .font(DS.TypeScale.label)
                        .foregroundStyle(DS.Palette.textTertiary)
                }

                ConfidenceLine(value: analysis.confidence, status: analysis.status)

                // 看音效目前的旗標，不是分析當下的：人接受或設定過分類之後就不該再顯示（D-043）。
                if analysis.needsReview, store.selectedSound?.needsReview == true {
                    HStack(spacing: DS.Ma.tight) {
                        Rectangle()
                            .fill(DS.Palette.kihada)
                            .frame(width: DS.Metrics.shioriWidth, height: 10)
                        Text(L10n.tr("待複查"))
                            .font(DS.TypeScale.label)
                            .tracking(1.4)
                            .foregroundStyle(DS.Palette.kihada)
                    }
                }

                if let summary = analysis.summary {
                    Text(summary)
                        .font(DS.TypeScale.rowMeta)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if store.suggestions.isEmpty {
                    Text(L10n.tr("這次分析沒有可套用的建議"))
                        .font(DS.TypeScale.label)
                        .foregroundStyle(DS.Palette.textTertiary)
                } else {
                    MaRule()
                    VStack(spacing: DS.Ma.block) {
                        ForEach(store.suggestions, id: \.id) { suggestion in
                            SuggestionRow(suggestion: suggestion,
                                          onAccept: { store.accept(suggestion) },
                                          onReject: { store.reject(suggestion) })
                        }
                    }
                }
            } else {
                Text(L10n.tr("尚未分析"))
                    .font(DS.TypeScale.rowMeta)
                    .foregroundStyle(DS.Palette.textTertiary)

                Button {
                    store.analyzeSelected()
                } label: {
                    Text(L10n.tr("分析這個音效"))
                        .foregroundStyle(DS.Palette.asagi)
                        .padding(.bottom, DS.Ma.tight)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(DS.Palette.asagi.opacity(0.5)).frame(height: 1)
                        }
                }
                .buttonStyle(.actionLeading)
            }
        }
    }

    private func statusColor(_ status: OrganizerStatus) -> Color {
        switch status {
        case .recognized: return DS.Palette.asagi
        case .suggested:  return DS.Palette.asagi.opacity(0.6)
        case .uncertain:  return DS.Palette.kihada
        case .unknown:    return DS.Palette.textTertiary
        case .failed:     return DS.Palette.hi
        }
    }

    // MARK: - File

    private func file(_ sound: Sound) -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.group) {
            SectionLabel(text: L10n.tr("file"))
            entry(L10n.tr("filename"), sound.filename, source: nil, monospaced: true)

            HStack(alignment: .top, spacing: DS.Ma.section) {
                compact(L10n.tr("rate"), sound.sampleRate.map { "\($0 / 1000)k" } ?? "—")
                compact(L10n.tr("bits"), sound.bitDepth.map(String.init) ?? "—")
                compact(L10n.tr("ch"), sound.channelCount.map(String.init) ?? "—")
                compact(L10n.tr("status"), L10n.tr("status." + sound.status.rawValue))
            }
        }
    }

    // MARK: - 小元件

    private func entry(_ label: String, _ value: String, source: MetadataSource?, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.tight) {
            SectionLabel(text: label)
            Text(value)
                .font(monospaced ? DS.TypeScale.mono : DS.TypeScale.value)
                .foregroundStyle(DS.Palette.textPrimary)
                .textSelection(.enabled)
                .lineLimit(2)
            ProvenanceDot(source: source)
        }
    }

    private func compact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.tight) {
            SectionLabel(text: label)
            Text(value)
                .font(DS.TypeScale.mono)
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }
}

private struct ConfidenceLine: View {
    let value: Double
    let status: OrganizerStatus

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(DS.Palette.hairlineFaint)
                    .frame(height: 1)
                Rectangle()
                    .fill(status == .uncertain || status == .unknown
                          ? DS.Palette.kihada
                          : DS.Palette.asagi)
                    .frame(width: max(2, geo.size.width * value), height: 2)
            }
        }
        .frame(height: 2)
    }
}

private struct SuggestionRow: View {
    let suggestion: OrganizerSuggestion
    let onAccept: () -> Void
    let onReject: () -> Void

    private var suggestionDisplay: String {
        switch suggestion.field {
        case .category, .alternativeCategory: return BuiltinNames.category(suggestion.value)
        case .style: return BuiltinNames.style(suggestion.value)
        default: return suggestion.value
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Ma.block) {
            VStack(alignment: .leading, spacing: DS.Ma.hair) {
                SectionLabel(text: L10n.tr(suggestion.field.rawValue))
                Text(suggestionDisplay)
                    .font(DS.TypeScale.rowMeta)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DS.Ma.inline)

            if suggestion.status == .suggested {
                HStack(spacing: DS.Ma.block) {
                    Button(action: onAccept) {
                        Text(L10n.tr("接受"))
                            .foregroundStyle(DS.Palette.asagi)
                    }
                    .buttonStyle(.actionLeading)

                    Button(action: onReject) {
                        Text(L10n.tr("拒絕"))
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    .buttonStyle(.action)
                }
                .padding(.top, DS.Ma.tight)
            } else {
                Text(L10n.tr("status." + suggestion.status.rawValue))
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .padding(.top, DS.Ma.block)
            }
        }
    }
}


/// 標籤 chip。人工標籤是浅葱底，AI 接受的是灰底——來源一眼可見。
private struct TagFlow: View {
    let tags: [SoundTagView]
    let onRemove: (SoundTagView) -> Void

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: DS.Ma.tight)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Ma.tight) {
            ForEach(tags) { tag in
                HStack(spacing: DS.Ma.tight) {
                    Text(tag.name)
                        .font(DS.TypeScale.label)
                        .foregroundStyle(tag.source.isManual ? DS.Palette.asagi : DS.Palette.textSecondary)
                    // ×的點擊範圍 20×24：chip 本身不長到 28pt，否則標籤區會變得很鬆（D-041）。
                    Button {
                        onRemove(tag)
                    } label: {
                        Text("×")
                            .font(DS.TypeScale.action)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .frame(width: 20, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("移除標籤"))
                }
                .padding(.leading, DS.Ma.inline)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tag.source.isManual
                              ? DS.Palette.asagi.opacity(0.14)
                              : DS.Palette.nezumi.opacity(0.5))
                )
            }
        }
    }
}
