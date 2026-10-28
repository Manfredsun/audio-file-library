import SwiftUI

/// 複選列。選到兩個以上才出現。
///
/// 只有一個的時候什麼都不變——右鍵選單本來就處理得了單筆，
/// 多長一條列出來只是擋住列表。
struct SelectionBar: View {
    @ObservedObject var store: LibraryStore

    var body: some View {
        if store.selection.isMultiple {
            VStack(spacing: 0) {
                MaRule()
                HStack(spacing: DS.Ma.block) {
                    SectionLabel(text: L10n.tr("selected"))

                    Text("\(store.selection.count)")
                        .font(DS.TypeScale.mono)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(L10n.tr("個"))
                        .font(DS.TypeScale.label)
                        .foregroundStyle(DS.Palette.textTertiary)

                    // 跨頁選取是刻意的，但人要看得出來，否則「我只選了這頁啊」
                    // 跟實際會被動到的筆數會對不上。
                    if offPageCount > 0 {
                        Text(L10n.tr("其中 %@ 個不在這一頁", String(describing: offPageCount)))
                            .font(DS.TypeScale.label)
                            .foregroundStyle(DS.Palette.kihada)
                    }

                    Spacer(minLength: DS.Ma.block)

                    if store.collections.isEmpty == false {
                        MenuButton(entries: {
                            store.collections.map { collection -> MenuEntry in
                                let id = collection.id ?? 0
                                return .item(collection.name) {
                                    let added = store.addSelectionToCollection(id)
                                    note = added == store.selection.count
                                        ? L10n.tr("加入 %@ 個", String(describing: added))
                                        : L10n.tr("加入 %@ 個，其餘已在分頁裡", String(describing: added))
                                }
                            }
                        }) {
                            Text(L10n.tr("加入分頁"))
                                .foregroundStyle(DS.Palette.asagi)
                        }
                        .fixedSize()
                    }

                    if store.selectedCollectionId != nil {
                        // 文案是規格的一部分：這裡絕不能寫成「刪除」。
                        action(L10n.tr("從分頁移除"), colour: DS.Palette.textSecondary) {
                            store.removeSelectionFromCurrentCollection()
                            note = nil
                        }
                    }

                    action(L10n.tr("清除選取"), colour: DS.Palette.textSecondary) {
                        store.clearSelection()
                        note = nil
                    }

                    if let note {
                        Text(note)
                            .font(DS.TypeScale.label)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                }
                .padding(.horizontal, DS.Ma.group)
                .padding(.vertical, DS.Ma.tight)
                .background(DS.Palette.kozumi)
            }
            .onChange(of: store.selection) { _, _ in note = nil }
        }
    }

    @State private var note: String?

    private var offPageCount: Int {
        let page = Set(store.pageIds)
        return store.selection.sortedIds.filter { page.contains($0) == false }.count
    }

    private func action(_ title: String, colour: Color, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .foregroundStyle(colour)
        }
        .buttonStyle(.action)
    }
}
