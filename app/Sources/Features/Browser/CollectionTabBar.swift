import SwiftUI
import UniformTypeIdentifiers

/// 虛擬資料夾的分頁列。
///
/// 一個原則貫穿整個檔案：**分頁是一份名單，不是一個目錄。**
/// 所有跟移除有關的文案都必須說清楚磁碟上什麼都不會變，
/// 因為這個功能最容易出的錯就是使用者以為自己在刪檔案。
struct CollectionTabBar: View {
    @ObservedObject var store: LibraryStore
    @FocusState private var renameFocused: Bool
    @State private var draftName = ""
    @State private var pendingDelete: Collection?
    @State private var dropTarget: Int64?

    var body: some View {
        // 水平捲動：分頁的數量級跟頁碼不同，十幾個就頂天，捲動是標準做法。
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Ma.tight) {
                    libraryTab
                    ForEach(store.collections) { collection in
                        tab(collection).id(collection.id)
                    }
                    addButton
                }
                // 分頁自帶左右內距，外框少給一點，文字左緣才會跟標頭對齊。
                .padding(.horizontal, DS.Ma.group - DS.Ma.inline)
            }
            .onChange(of: store.selectedCollectionId) { _, id in
                // 選取的分頁一定要在可視範圍內，否則使用者會以為它不見了。
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(height: DS.Metrics.hitTarget + DS.Ma.tight)
        .alert(L10n.tr("刪除分頁"), isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button(L10n.tr("取消"), role: .cancel) { pendingDelete = nil }
            Button(L10n.tr("刪除分頁"), role: .destructive) {
                if let id = pendingDelete?.id { store.deleteCollection(id: id) }
                pendingDelete = nil
            }
        } message: {
            Text(L10n.tr("「%@」這個分頁會消失。\n音檔本身不會被刪除，磁碟上的檔案一個都不會變。", String(describing: pendingDelete?.name ?? "")))
        }
    }

    // MARK: - 分頁

    private var libraryTab: some View {
        Button {
            store.selectCollection(nil)
        } label: {
            label(L10n.tr("音色庫"), selected: store.selectedCollectionId == nil, highlighted: false)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tab(_ collection: Collection) -> some View {
        let id = collection.id ?? 0
        let isSelected = store.selectedCollectionId == id

        if store.renamingCollectionId == id {
            TextField("", text: $draftName)
                .textFieldStyle(.plain)
                .font(DS.TypeScale.action)
                .foregroundStyle(DS.Palette.textPrimary)
                .frame(width: 120)
                .focused($renameFocused)
                .onSubmit { commitRename(id) }
                .onAppear {
                    draftName = collection.name
                    renameFocused = true
                }
                .onChange(of: renameFocused) { _, focused in
                    if !focused { commitRename(id) }
                }
        } else {
            // 點擊維持用 Button：拿掉之後單擊選取就失效了（雙擊改名還在，
            // 但單擊被雙擊那個手勢吃掉）。放置點另外用 AppKit 疊在上面。
            Button {
                store.selectCollection(id)
            } label: {
                label(collection.name, selected: isSelected, highlighted: dropTarget == id)
            }
            .buttonStyle(.plain)
            .onTapGesture(count: 2) { beginRename(collection) }
            .contextMenu {
                Button(L10n.tr("重新命名")) { beginRename(collection) }
                Divider()
                Button(L10n.tr("刪除分頁（音檔不受影響）"), role: .destructive) {
                    pendingDelete = collection
                }
            }
            // 放置點交給 AppKit（見 FileDropTarget 的註解）：
            // SwiftUI 的 dropDestination 掛在 Button 上收不到東西，
            // 而單擊選取又必須是 Button。
            .overlay {
                FileDropTarget(
                    isTargeted: { targeted in dropTarget = targeted ? id : nil },
                    onDrop: { urls in store.acceptDrop(urls, into: id) })
            }
        }
    }

    private var addButton: some View {
        Button {
            store.createCollection()
        } label: {
            Text("＋")
                .font(DS.TypeScale.glyph)
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: DS.Metrics.hitTarget, height: DS.Metrics.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.tr("新增分頁"))
    }

    /// 選取沿用側邊欄的栞（shiori），拖曳目標用淡底，不引進新的視覺語彙。
    private func label(_ text: String, selected: Bool, highlighted: Bool) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(selected ? DS.Palette.asagi : Color.clear)
                .frame(width: 2, height: 12)
            Text(text)
                .font(DS.TypeScale.action)
                .foregroundStyle(selected ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                .lineLimit(1)
        }
        // 分頁的點擊範圍與文字按鈕一致（D-041）。放置點 FileDropTarget 疊在這個 label 上，
        // 所以放大 label 也同時放大了拖放目標。
        .padding(.horizontal, DS.Ma.inline)
        .frame(minHeight: DS.Metrics.hitTarget)
        .background {
            if highlighted {
                Rectangle().fill(DS.Palette.asagi.opacity(0.18))
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - 改名

    private func beginRename(_ collection: Collection) {
        draftName = collection.name
        store.renamingCollectionId = collection.id
    }

    private func commitRename(_ id: Int64) {
        guard store.renamingCollectionId == id else { return }
        store.renamingCollectionId = nil
        store.renameCollection(id: id, to: draftName)
    }
}
