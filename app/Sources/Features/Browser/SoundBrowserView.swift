import AppKit
import SwiftUI

struct SoundBrowserView: View {
    @ObservedObject var store: LibraryStore
    /// 打開批次接受的面板。由 RootView 提供。
    var onBatchReview: () -> Void = {}
    /// 打開依分類自動建立分頁的面板。
    var onAutoFill: () -> Void = {}
    /// 打開命名預覽。這個面板不會改任何東西。
    var onNamingPreview: () -> Void = {}
    /// 打開「接受這一類的建議」（M41）。
    var onCategoryAccept: () -> Void = {}
    var onOrganizerSettings: () -> Void = {}
    @FocusState private var listFocused: Bool
    /// 拖曳重排時的插入位置提示。
    @State private var dropRowId: Int64?

    private func select(_ sound: Sound) {
        listFocused = true
        store.selectOnly(sound.rowId)
        store.selectionDidChange()
    }

    /// 帶修飾鍵的點擊。⌘ 單獨加減、⇧ 選一段、什麼都不按就是只選這一個。
    ///
    /// SwiftUI 的 `onTapGesture` 不給修飾鍵，所以在點擊發生的當下直接問 AppKit。
    /// `modifierKeyAlternate` 會在按著修飾鍵時整個換掉這一列的內容，
    /// 只是為了讀一個旗標不值得讓列表在按著 ⌘ 時閃一下。
    private func click(_ sound: Sound) {
        listFocused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            store.toggleSelection(sound.rowId)
        } else if flags.contains(.shift) {
            store.extendSelection(to: sound.rowId)
        } else {
            select(sound)
        }
    }

    /// 拖曳時跟著游標的東西。
    @ViewBuilder
    private func dragPreview(_ sound: Sound) -> some View {
        let dragging = store.selection.isMultiple && store.selection.contains(sound.rowId)
        HStack(spacing: DS.Ma.tight) {
            Text(dragging ? L10n.files(store.selection.count) : sound.browserTitle)
                .font(DS.TypeScale.rowTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Ma.block)
        .padding(.vertical, DS.Ma.tight)
        .background(DS.Palette.kozumi)
    }

    @ViewBuilder
    private func rowMenu(_ sound: Sound) -> some View {
        Button(L10n.tr("播放")) {
            select(sound)
            store.playSelected()
        }
        Divider()

        if store.collections.isEmpty == false {
            // 複選時右鍵是對整批動作。標題把數量寫出來，
            // 按下去才不會以為只動到游標底下那一個。
            Menu(store.selection.isMultiple ? L10n.tr("加入分頁（%@ 個）", String(describing: store.selection.count)) : L10n.tr("加入分頁")) {
                ForEach(store.collections) { collection in
                    Button(collection.name) {
                        store.addSelectionToCollection(collection.id ?? 0)
                    }
                }
            }
        }
        if store.selectedCollectionId != nil {
            // 文案是規格的一部分：這裡絕不能寫成「刪除」。
            Button(store.selection.isMultiple
                   ? L10n.tr("從分頁移除 %@ 個（不會刪除檔案）", String(describing: store.selection.count))
                   : L10n.tr("從分頁移除（不會刪除檔案）")) {
                store.removeSelectionFromCurrentCollection()
            }
        }

        Divider()
        Button(L10n.tr("在 Finder 中顯示")) { store.revealInFinder(sound) }
        Button(L10n.tr("複製檔案路徑")) { store.copyPath(sound) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            categoryBar

            if store.sounds.isEmpty {
                EmptyStateView(title: emptyTitle, message: emptyMessage)
            } else {
                List {
                    ForEach(store.sounds, id: \.rowId) { sound in
                        SoundRow(sound: sound,
                                 isSelected: store.selection.contains(sound.rowId)
                                             || sound.rowId == store.selectedSoundId,
                                 isFocused: sound.rowId == store.selectedSoundId,
                                 isPlaying: store.preview.state.soundId == sound.rowId
                                            && store.preview.state.isPlaying,
                                 peaks: store.waveforms[sound.rowId],
                                 // 分類檢視裡，沒有已確定分類的那些列是靠建議進來的。
                                 isSuggestion: store.currentCategoryPath != nil
                                               && sound.categoryId == nil)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .contentShape(Rectangle())
                            // 次數多的要先宣告，否則雙擊會被單擊先吃掉
                            .onTapGesture(count: 2) {
                                select(sound)
                                store.playSelected()
                            }
                            .onTapGesture {
                                click(sound)
                            }
                            .contextMenu { rowMenu(sound) }
                            // 拖曳預覽要說出實際會被拖走的筆數。
                            // onDrag 只給得出一個檔案 URL，畫面上又只有一個
                            // 檔案圖示的話，使用者會以為複選沒生效。
                            .onDrag {
                                store.dragItem(for: sound)
                            } preview: {
                                dragPreview(sound)
                            }
                            // 分頁檢視裡，每一列都是一個放置點：拖到某一列上＝插在它前面。
                            // 用 dropDestination 而不是 List 的 onMove，是為了沿用同一個
                            // 拖曳來源（檔案 URL）。onMove 會另外開一套拖曳語意，
                            // 跟既有的單擊／雙擊／拖去 Logic 打架。
                            .dropDestination(for: URL.self) { urls, _ in
                                guard store.selectedCollectionId != nil else { return false }
                                return store.dropInCollection(urls: urls, before: sound.rowId)
                            } isTargeted: { targeted in
                                dropRowId = (targeted && store.selectedCollectionId != nil)
                                    ? sound.rowId : nil
                            }
                            .overlay(alignment: .top) {
                                if dropRowId == sound.rowId {
                                    Rectangle()
                                        .fill(DS.Palette.asagi)
                                        .frame(height: 2)
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, DS.Metrics.rowHeight)
            }

            footer
        }
        .background(DS.Palette.sumi)
        .searchable(text: $store.searchText, placement: .toolbar, prompt: L10n.tr("搜尋"))
        .focusable()
        .focused($listFocused)
        .onKeyPress(.space) {
            store.togglePreview()
            return .handled
        }
        // ⇧ 方向鍵是「把選取往外擴一列」，所以**不播放**——
        // 圈一段要圈十幾列，每一列都響一下沒辦法用。
        // 沒按 ⇧ 的方向鍵維持原本的行為：移動並自動播放。
        .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
            let forward = press.key == .downArrow
            if press.modifiers.contains(.shift) {
                store.extendSelectionByOneRow(forward: forward)
            } else if forward {
                store.selectNext()
            } else {
                store.selectPrevious()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            guard store.selection.isMultiple else { return .ignored }
            store.clearSelection()
            return .handled
        }
        .onKeyPress(.return) {
            store.playSelected()
            return .handled
        }
        // 審核是一直往下的動作，A/R 按完自動跳下一筆。
        //
        // 這裡一定要自己檢查修飾鍵：不檢查的話 ⌘A（全選這一頁）會**順便接受**
        // 游標那一筆的建議——使用者只是想選取，結果人工欄位被寫進去了。
        .onKeyPress(keys: [KeyEquivalent("a")], phases: .down) { press in
            if press.modifiers.contains(.command) {
                store.selectAllOnPage()
                return .handled
            }
            guard press.modifiers.isEmpty, store.pendingSuggestions.isEmpty == false else {
                return .ignored
            }
            store.acceptSelectedAndAdvance()
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("r")], phases: .down) { press in
            // 同上：⌘R 之類的系統快捷鍵不該被當成「拒絕」。
            guard press.modifiers.isEmpty, store.pendingSuggestions.isEmpty == false else {
                return .ignored
            }
            store.rejectSelectedAndAdvance()
            return .handled
        }
    }

    private var emptyTitle: String {
        if !store.searchText.isEmpty { return L10n.tr("沒有符合的結果") }
        if store.selectedCollectionId != nil { return L10n.tr("這個分頁還是空的") }
        if store.libraries.isEmpty { return L10n.tr("尚未加入音色庫") }
        return L10n.tr("這個檢視沒有音效")
    }

    private var emptyMessage: String {
        if !store.searchText.isEmpty { return L10n.tr("換個關鍵字，或清除搜尋。") }
        if store.selectedCollectionId != nil {
            return L10n.tr("回到 LIBRARY 分頁，把音檔拖到上面的分頁名稱上就會加進來。原始檔案不會被移動。")
        }
        if store.libraries.isEmpty {
            return L10n.tr("用工具列的 ＋ 選一個含音效檔的資料夾。原始檔案不會被移動或改名。")
        }
        return L10n.tr("索引在 M2 實作；在那之前這裡只會顯示已存在的紀錄。")
    }

    /// 欄位標頭。只標記兩件事：聲音本身，以及它的長度。
    private var header: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                headerRow(showLength: true)
                headerRow(showLength: false)
                headerRow(showLength: false, compressTitle: true)
            }
            .frame(height: DS.Metrics.hitTarget)
            .padding(.leading, DS.Ma.group)
            .padding(.trailing, DS.Ma.group)
            // 按鈕自帶 28pt 的點擊範圍（D-041），上方留白相應縮小，整體高度只多幾點。
            .padding(.top, DS.Ma.block)

            CollectionTabBar(store: store)
                .padding(.bottom, DS.Ma.tight)

            MaRule(inset: DS.Ma.group)
        }
    }

    /// Narrow columns retain complete labels; the duration heading is decorative.
    private func headerRow(showLength: Bool, compressTitle: Bool = false) -> some View {
        HStack(spacing: DS.Ma.block) {
            SectionLabel(text: store.selectedCollectionId.map(store.collectionName) ?? store.filter.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: !compressTitle, vertical: false)
                .help(store.selectedCollectionId.map(store.collectionName) ?? store.filter.title)

            // 分析是會改動整個音色庫的動作，入口要看得到但不能搶戲。
            // 重跑分開放，因為它會覆蓋掉已經審核過的建議——不該跟平常的動作同一鍵。
            MenuButton(entries: {[
                .item(L10n.tr("分析尚未分析的檔案")) { store.analyzeLibrary() },
                .divider,
                .item(L10n.tr("重新分析全部（會覆蓋既有建議）")) { store.analyzeLibrary(includeAnalysed: true) },
                .divider,
                .item(L10n.tr("批次接受建議⋯⋯")) { onBatchReview() },
                .divider,
                .item(L10n.tr("分析與備份⋯⋯")) { onOrganizerSettings() },
            ]}) {
                Text(L10n.tr("分析"))
                    .foregroundStyle(store.batchProgress.isRunning
                                     ? DS.Palette.textTertiary
                                     : DS.Palette.asagi)
            }
            .fixedSize()
            .disabled(store.batchProgress.isRunning || store.scanProgress.isRunning)

            // 把目前的檢視變成分頁。分析的結果要能一步變成你找音的入口，
            // 不然那些分類只是資料庫裡的欄位。
            MenuButton(entries: { collectEntries }) {
                Text(L10n.tr("整理"))
                    .foregroundStyle(DS.Palette.asagi)
            }
            .fixedSize()

            Spacer(minLength: 0)
            if showLength {
                SectionLabel(text: L10n.tr("length"))
                    .frame(width: DS.Metrics.durationLane, alignment: .leading)
                Spacer().frame(width: DS.Metrics.numeralColumn)
            }
        }
    }

    /// 分類檢視的說明列（M41）。有還沒確認的建議時才出現。
    ///
    /// 側欄把建議也算進分類裡，這一列負責把話說清楚：這裡有幾筆只是分析的猜測，
    /// 以及要怎麼把它們變成你確認過的分類。
    @ViewBuilder
    private var categoryBar: some View {
        if let node = store.currentCategoryNode, node.suggested > 0 {
            VStack(spacing: 0) {
                HStack(spacing: DS.Ma.inline) {
                    Circle().fill(DS.Palette.kihada).frame(width: 4, height: 4)
                    Text(L10n.tr("%@ 筆是分析建議，還沒確認", String(describing: node.suggested)))
                        .font(DS.TypeScale.rowMeta)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                    if node.confirmed > 0 {
                        Text(L10n.tr("已確定 %@", String(describing: node.confirmed)))
                            .font(DS.TypeScale.rowMeta)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: DS.Ma.inline)
                    Button(L10n.tr("接受這一類的建議⋯⋯")) { onCategoryAccept() }
                        .buttonStyle(ActionButtonStyle(flush: .trailing))
                        .foregroundStyle(DS.Palette.asagi)
                        .fixedSize()
                }
                .padding(.horizontal, DS.Ma.group)
                .padding(.vertical, DS.Ma.hair)

                MaRule(inset: DS.Ma.group)
            }
        }
    }

    /// 「整理」選單。項目在按下時才產生，分頁清單永遠是最新的。
    private var collectEntries: [MenuEntry] {
        var entries: [MenuEntry] = [
            .item(L10n.tr("把目前這個檢視存成新分頁")) { store.addCurrentViewToNewCollection() },
        ]
        if store.collections.isEmpty == false {
            entries.append(.divider)
            for collection in store.collections {
                let id = collection.id ?? 0
                entries.append(.item(L10n.tr("加入「%@」", String(describing: collection.name))) { store.addCurrentViewToCollection(id) })
            }
        }
        entries += [
            .divider,
            .item(L10n.tr("依分類自動建立分頁⋯⋯")) { onAutoFill() },
            // 文案要讓人知道按下去不會發生任何事——它只是一份清單。
            .item(L10n.tr("命名預覽（不會改任何東西）⋯⋯")) { onNamingPreview() },
            .divider,
            // 這兩個都只讀路徑，不開任何音檔。
            .item(L10n.tr("重讀路徑欄位（不改分類）")) { store.rereadPaths() },
            .item(L10n.tr("只補材質")) { store.backfillTextures() },
        ]
        return entries
    }

    /// 篩選列。全部收在一行，沒有作用時保持低對比，不跟內容搶注意力。
    private var filterBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Ma.block) {
                toggleChip("★", active: store.filters.favoritesOnly) {
                    store.filters.favoritesOnly.toggle()
                }

                chipMenu(store.filters.minRating == 0 ? L10n.tr("評分") : "★\(store.filters.minRating)+",
                         active: store.filters.minRating > 0) {
                    (0...5).map { value -> MenuEntry in
                        .item(value == 0 ? L10n.tr("不限評分") : L10n.tr("★ %@ 以上", String(describing: value)),
                              checked: store.filters.minRating == value) { store.filters.minRating = value }
                    }
                }

                chipMenu(store.filters.duration == .any ? L10n.tr("長度") : store.filters.duration.title,
                         active: store.filters.duration != .any) {
                    SoundFilters.DurationBand.allCases.map { band -> MenuEntry in
                        .item(band.title, checked: store.filters.duration == band) { store.filters.duration = band }
                    }
                }

                chipMenu(store.filters.loop == .any ? L10n.tr("Loop") : store.filters.loop.title,
                         active: store.filters.loop != .any) {
                    SoundFilters.LoopBand.allCases.map { band -> MenuEntry in
                        .item(band.title, checked: store.filters.loop == band) { store.filters.loop = band }
                    }
                }

                chipMenu(store.filters.tempo == .any ? L10n.tr("BPM") : store.filters.tempo.title,
                         active: store.filters.tempo != .any) {
                    SoundFilters.TempoBand.allCases.map { band -> MenuEntry in
                        .item(band.title, checked: store.filters.tempo == band) { store.filters.tempo = band }
                    }
                }

                if !store.availableFileTypes.isEmpty {
                    chipMenu(store.filters.fileTypes.isEmpty
                             ? L10n.tr("格式")
                             : store.filters.fileTypes.sorted().joined(separator: " "),
                             active: !store.filters.fileTypes.isEmpty) {
                        store.availableFileTypes.map { ext -> MenuEntry in
                            .item(ext, checked: store.filters.fileTypes.contains(ext)) {
                                store.filters.toggleFileType(ext)
                            }
                        }
                    }
                }

                Spacer()

                if store.filters.isActive || !store.searchText.isEmpty {
                    Button {
                        store.clearFilters()
                        store.searchText = ""
                    } label: {
                        Text(L10n.tr("清除篩選")).fixedSize()
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    .buttonStyle(ActionButtonStyle(flush: .trailing))
                }
            }
            .padding(.horizontal, DS.Ma.group)
            .padding(.vertical, DS.Ma.tight)
            }
            .frame(height: DS.Metrics.hitTarget + DS.Ma.tight * 2)

            MaRule(inset: DS.Ma.group)
        }
    }

    /// 篩選 chip 形狀的選單按鈕。見 `PopUpMenu` 為何不用 SwiftUI 的 `Menu`（D-041）。
    private func chipMenu(_ text: String, active: Bool,
                          entries: @escaping () -> [MenuEntry]) -> some View {
        Button {
            PopUpMenu.show(entries())
        } label: {
            chipLabel(text, active: active)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func toggleChip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chipLabel(text, active: active)
        }
        .buttonStyle(.plain)   // chipLabel 已經自帶點擊範圍與底色
    }

    /// 篩選 chip。字與點擊範圍跟文字按鈕一致（D-041）；啟用中的 chip 保留浅葱底。
    private func chipLabel(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(DS.TypeScale.action)
            .foregroundStyle(active ? DS.Palette.asagi : DS.Palette.textSecondary)
            .padding(.horizontal, DS.Ma.inline)
            .frame(minWidth: DS.Metrics.hitTarget, minHeight: DS.Metrics.hitTarget)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(active ? DS.Palette.asagi.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
    }

    private var footer: some View {
        VStack(spacing: 0) {
            MaRule()

            if store.scanProgress.isRunning {
                scanFooter
            } else if store.batchProgress.isRunning {
                batchFooter
            } else {
                countFooter
                if store.pageCount > 1 {
                    pageBar
                }
            }
        }
    }

    private var scanFooter: some View {
        VStack(alignment: .leading, spacing: DS.Ma.tight) {
            HStack(spacing: DS.Ma.inline) {
                SectionLabel(text: store.scanProgress.phase == .discovering ? L10n.tr("scanning") : L10n.tr("reading audio"))

                Text(store.scanProgress.phase == .discovering
                     ? "\(store.scanProgress.discovered)"
                     : "\(store.scanProgress.processed) / \(store.scanProgress.total ?? 0)")
                    .font(DS.TypeScale.mono)
                    .foregroundStyle(DS.Palette.textSecondary)

                Text(store.scanProgress.currentName)
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)

                Spacer()

                Button {
                    store.cancelScan()
                } label: {
                    Text(L10n.tr("中止"))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                .buttonStyle(ActionButtonStyle(flush: .trailing))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(DS.Palette.hairlineFaint)
                        .frame(height: 1)
                    Rectangle()
                        .fill(DS.Palette.asagi)
                        .frame(width: max(2, geo.size.width * store.scanProgress.fraction), height: 2)
                }
            }
            .frame(height: 2)
        }
        .padding(.horizontal, DS.Ma.group)
        .padding(.vertical, DS.Ma.block)
    }

    /// 批次分析的進度。刻意與掃描共用同一套視覺，
    /// 使用者不需要為了兩件相似的事學兩種介面。
    private var batchFooter: some View {
        VStack(alignment: .leading, spacing: DS.Ma.tight) {
            HStack(spacing: DS.Ma.inline) {
                SectionLabel(text: L10n.tr("analysing"))

                Text("\(store.batchProgress.completed) / \(store.batchProgress.total)")
                    .font(DS.TypeScale.mono)
                    .foregroundStyle(DS.Palette.textSecondary)

                Text(store.batchProgress.currentName)
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)

                Spacer()

                if store.batchProgress.needsReview > 0 {
                    HStack(spacing: DS.Ma.tight) {
                        Circle().fill(DS.Palette.kihada).frame(width: 4, height: 4)
                        Text(L10n.tr("%@ 待複查", String(describing: store.batchProgress.needsReview)))
                            .font(DS.TypeScale.label)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                }

                Button {
                    store.cancelBatchAnalysis()
                } label: {
                    Text(L10n.tr("中止"))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                .buttonStyle(ActionButtonStyle(flush: .trailing))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(DS.Palette.hairlineFaint)
                        .frame(height: 1)
                    Rectangle()
                        .fill(DS.Palette.asagi)
                        .frame(width: max(2, geo.size.width * store.batchProgress.fraction), height: 2)
                }
            }
            .frame(height: 2)
        }
        .padding(.horizontal, DS.Ma.group)
        .padding(.vertical, DS.Ma.block)
    }

    private var countFooter: some View {
        HStack(spacing: DS.Ma.block) {
            Text(store.pageRangeText)
                .font(DS.TypeScale.mono)
                .foregroundStyle(DS.Palette.textSecondary)
            Text("/")
                .font(DS.TypeScale.mono)
                .foregroundStyle(DS.Palette.textTertiary)
            Text(L10n.sounds(store.totalCount))
                .font(DS.TypeScale.mono)
                .foregroundStyle(DS.Palette.textSecondary)

            Spacer()

            // 單檔分析的結果。優先於批次摘要，因為它是使用者剛剛按下去的那一個動作。
            if store.lastError == nil, let note = store.lastAnalysisNote {
                HStack(spacing: DS.Ma.tight) {
                    Circle().fill(DS.Palette.asagi).frame(width: 4, height: 4)
                    Text(note)
                        .font(DS.TypeScale.label)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }
                .layoutPriority(0)
                Spacer()
            }

            // 批次分析結束後的結果留在原地，不用彈窗打斷，也不要一閃就消失。
            if store.lastError == nil, store.lastAnalysisNote == nil,
               store.batchProgress.summary.isEmpty == false {
                HStack(spacing: DS.Ma.tight) {
                    Circle()
                        .fill(store.batchProgress.failed > 0 ? DS.Palette.kihada : DS.Palette.asagi)
                        .frame(width: 4, height: 4)
                    Text(store.batchProgress.summary)
                        .font(DS.TypeScale.label)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }
                .layoutPriority(0)
                Spacer()
            }

            if let error = store.lastError {
                HStack(spacing: DS.Ma.tight) {
                    Circle().fill(DS.Palette.kihada).frame(width: 4, height: 4)
                    Text(error)
                        .font(DS.TypeScale.label)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(0)
                Spacer()
            }

            pageSizeMenu
                .fixedSize()
                .layoutPriority(1)
        }
        .padding(.horizontal, DS.Ma.group)
        .padding(.vertical, DS.Ma.block)
    }

    /// 頁碼獨立一行。
    ///
    /// 2065 頁的頁碼列擠不進計數那一行——瀏覽器欄最窄只有 380pt，
    /// 硬塞的結果是筆數和狀態訊息被切掉。多一行 24pt 換一個看得懂的翻頁列，划算。
    private var pageBar: some View {
        // 按鈕放大到 28pt 之後（D-041），四位數頁碼在最窄的 380pt 欄寬會擠不下。
        // 依序退讓：先把目前頁前後各 2 頁縮成 1 頁，再拿掉「第一頁／最後一頁」兩顆符號鈕
        // （頁碼列本來就永遠顯示第 1 頁與最後一頁，功能不會少）。
        ViewThatFits(in: .horizontal) {
            pageBarRow(window: Pagination.defaultWindow, showEnds: true)
            pageBarRow(window: 1, showEnds: true)
            pageBarRow(window: 1, showEnds: false)
        }
        .padding(.horizontal, DS.Ma.group)
        .padding(.bottom, DS.Ma.inline)
    }

    private func pageBarRow(window: Int, showEnds: Bool) -> some View {
        HStack(spacing: DS.Ma.hair) {
            if showEnds {
                pagerButton("⇤", enabled: store.canGoBack) { store.firstPage() }
            }
            pagerButton("◀", enabled: store.canGoBack) { store.previousPage() }

            ForEach(Array(Pagination.tokens(total: store.pageCount,
                                            current: store.page + 1,
                                            window: window).enumerated()),
                    id: \.offset) { _, token in
                switch token {
                case .page(let number):
                    pageNumberButton(number)
                case .gap:
                    Text("…")
                        .font(DS.TypeScale.monoLarge)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(width: 16)
                }
            }

            pagerButton("▶", enabled: store.canGoForward) { store.nextPage() }
            if showEnds {
                pagerButton("⇥", enabled: store.canGoForward) { store.lastPage() }
            }
        }
        .fixedSize()
    }

    private func pageNumberButton(_ number: Int) -> some View {
        let isCurrent = number == store.page + 1
        return Button {
            store.goToPage(number)
        } label: {
            Text("\(number)")
                // 等寬字體：頁碼從 99 變 100 時整排才不會跳。
                .font(DS.TypeScale.monoLarge)
                .foregroundStyle(isCurrent ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                .padding(.horizontal, DS.Ma.tight)
                .frame(minWidth: DS.Metrics.hitTarget, minHeight: DS.Metrics.hitTarget)
                .background {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 3).fill(DS.Palette.nezumi.opacity(0.5))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)   // 頁碼自帶點擊範圍；目前頁的底色不能被 hover 蓋掉
        .disabled(isCurrent)
    }

    private var pageSizeMenu: some View {
        MenuButton(style: ActionButtonStyle(flush: .trailing), entries: {
            LibraryStore.pageSizeOptions.map { size -> MenuEntry in
                .item(L10n.tr("每頁 %@ 筆", String(describing: size)), checked: store.pageSize == size) { store.pageSize = size }
            }
        }) {
            Text(L10n.tr("每頁 %@ ▾", String(describing: store.pageSize)))
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }

    private func pagerButton(_ glyph: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(DS.TypeScale.glyph)
                .foregroundStyle(enabled ? DS.Palette.asagi : DS.Palette.textTertiary.opacity(0.4))
                .frame(width: DS.Metrics.hitTarget, height: DS.Metrics.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct SoundRow: View {
    let sound: Sound
    /// 在選取範圍裡。複選時可能有很多列同時是 true。
    let isSelected: Bool
    /// 焦點那一列——Inspector、審核列、方向鍵都跟著它。
    /// 複選時要看得出「整批裡面現在停在哪一個」，所以左邊那條書籤只畫在它身上。
    var isFocused: Bool = true
    var isPlaying: Bool = false
    var peaks: [UInt8]? = nil
    /// 靠分析建議出現在這個分類裡、還沒確認的一列（M41）。
    var isSuggestion: Bool = false

    var body: some View {
        HStack(spacing: DS.Ma.block) {
            // 狀態：實心 = 待複查，空心 = 離線，無 = 正常
            ZStack {
                if isPlaying {
                    Rectangle()
                        .fill(DS.Palette.asagi)
                        .frame(width: 2, height: 10)
                } else if sound.needsReview {
                    Circle().fill(DS.Palette.kihada).frame(width: 4, height: 4)
                } else if sound.status != .ok {
                    Circle().stroke(DS.Palette.textTertiary, lineWidth: 0.8).frame(width: 4, height: 4)
                }
            }
            .frame(width: 5)

            VStack(alignment: .leading, spacing: DS.Ma.hair) {
                Text(sound.browserTitle)
                    .font(DS.TypeScale.rowTitle)
                    .foregroundStyle(isSelected ? DS.Palette.textPrimary : DS.Palette.textPrimary.opacity(0.82))
                    .lineLimit(1)
                Text(sound.relativePath)
                    .font(DS.TypeScale.rowMeta)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: DS.Ma.block)

            if isSuggestion {
                Text(L10n.tr("建議"))
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.kihada)
                    .help(L10n.tr("分析的建議，還沒確認。在 Inspector 接受，或用上方的「接受這一類的建議」。"))
            }

            if sound.favorite {
                Circle()
                    .fill(DS.Palette.asagi)
                    .frame(width: 4, height: 4)
            }

            RowWaveform(peaks: peaks.map { WaveformGenerator.downsample($0, to: 52) },
                        duration: sound.duration,
                        emphasized: isSelected || isPlaying)

            Text(Format.seconds(sound.duration))
                .font(DS.TypeScale.mono)
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: DS.Metrics.numeralColumn, alignment: .trailing)
        }
        .padding(.horizontal, DS.Ma.group)
        .frame(height: DS.Metrics.rowHeight)
        .background(alignment: .leading) {
            if isSelected {
                ZStack(alignment: .leading) {
                    DS.Palette.selection
                    if isFocused {
                        Rectangle()
                            .fill(DS.Palette.asagi)
                            .frame(width: DS.Metrics.shioriWidth)
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }
}
