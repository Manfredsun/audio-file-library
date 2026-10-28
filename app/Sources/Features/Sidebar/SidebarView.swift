import SwiftUI

/// 文字為主的側欄。沒有圖示——選取用左緣的栞（2px 標記）表示。
struct SidebarView: View {
    @ObservedObject var store: LibraryStore

    private let smartFilters: [SoundFilter] = [.all, .favorites]
    private let reviewFilters: [SoundFilter] = [.needsReview, .unclassified, .analysisFailed]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Ma.section) {
                group(L10n.tr("Library"), smartFilters)
                categorySection
                librarySection
                styleSection
                textureSection
                group(L10n.tr("Review"), reviewFilters)
            }
            .padding(.top, DS.Ma.section)
            .padding(.bottom, DS.Ma.chapter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(DS.Palette.sumi)
    }

    @ViewBuilder
    private func group(_ title: String, _ filters: [SoundFilter]) -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.tight) {
            header(title)
            ForEach(filters, id: \.self) { filter in
                SidebarRow(title: filter.title,
                           count: store.counts[filter] ?? 0,
                           accent: accent(for: filter),
                           isSelected: store.filter == filter,
                           isOffline: false)
                    .contentShape(Rectangle())
                    .onTapGesture { store.filter = filter }
            }
        }
    }

    /// 分類區塊（M41）。
    ///
    /// 從網路下載的 sample pack 各自有自己的 Kicks／BD／Kick Drum 資料夾，
    /// 這裡把它們收成同一個「Drums › Kick」。數字含還沒確認的分析建議——
    /// 只列已確定的話，這一區幾乎是空的（2026-09-23 實測 41,297 筆裡只有 26 筆已確定）。
    /// 建議有多少，看數字旁的黃點；點進去後每一列也會標出哪些還沒確認。
    @ViewBuilder
    private var categorySection: some View {
        if store.categoryTree.isEmpty == false {
            VStack(alignment: .leading, spacing: DS.Ma.tight) {
                header(L10n.tr("Category"))
                ForEach(store.categoryTree) { node in
                    categoryRow(node, depth: 0)
                    if store.expandedCategories.contains(node.path) {
                        ForEach(node.children) { child in
                            categoryRow(child, depth: 1)
                        }
                    }
                }
            }
        }
    }

    private func categoryRow(_ node: CategoryNode, depth: Int) -> some View {
        let disclosure: SidebarDisclosure = node.children.isEmpty
            ? .none
            : (store.expandedCategories.contains(node.path) ? .open : .closed)
        return SidebarRow(title: BuiltinNames.category(node.path, leafOnly: true),
                          count: node.total,
                          accent: DS.Palette.asagi,
                          isSelected: store.filter == .category(node.path),
                          isOffline: false,
                          depth: depth,
                          disclosure: disclosure,
                          onToggle: { store.toggleCategory(node.path) },
                          suggested: node.suggested)
            .contentShape(Rectangle())
            .onTapGesture {
                store.filter = .category(node.path)
                // 點頂層時順便展開，跟資料夾樹的行為一致。
                if disclosure == .closed { store.toggleCategory(node.path) }
            }
    }

    /// 風格區塊。
    ///
    /// 風格是跟分類正交的面向（D-014），所以它在側欄裡是獨立的一段，
    /// 不是掛在某個分類底下。沒有任何音效有風格時整段不顯示——
    /// 空標題只會讓人以為壞了。
    @ViewBuilder
    private var styleSection: some View {
        if store.styleCounts.isEmpty == false {
            VStack(alignment: .leading, spacing: DS.Ma.tight) {
                HStack {
                    header(L10n.tr("Style"))
                    Spacer()
                    if store.styleCounts.count > Self.collapsedStyleCount {
                        Button {
                            store.showAllStyles.toggle()
                        } label: {
                            Text(store.showAllStyles ? L10n.tr("收合") : L10n.tr("全部 %@", String(describing: store.styleCounts.count)))
                                .foregroundStyle(DS.Palette.textSecondary)
                        }
                        .buttonStyle(ActionButtonStyle(flush: .trailing))
                        .padding(.trailing, DS.Ma.group)
                    }
                }

                ForEach(visibleStyles, id: \.style) { entry in
                    SidebarRow(title: BuiltinNames.style(entry.style),
                               count: entry.count,
                               accent: DS.Palette.kihada,
                               isSelected: store.filter == .style(entry.style),
                               isOffline: false)
                        .contentShape(Rectangle())
                        .onTapGesture { store.filter = .style(entry.style) }
                }
            }
        }
    }

    /// 材質區塊。
    ///
    /// 跟風格一樣是正交的面向，所以是獨立的一段。材質是「東西是什麼做的」
    /// （金屬、木頭、玻璃），風格是「這是為哪種音樂做的」——兩件事。
    @ViewBuilder
    private var textureSection: some View {
        if store.textureCounts.isEmpty == false {
            VStack(alignment: .leading, spacing: DS.Ma.tight) {
                HStack {
                    header(L10n.tr("Texture"))
                    Spacer()
                    if store.textureCounts.count > Self.collapsedStyleCount {
                        Button {
                            store.showAllTextures.toggle()
                        } label: {
                            Text(store.showAllTextures ? L10n.tr("收合") : L10n.tr("全部 %@", String(describing: store.textureCounts.count)))
                                .foregroundStyle(DS.Palette.textSecondary)
                        }
                        .buttonStyle(ActionButtonStyle(flush: .trailing))
                        .padding(.trailing, DS.Ma.group)
                    }
                }

                ForEach(visibleTextures, id: \.texture) { entry in
                    SidebarRow(title: BuiltinNames.texture(entry.texture),
                               count: entry.count,
                               accent: DS.Palette.asagi,
                               isSelected: store.filter == .texture(entry.texture),
                               isOffline: false)
                        .contentShape(Rectangle())
                        .onTapGesture { store.filter = .texture(entry.texture) }
                }
            }
        }
    }

    private var visibleTextures: [(texture: String, count: Int)] {
        store.showAllTextures ? store.textureCounts
                              : Array(store.textureCounts.prefix(Self.collapsedStyleCount))
    }

    /// 風格可能有二三十個，全部展開會把音色庫擠出視線外。
    private static let collapsedStyleCount = 8

    private var visibleStyles: [(style: String, count: Int)] {
        store.showAllStyles ? store.styleCounts
                            : Array(store.styleCounts.prefix(Self.collapsedStyleCount))
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: DS.Ma.tight) {
            HStack {
                header(L10n.tr("Libraries"))
                Spacer()
                Button {
                    store.addLibrary()
                } label: {
                    Text("＋")
                        .font(DS.TypeScale.glyph)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(width: DS.Metrics.hitTarget, height: DS.Metrics.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.tr("加入音色庫資料夾"))
                .padding(.trailing, DS.Ma.group - DS.Ma.inline)
            }

            if store.libraries.isEmpty {
                Text(L10n.tr("尚未加入"))
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .padding(.leading, DS.Ma.group)
                    .padding(.top, DS.Ma.tight)
            } else {
                ForEach(store.sidebarItems) { item in
                    SidebarRow(title: item.title,
                               count: item.count,
                               accent: DS.Palette.asagi,
                               isSelected: store.filter == item.filter,
                               isOffline: item.isOffline,
                               depth: item.depth,
                               disclosure: item.disclosure,
                               onToggle: {
                                   if let key = item.toggleKey { store.toggle(key) }
                               })
                        .contentShape(Rectangle())
                        .onTapGesture { store.select(item) }
                        .contextMenu {
                            if item.depth == 0,
                               let id = item.libraryId,
                               let library = store.library(withId: id) {
                                Button(L10n.tr("重新掃描")) { store.scanLibrary(library) }
                                Divider()
                                Button(L10n.tr("移除音色庫紀錄")) { store.removeLibrary(library) }
                                Text(L10n.tr("只移除 App 內的紀錄，不會刪除任何檔案"))
                            }
                        }
                }
            }
        }
    }

    private func header(_ title: String) -> some View {
        SectionLabel(text: title)
            .padding(.leading, DS.Ma.group)
            .padding(.bottom, DS.Ma.inline)
    }

    private func accent(for filter: SoundFilter) -> Color {
        switch filter {
        case .needsReview:    return DS.Palette.kihada
        case .analysisFailed: return DS.Palette.hi
        default:              return DS.Palette.asagi
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let count: Int
    let accent: Color
    let isSelected: Bool
    let isOffline: Bool
    var depth: Int = 0
    var disclosure: SidebarDisclosure = .none
    var onToggle: () -> Void = {}
    /// 數量裡有幾筆是還沒確認的建議（M41）。大於 0 時數字旁有一個黃點。
    var suggested: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isSelected ? accent : Color.clear)
                .frame(width: DS.Metrics.shioriWidth)

            HStack(spacing: DS.Ma.tight) {
                // 展開記號：沒有子項目時留空白，位置仍然保留，避免文字左緣跳動
                Group {
                    if disclosure == .none {
                        Color.clear
                    } else {
                        Text(disclosure == .open ? "▾" : "▸")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                }
                // 展開記號的點擊範圍 20×30（原本 16 寬、8pt 的字，D-041）。
                .frame(width: 20, height: DS.Metrics.sidebarRowHeight)
                .contentShape(Rectangle())
                .onTapGesture { onToggle() }

                Text(title)
                    .font(DS.TypeScale.rowTitle)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if isOffline {
                    Circle()
                        .stroke(DS.Palette.textTertiary, lineWidth: 0.8)
                        .frame(width: 4, height: 4)
                        .help(L10n.tr("離線——metadata 保留"))
                }

                Spacer(minLength: DS.Ma.inline)

                if suggested > 0 {
                    Circle()
                        .fill(DS.Palette.kihada)
                        .frame(width: 4, height: 4)
                        .help(L10n.tr("其中 %@ 筆是分析建議，還沒確認", String(describing: suggested)))
                }

                if count > 0 {
                    Text("\(count)")
                        .font(DS.TypeScale.mono)
                        .foregroundStyle(isSelected ? DS.Palette.textSecondary : DS.Palette.textTertiary)
                }
            }
            .padding(.leading, DS.Ma.group - DS.Metrics.shioriWidth + CGFloat(depth) * DS.Ma.block)
            .padding(.trailing, DS.Ma.group)
        }
        .frame(height: DS.Metrics.sidebarRowHeight)
        .background(isSelected ? DS.Palette.selection : Color.clear)
    }

    private var titleColor: Color {
        if isOffline { return DS.Palette.textTertiary }
        return isSelected ? DS.Palette.textPrimary : DS.Palette.textSecondary
    }
}
