import AppKit
import Foundation
import SwiftUI

extension Sound {
    /// List 選取用的非 optional 識別碼。
    var rowId: Int64 { id ?? -1 }
}

@MainActor
final class LibraryStore: ObservableObject {
    private let services: AppEnvironment.Services

    @Published var filter: SoundFilter = .all {
        didSet {
            // 側邊欄與分頁互斥，不疊加：側邊欄一被點，就切回 LIBRARY 分頁。
            // 疊加（「Lo-Fi 資料夾 ∩ 我的分頁」）介面上沒有地方顯示同時套了兩個條件，
            // 使用者會以為分頁壞了。
            if case .collection = filter {} else { selectedCollectionId = nil }
            page = 0
            reload()
        }
    }
    @Published var searchText: String = "" { didSet { page = 0; reload() } }
    @Published var filters = SoundFilters() { didSet { page = 0; reload() } }
    @Published private(set) var availableFileTypes: [String] = []
    /// 側欄的風格清單。多的在前。
    @Published private(set) var styleCounts: [(style: String, count: Int)] = []
    @Published var showAllStyles = false
    /// 側欄的材質清單。多的在前。
    @Published private(set) var textureCounts: [(texture: String, count: Int)] = []
    @Published var showAllTextures = false
    @Published var selectedSoundId: Int64? {
        didSet {
            guard suppressSelectionSync == false else { return }
            if let selectedSoundId { selection.replace(with: selectedSoundId) } else { selection.clear() }
        }
    }

    /// 複選狀態。`selectedSoundId` 仍然是「焦點那一列」——Inspector、審核列、
    /// 波形都跟著它，複選只是額外多記了哪些列也被選到。
    @Published private(set) var selection = SoundSelection()

    /// 改 `selectedSoundId` 時不要動複選。
    /// 換頁、複選手勢自己維護 `selection`，讓 didSet 也插手會把整批選取洗掉。
    private var suppressSelectionSync = false

    private func withoutSelectionSync(_ body: () -> Void) {
        suppressSelectionSync = true
        body()
        suppressSelectionSync = false
    }

    /// 當前頁的 id，順序與畫面一致。shift 範圍選取要用。
    var pageIds: [Int64] { sounds.map(\.rowId) }
    @Published private(set) var sounds: [Sound] = []
    @Published private(set) var analysis: OrganizerAnalysis?
    @Published private(set) var suggestions: [OrganizerSuggestion] = []
    @Published private(set) var selectedTags: [SoundTagView] = []
    @Published private(set) var selectedCategoryPath: String?
    @Published private(set) var counts: [SoundFilter: Int] = [:]
    @Published private(set) var libraries: [Library] = []
    @Published private(set) var libraryCounts: [Int64: Int] = [:]
    @Published private(set) var folderTrees: [Int64: [FolderNode]] = [:]
    @Published var expandedLibraries: Set<Int64> = [] { didSet { persistExpansion() } }
    @Published var expandedFolders: Set<String> = [] { didSet { persistExpansion() } }
    @Published private(set) var scanProgress = ScanProgress()
    @Published private(set) var totalCount: Int = 0

    private var scanTask: Task<Void, Never>?
    private var scanRequestId: UUID?

    // MARK: - 虛擬資料夾（M33）

    @Published private(set) var collections: [Collection] = []
    /// nil 代表在 LIBRARY 分頁。
    @Published private(set) var selectedCollectionId: Int64?
    /// 正在改名的分頁。
    @Published var renamingCollectionId: Int64?

    private enum CollectionKey {
        static let selected = "browser.selectedCollection"
    }

    @Published private(set) var batchProgress = BatchAnalysisProgress()
    private var batchTask: Task<Void, Never>?

    // MARK: - 分析引擎

    /// 引擎只有一個：本機。
    ///
    /// Antigravity 曾經是個選項，實測證明它讀不到音訊而且會用高信心編造描述
    /// （D-013）。選單留著一個「知情的錯誤選項」只會讓人有一天選下去，
    /// 所以整個移除了。歷史留在 DECISIONS.md。
    func currentEngine() -> OrganizerEngine { services.organizer }

    var organizerStatus: String { L10n.tr("本機聲學分析（不連網、不呼叫任何模型）") }

    /// 音訊預覽。PlaybackBar 直接觀察它——巢狀的 ObservableObject 不會自動轉發變更。
    let preview = AudioPreviewEngine()

    /// 目前送進預覽引擎的那個音效。
    ///
    /// 這件事必須跟「選取」分開記：換頁或換資料夾時，選取會被清掉
    /// （那一筆已經不在這一頁的清單裡），但聲音還在播。只看選取的話，
    /// 播放列會在使用者正在聽的時候整條空掉。
    @Published private(set) var playingSound: Sound?

    /// 播放列與波形該顯示誰。
    ///
    /// **正在播（含暫停）的時候，一律顯示正在播的那一個。**
    /// 邊聽 A 邊用滑鼠點 B 來看細節時，播放列跟著跳到 B 是錯的——
    /// 你聽到的是 A，波形卻在畫 B，游標還在 B 的時間軸上跑。
    /// 只有在什麼都沒在播的時候，播放列才預覽你選取的那一個。
    var barSound: Sound? {
        if preview.state.soundId != nil, let playingSound { return playingSound }
        return selectedSound ?? playingSound
    }

    var barWaveform: [UInt8]? {
        guard let id = barSound?.id else { return nil }
        return waveforms[id]
    }

    /// 已載入的波形。鍵是 sound id。
    @Published private(set) var waveforms: [Int64: [UInt8]] = [:]
    private var waveformTask: Task<Void, Never>?

    /// 選取即播放。預設關閉：一路按方向鍵掃過整個音色庫時，
    /// 自動播放會變成噪音而不是幫助。
    @Published var autoPreview: Bool = UserDefaults.standard.bool(forKey: "preview.auto") {
        didSet { UserDefaults.standard.set(autoPreview, forKey: "preview.auto") }
    }
    /// 每頁筆數。可調，預設 20。
    @Published var pageSize: Int = 20 { didSet { page = 0; reload() } }
    @Published private(set) var page: Int = 0

    static let pageSizeOptions = [20, 50, 100, 200, 500]
    @Published var lastError: String?
    /// 需要使用者注意的錯誤。角落一行小字會被忽略，該用對話框。
    @Published var alert: String?

    init(services: AppEnvironment.Services) {
        self.services = services
        restoreExpansion()
        reloadLibraries()
        reloadCollections()
        restoreSelectedCollection()
        reload()
    }

    // MARK: - 展開狀態

    private enum ExpansionKey {
        static let libraries = "sidebar.expandedLibraries"
        static let folders = "sidebar.expandedFolders"
        static let seeded = "sidebar.expansionSeeded"
    }

    private var isRestoringExpansion = false

    private func restoreExpansion() {
        isRestoringExpansion = true
        defer { isRestoringExpansion = false }

        let defaults = UserDefaults.standard
        let libraryIds = (defaults.array(forKey: ExpansionKey.libraries) as? [NSNumber]) ?? []
        expandedLibraries = Set(libraryIds.map { $0.int64Value })
        expandedFolders = Set((defaults.array(forKey: ExpansionKey.folders) as? [String]) ?? [])
    }

    private func persistExpansion() {
        guard !isRestoringExpansion else { return }
        let defaults = UserDefaults.standard
        defaults.set(expandedLibraries.map { NSNumber(value: $0) }, forKey: ExpansionKey.libraries)
        defaults.set(Array(expandedFolders), forKey: ExpansionKey.folders)
    }

    /// 第一次看到某個音色庫時預設展開它。
    /// 收合是使用者的選擇，收合狀態會被記住；但一個從沒被展開過的音色庫，
    /// 預設應該是打開的——否則重開 App 只會看到一行字，看不到自己的資料夾。
    private func seedExpansionForNewLibraries() {
        let defaults = UserDefaults.standard
        var seen = Set((defaults.array(forKey: ExpansionKey.seeded) as? [NSNumber])?.map { $0.int64Value } ?? [])
        var changed = false

        for library in libraries {
            guard let id = library.id, !seen.contains(id) else { continue }
            seen.insert(id)
            expandedLibraries.insert(id)
            changed = true
        }

        if changed {
            defaults.set(seen.map { NSNumber(value: $0) }, forKey: ExpansionKey.seeded)
        }
    }

    var selectedSound: Sound? {
        guard let selectedSoundId else { return nil }
        return sounds.first { $0.rowId == selectedSoundId }
    }

    var taxonomy: Taxonomy { services.taxonomy }
    var metadata: ManualMetadataService { services.metadata }

    /// 重新檢查音色庫可用性並更新側欄。
    /// 外接碟離線只會讓它變成 offline，不會影響任何既有 metadata。
    private var libraryReloadTask: Task<Void, Never>?
    private var libraryReloadQueued = false

    func reloadLibraries() {
        guard libraryReloadTask == nil else { libraryReloadQueued = true; return }
        let services = self.services
        libraryReloadTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { () throws -> ([Library], [Int64: Int], [Int64: [FolderNode]], [String], [(style: String, count: Int)], [(texture: String, count: Int)], [CategoryNode]) in
                    let libraries = try services.libraryManager.refreshAvailability()
                    var counts: [Int64: Int] = [:]
                    var trees: [Int64: [FolderNode]] = [:]
                    for library in libraries {
                        guard let id = library.id else { continue }
                        counts[id] = try services.libraryManager.soundCount(libraryId: id)
                        trees[id] = FolderTree.build(from: try services.repository.folderCounts(libraryId: id))
                    }
                    return (libraries, counts, trees, try services.repository.availableFileTypes(),
                            try services.repository.styleCounts(), try services.repository.textureCounts(),
                            CategoryTree.build(from: try services.repository.categoryCounts()))
                }
            }.value
            guard let self else { return }
            switch result {
            case .success(let snapshot):
                self.libraries = snapshot.0
                self.libraryCounts = snapshot.1
                self.folderTrees = snapshot.2
                self.availableFileTypes = snapshot.3
                self.styleCounts = snapshot.4
                self.textureCounts = snapshot.5
                self.categoryTree = snapshot.6
                self.seedExpansionForNewLibraries()
                self.reload()
            case .failure(let error): self.lastError = error.localizedDescription
            }
            self.libraryReloadTask = nil
            if self.libraryReloadQueued {
                self.libraryReloadQueued = false
                self.reloadLibraries()
            }
        }
    }

    /// 加入音色庫。原始檔案不會被移動、改名或改寫。
    func addLibrary() {
        let urls = services.folderPicker.pickFolders()
        guard !urls.isEmpty else { return }
        do {
            var added: [Library] = []
            for url in urls {
                let library = try services.libraryManager.add(url: url)
                guard library.id != nil else {
                    alert = L10n.tr("%@ 沒有被寫入資料庫", String(describing: url.lastPathComponent))
                    return
                }
                if library.availabilityStatus == .offline {
                    alert = L10n.tr("%@ 讀不到。若它在外接碟上，請確認硬碟已連接。", String(describing: url.lastPathComponent))
                }
                added.append(library)
            }
            reloadLibraries()
            reload()

            guard let first = added.first, let firstId = first.id else { return }
            // 確認它真的在資料庫裡，而不是只出現在畫面上
            guard try services.libraryManager.library(id: firstId) != nil else {
                alert = L10n.tr("加入後找不到這個音色庫，資料庫可能寫入失敗")
                return
            }
            filter = .library(firstId)
            expandedLibraries.insert(firstId)
            scanLibrary(first)
        } catch {
            alert = L10n.tr("無法加入音色庫：%@", String(describing: error.localizedDescription))
            lastError = error.localizedDescription
        }
    }

    // MARK: - 掃描

    /// 背景掃描。分兩段：先盤點檔案（清單很快就會出現），再讀音訊詮釋資料。
    func scanLibrary(_ library: Library) {
        guard let id = library.id else { return }
        guard let url = services.libraryManager.resolveURL(for: library) else {
            alert = L10n.tr("%@ 目前讀不到，無法掃描。外接碟請確認已連接。", String(describing: library.name))
            return
        }

        scanTask?.cancel()
        let requestId = UUID()
        scanRequestId = requestId
        scanProgress = ScanProgress(phase: .discovering)
        let scanner = services.scanner

        scanTask = Task.detached(priority: .utility) {
            let result = scanner.scan(
                libraryId: id,
                root: url,
                isCancelled: { Task.isCancelled },
                progress: { update in
                    Task { @MainActor in
                        guard self.scanRequestId == requestId else { return }
                        self.scanProgress = update
                    }
                })

            await MainActor.run {
                guard self.scanRequestId == requestId else { return }
                self.finishScan(result)
            }
        }
    }

    /// 把音色庫與資料夾樹攤平成側欄要畫的那幾列，只包含目前展開的部分。
    var sidebarItems: [SidebarItem] {
        var items: [SidebarItem] = []

        for library in libraries {
            guard let id = library.id else { continue }
            let tree = folderTrees[id] ?? []
            let isExpanded = expandedLibraries.contains(id)

            items.append(SidebarItem(
                id: "lib:\(id)",
                title: library.name,
                count: libraryCounts[id] ?? 0,
                depth: 0,
                filter: .library(id),
                disclosure: tree.isEmpty ? .none : (isExpanded ? .open : .closed),
                toggleKey: tree.isEmpty ? nil : "lib:\(id)",
                isOffline: library.availabilityStatus == .offline,
                libraryId: id))

            if isExpanded {
                appendFolders(tree, libraryId: id, depth: 1, into: &items)
            }
        }
        return items
    }

    private func appendFolders(_ nodes: [FolderNode],
                               libraryId: Int64,
                               depth: Int,
                               into items: inout [SidebarItem]) {
        for node in nodes {
            let key = "folder:\(libraryId)|\(node.path)"
            let isExpanded = expandedFolders.contains(key)

            items.append(SidebarItem(
                id: key,
                title: node.name,
                count: node.count,
                depth: depth,
                filter: .folder(libraryId: libraryId, path: node.path),
                disclosure: node.hasChildren ? (isExpanded ? .open : .closed) : .none,
                toggleKey: node.hasChildren ? key : nil,
                isOffline: false,
                libraryId: libraryId))

            if isExpanded {
                appendFolders(node.children, libraryId: libraryId, depth: depth + 1, into: &items)
            }
        }
    }

    /// 選取一列。若它有子項目而且是收合的，順便展開——
    /// 使用者點一個資料夾時的意圖是「我要看它」，不是「我要它保持關著」。
    func select(_ item: SidebarItem) {
        filter = item.filter
        if item.disclosure == .closed, let key = item.toggleKey {
            toggle(key)
        }
    }

    func toggle(_ key: String) {
        if key.hasPrefix("lib:") {
            if let id = Int64(key.dropFirst(4)) { toggleLibrary(id) }
        } else {
            toggleFolder(key)
        }
    }

    func library(withId id: Int64) -> Library? {
        libraries.first { $0.id == id }
    }

    func toggleLibrary(_ id: Int64) {
        if expandedLibraries.contains(id) {
            expandedLibraries.remove(id)
        } else {
            expandedLibraries.insert(id)
        }
    }

    func toggleFolder(_ key: String) {
        if expandedFolders.contains(key) {
            expandedFolders.remove(key)
        } else {
            expandedFolders.insert(key)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func rescanSelectedLibrary() {
        if case .library(let id) = filter,
           let library = libraries.first(where: { $0.id == id }) {
            scanLibrary(library)
        }
    }

    private func finishScan(_ result: ScanResult) {
        reloadLibraries()
        reload()
        if let error = result.errorMessage {
            lastError = error
            alert = L10n.tr("掃描未完成：") + error
            return
        }
        if result.discovered == 0 && !result.cancelled {
            alert = L10n.tr("這個資料夾裡沒有找到支援的音訊檔（wav / aif / aiff / caf / mp3 / m4a / flac）。")
        }
        if result.unreadable > 0 {
            lastError = L10n.tr("%@ 個檔案讀不到音訊，已保留紀錄並標記", String(describing: result.unreadable))
        } else {
            lastError = nil
        }
    }

    func removeLibrary(_ library: Library) {
        guard let id = library.id else { return }
        do {
            try services.libraryManager.remove(libraryId: id)
            if filter == .library(id) { filter = .all }
            reloadLibraries()
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearFilters() {
        filters.clear()
    }

    // MARK: - 分頁

    var pageCount: Int {
        max(1, Int((Double(totalCount) / Double(pageSize)).rounded(.up)))
    }

    var pageRangeText: String {
        guard totalCount > 0 else { return "0" }
        let first = page * pageSize + 1
        let last = min(totalCount, (page + 1) * pageSize)
        return "\(first)–\(last)"
    }

    var canGoBack: Bool { page > 0 }
    var canGoForward: Bool { page + 1 < pageCount }

    func nextPage() {
        guard canGoForward else { return }
        page += 1
        reload()
    }

    func previousPage() {
        guard canGoBack else { return }
        page -= 1
        reload()
    }

    /// 跳到指定頁。頁碼從 1 開始，超出範圍會被夾到合法區間。
    func goToPage(_ oneIndexed: Int) {
        let target = min(max(oneIndexed, 1), pageCount) - 1
        guard target != page else { return }
        page = target
        reload()
    }

    /// 翻頁列要顯示的內容。
    var pageTokens: [PageToken] {
        Pagination.tokens(total: pageCount, current: page + 1)
    }

    func firstPage() {
        guard page != 0 else { return }
        page = 0
        reload()
    }

    func lastPage() {
        let target = pageCount - 1
        guard page != target else { return }
        page = target
        reload()
    }

    func reload() {
        do {
            totalCount = try services.repository.count(filter: filter,
                                                       search: searchText,
                                                       filters: filters)
            // 資料變少時（例如重新掃描後）目前頁次可能已經超出範圍
            if page >= pageCount { page = max(0, pageCount - 1) }
            sounds = try services.repository.fetch(filter: filter,
                                                   search: searchText,
                                                   filters: filters,
                                                   limit: pageSize,
                                                   offset: page * pageSize)
            prefetchWaveforms()
            // 焦點那一筆不在這一頁就清掉焦點，方向鍵才不會從看不見的位置開始跳。
            // 但 playingSound 刻意不動——換頁不該讓正在播的聲音從播放列上消失，
            // **複選也刻意不動**——選到一半換頁就被清掉的話複選等於沒用。
            if let selectedSoundId, !sounds.contains(where: { $0.rowId == selectedSoundId }) {
                withoutSelectionSync { self.selectedSoundId = nil }
            }
            refreshSelectionDetails()
            refreshCounts()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshCounts() {
        let filters: [SoundFilter] = [.all, .favorites, .needsReview, .unclassified, .analysisFailed]
        var result: [SoundFilter: Int] = [:]
        for filter in filters {
            result[filter] = (try? services.repository.count(filter: filter)) ?? 0
        }
        counts = result
    }

    // MARK: - 預覽

    /// 這次的選取變更是不是鍵盤方向鍵造成的。
    ///
    /// 用旗標而不是參數，是因為選取變更的唯一入口是 RootView 的 onChange；
    /// 在 selectNext 裡直接呼叫一次會跟 onChange 撞成兩次，同一個音效被播兩遍
    /// （聽起來就是「按一下方向鍵，聲音抖一下」）。
    private var selectionCameFromKeyboard = false

    /// 選取變更時呼叫。
    ///
    /// 鍵盤方向鍵一律播放，不受 auto preview 開關影響——用方向鍵掃過清單
    /// 本來就是為了聽。滑鼠點選才看 auto preview：點一下常常只是要看細節。
    func selectionDidChange() {
        let fromKeyboard = selectionCameFromKeyboard
        selectionCameFromKeyboard = false
        // 換了音效之後，上一個的分析結果就不再是在講眼前這一個了。
        lastAnalysisNote = nil

        refreshSelectionDetails()
        if let sound = selectedSound { prioritizeWaveform(for: sound) }
        guard fromKeyboard || autoPreview, let sound = selectedSound else { return }
        startPreview(sound)
    }

    /// 所有播放都走這裡，`playingSound` 才不會跟實際在響的聲音脫節。
    func startPreview(_ sound: Sound) {
        playingSound = sound
        prioritizeWaveform(for: sound)
        preview.play(sound: sound)
    }

    // MARK: - 波形

    /// 目前這一頁缺的波形，在背景逐一補上。換頁時取消上一批。
    private func prefetchWaveforms() {
        waveformTask?.cancel()

        let pending = sounds.filter { sound in
            guard let id = sound.id else { return false }
            return waveforms[id] == nil && sound.status == .ok
        }
        guard !pending.isEmpty else { return }

        let store = services.waveforms
        waveformTask = Task.detached(priority: .background) {
            for sound in pending {
                if Task.isCancelled { return }
                guard let id = sound.id else { continue }
                let url = URL(fileURLWithPath: sound.filePath)
                guard let peaks = store.peaks(soundId: id, url: url) else { continue }
                if Task.isCancelled { return }
                await MainActor.run { self.waveforms[id] = peaks }
            }
        }
    }

    /// 選取的音效優先算，不排在整頁後面。
    private func prioritizeWaveform(for sound: Sound) {
        guard let id = sound.id, waveforms[id] == nil, sound.status == .ok else { return }
        let store = services.waveforms
        let path = sound.filePath
        Task.detached(priority: .userInitiated) {
            guard let peaks = store.peaks(soundId: id, url: URL(fileURLWithPath: path)) else { return }
            await MainActor.run { self.waveforms[id] = peaks }
        }
    }

    /// 用 barSound 而不是 selectedSound：換頁之後選取會是空的，
    /// 但使用者按暫停時要能停掉正在播的那一個。
    func togglePreview() {
        guard let sound = barSound else { return }
        playingSound = sound
        preview.toggle(sound: sound)
    }

    func playSelected() {
        guard let sound = selectedSound else { return }
        startPreview(sound)
    }

    /// 選下一個。走到這一頁最後一筆時自動翻到下一頁的第一筆。
    func selectNext() {
        guard !sounds.isEmpty else { return }
        guard let current = selectedSoundId,
              let index = sounds.firstIndex(where: { $0.rowId == current }) else {
            selectionCameFromKeyboard = true
            selectedSoundId = sounds.first?.rowId
            return
        }

        if index + 1 < sounds.count {
            selectionCameFromKeyboard = true
            selectedSoundId = sounds[index + 1].rowId
        } else if canGoForward {
            nextPage()
            selectionCameFromKeyboard = true
            selectedSoundId = sounds.first?.rowId
        }
    }

    func selectPrevious() {
        guard !sounds.isEmpty else { return }
        guard let current = selectedSoundId,
              let index = sounds.firstIndex(where: { $0.rowId == current }) else {
            selectionCameFromKeyboard = true
            selectedSoundId = sounds.first?.rowId
            return
        }

        if index > 0 {
            selectionCameFromKeyboard = true
            selectedSoundId = sounds[index - 1].rowId
        } else if canGoBack {
            previousPage()
            selectionCameFromKeyboard = true
            selectedSoundId = sounds.last?.rowId
        }
    }

    func refreshSelectionDetails() {
        guard let sound = selectedSound, let id = sound.id else {
            analysis = nil
            suggestions = []
            selectedTags = []
            selectedCategoryPath = nil
            return
        }
        do {
            analysis = try services.repository.latestAnalysis(soundId: id)
            if let analysisId = analysis?.id {
                suggestions = try services.repository.suggestions(analysisId: analysisId)
            } else {
                suggestions = []
            }
            selectedTags = try services.repository.tags(soundId: id)
            if let categoryId = sound.categoryId {
                selectedCategoryPath = try services.repository.category(id: categoryId)?.path
            } else {
                selectedCategoryPath = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 分析單一選取的音效。引擎由 `currentEngine()` 決定，這裡不認得任何特定實作。
    func analyzeSelected() {
        guard let sound = selectedSound, let soundId = sound.id else { return }
        let services = self.services
        Task {
            do {
                let request = OrganizerRequest(
                    soundId: soundId,
                    audioURL: URL(fileURLWithPath: sound.filePath),
                    filename: sound.filename,
                    relativePath: sound.relativePath,
                    duration: sound.duration,
                    fileFormat: sound.fileExtension,
                    sampleRate: sound.sampleRate,
                    channelCount: sound.channelCount,
                    existingCategory: selectedCategoryPath,
                    existingTags: [],
                    hasManualMetadata: sound.categorySource == .manual || sound.displayNameSource == .manual)

                let engine = currentEngine()
                let result = try await engine.analyze(request)
                let mapper = services.mapper
                let engineName = engine.engineName
                let model = engine.modelName
                let modelVersion = engine.modelVersion
                // 用非同步寫入，不要在主執行緒上卡住資料庫（CLAUDE.md §38）
                _ = try await services.database.writer.write { db in
                    try mapper.persist(result: result,
                                       soundId: soundId,
                                       engine: engineName,
                                       model: model,
                                       modelVersion: modelVersion,
                                       in: db)
                }
                reload()
                // 單檔分析原本完全沒有回饋：結果寫進右欄，但如果右欄被收起來，
                // 按下去就像什麼都沒發生。至少要在底列說一句話。
                lastAnalysisNote = Self.note(for: result, engine: engineName)
            } catch {
                // 分析失敗要落庫成 failed，而不是只在畫面上閃一下
                await recordAnalysisFailure(soundId: soundId, reason: error.localizedDescription)
                alert = L10n.tr("分析失敗：%@", String(describing: error.localizedDescription))
            }
        }
    }

    // MARK: - 批次分析（M9）

    /// 分析整個音色庫裡還沒分析過的檔案。
    ///
    /// 併發數刻意壓在核心數以內：本機引擎是 CPU 密集（FFT），開太多執行緒
    /// 只會讓每一個都變慢，還會把 UI 卡住。
    func analyzeLibrary(libraryId: Int64? = nil, includeAnalysed: Bool = false) {
        guard batchTask == nil else { return }
        let services = self.services
        let engine = currentEngine()

        batchTask = Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.batchTask = nil } }

            let pending: [Sound]
            do {
                pending = try services.repository.soundsPendingAnalysis(libraryId: libraryId,
                                                                       includeAnalysed: includeAnalysed)
            } catch {
                await MainActor.run {
                    self.batchProgress = BatchAnalysisProgress()
                    self.alert = L10n.tr("取不到待分析清單：%@", String(describing: error.localizedDescription))
                }
                return
            }

            await MainActor.run {
                self.batchProgress = BatchAnalysisProgress(phase: .running, total: pending.count)
            }
            guard pending.isEmpty == false else {
                await MainActor.run { self.batchProgress.phase = .finished }
                return
            }

            let limit = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1))
            var cancelled = false

            await withTaskGroup(of: BatchOutcome.self) { group in
                var iterator = pending.makeIterator()
                var inFlight = 0

                func submit() {
                    guard let sound = iterator.next(), let soundId = sound.id else { return }
                    inFlight += 1
                    group.addTask {
                        await LibraryStore.analyzeOne(sound: sound,
                                                      soundId: soundId,
                                                      engine: engine,
                                                      services: services)
                    }
                }

                for _ in 0..<limit { submit() }

                while inFlight > 0, let outcome = await group.next() {
                    inFlight -= 1
                    await MainActor.run {
                        self.batchProgress.completed += 1
                        self.batchProgress.currentName = outcome.name
                        if outcome.failed { self.batchProgress.failed += 1 }
                        if outcome.needsReview { self.batchProgress.needsReview += 1 }
                    }
                    if Task.isCancelled {
                        cancelled = true
                        break
                    }
                    submit()
                }
                group.cancelAll()
            }

            await MainActor.run {
                self.batchProgress.phase = cancelled || Task.isCancelled ? .cancelled : .finished
                self.batchProgress.currentName = ""
                self.reload()
            }
        }
    }

    func cancelBatchAnalysis() {
        batchTask?.cancel()
    }

    private struct BatchOutcome {
        var name: String
        var failed: Bool
        var needsReview: Bool
    }

    /// 單一檔案的分析 + 落庫。失敗一律寫進資料庫，不讓它只在畫面上閃一下。
    private static func analyzeOne(sound: Sound,
                                   soundId: Int64,
                                   engine: OrganizerEngine,
                                   services: AppEnvironment.Services) async -> BatchOutcome {
        let request = OrganizerRequest(
            soundId: soundId,
            audioURL: URL(fileURLWithPath: sound.filePath),
            filename: sound.filename,
            relativePath: sound.relativePath,
            duration: sound.duration,
            fileFormat: sound.fileExtension,
            sampleRate: sound.sampleRate,
            channelCount: sound.channelCount,
            existingCategory: nil,
            existingTags: [],
            hasManualMetadata: sound.categorySource == .manual || sound.displayNameSource == .manual)

        let result: OrganizerResult
        do {
            result = try await engine.analyze(request)
        } catch {
            result = .failure(reason: error.localizedDescription)
        }

        let mapper = services.mapper
        let engineName = engine.engineName
        let model = engine.modelName
        let modelVersion = engine.modelVersion
        do {
            _ = try await services.database.writer.write { db in
                try mapper.persist(result: result,
                                   soundId: soundId,
                                   engine: engineName,
                                   model: model,
                                   modelVersion: modelVersion,
                                   in: db)
            }
        } catch {
            return BatchOutcome(name: sound.filename, failed: true, needsReview: true)
        }

        return BatchOutcome(name: sound.filename,
                            failed: result.status == .failed,
                            needsReview: ConfidencePolicy.default.effectiveNeedsReview(for: result))
    }

    /// 單檔分析的結果摘要。nil 代表沒有剛跑過的分析。
    @Published var lastAnalysisNote: String?

    private static func note(for result: OrganizerResult, engine: String) -> String {
        switch result.status {
        case .failed:
            return L10n.tr("分析失敗：讀不到音訊內容")
        case .unknown:
            return L10n.tr("%@：路徑沒有可用線索，維持未分類", String(describing: engine))
        default:
            var parts = ["\(engine)：\(result.category)"]
            if let style = result.style { parts.append(L10n.tr("風格 %@", String(describing: style))) }
            parts.append(String(format: L10n.tr("信心 %.0f%%"), result.confidence * 100))
            if result.needsReview { parts.append(L10n.tr("待複查")) }
            return parts.joined(separator: L10n.tr("separator.list"))
        }
    }

    private func recordAnalysisFailure(soundId: Int64, reason: String) async {
        let mapper = services.mapper
        let engineName = currentEngine().engineName
        _ = try? await services.database.writer.write { db in
            try mapper.persist(result: OrganizerResult.failure(reason: reason),
                               soundId: soundId,
                               engine: engineName,
                               in: db)
        }
        reload()
    }

    // MARK: - 批次審核（M11）

    @Published var batchReviewPreview: ReviewService.Preview?
    @Published var reviewThreshold: Double = ConfidencePolicy.default.strongMin
    @Published var reviewIncludesTags: Bool = true

    /// 算一次預覽。**執行前一定要先給使用者看這個。**
    func refreshBatchReviewPreview() {
        batchReviewPreview = try? services.review.preview(minConfidence: reviewThreshold,
                                                          includeTags: reviewIncludesTags)
    }

    @Published private(set) var batchWriteInProgress = false

    func applyBatchReview() {
        guard !batchWriteInProgress else { return }
        batchWriteInProgress = true
        let services = self.services
        let threshold = reviewThreshold
        let includeTags = reviewIncludesTags
        Task { [weak self] in
            guard let self else { return }
            defer { self.batchWriteInProgress = false }
            guard await self.backupBefore(.batchAccept) else { return }
            do {
                let applied = try await Task.detached(priority: .utility) {
                    try services.review.acceptAll(minConfidence: threshold, includeTags: includeTags)
                }.value
                self.lastAnalysisNote = L10n.tr("已套用 %@ 筆分類、%@ 筆標籤", String(describing: applied.categories), String(describing: applied.tags))
                self.batchReviewPreview = nil
                self.reloadLibraries()
                self.reload()
            } catch { self.alert = L10n.tr("批次接受失敗：%@", String(describing: error.localizedDescription)) }
        }
    }

    // MARK: - 依分類瀏覽（M41）

    /// 側欄分類區。已確定與建議分開計數，頂層含子分類。
    @Published private(set) var categoryTree: [CategoryNode] = []
    /// 展開的頂層分類。預設全部收合：十幾個頂層攤開就把音色庫擠出視線外。
    @Published var expandedCategories: Set<String> = []

    func refreshCategoryTree() {
        categoryTree = CategoryTree.build(from: (try? services.repository.categoryCounts()) ?? [])
    }

    func toggleCategory(_ path: String) {
        if expandedCategories.contains(path) {
            expandedCategories.remove(path)
        } else {
            expandedCategories.insert(path)
        }
    }

    /// 目前在看的分類。不是分類檢視就是 nil。
    var currentCategoryPath: String? {
        if case .category(let path) = filter { return path }
        return nil
    }

    /// 目前分類在側欄樹裡的節點（數量含子分類）。
    var currentCategoryNode: CategoryNode? {
        guard let path = currentCategoryPath else { return nil }
        for top in categoryTree {
            if top.path == path { return top }
            if let child = top.children.first(where: { $0.path == path }) { return child }
        }
        return nil
    }

    /// 「接受這一類的建議」的門檻選項。跟批次接受同一組定義，再加一個「全部」。
    static let categoryAcceptThresholds: [(label: String, value: Double)] = [
        (L10n.tr("只接受兩條證據一致的"), ConfidencePolicy.default.strongMin),
        (L10n.tr("也接受路徑證據強的"), ConfidencePolicy.default.moderateMin),
        (L10n.tr("連弱證據也接受"), ConfidencePolicy.default.weakMin),
        (L10n.tr("全部接受（包括很不確定的）"), 0),
    ]
    @Published var categoryAcceptThreshold: Double = ConfidencePolicy.default.strongMin
    /// 每個門檻會套用幾筆。**執行前一定要先給使用者看這個。**
    @Published private(set) var categoryAcceptCounts: [Double: Int] = [:]

    func refreshCategoryAcceptPreview() {
        guard let path = currentCategoryPath else { categoryAcceptCounts = [:]; return }
        var counts: [Double: Int] = [:]
        for option in Self.categoryAcceptThresholds {
            counts[option.value] = (try? services.review.categoryPreview(path: path,
                                                                      minConfidence: option.value)) ?? 0
        }
        categoryAcceptCounts = counts
    }

    /// 接受目前分類底下的分類建議。只動分類，不動標籤；已確定的不會被改（D-042）。
    func acceptCurrentCategory() {
        guard let path = currentCategoryPath, !batchWriteInProgress else { return }
        batchWriteInProgress = true
        let services = self.services
        let threshold = categoryAcceptThreshold
        Task { [weak self] in
            guard let self else { return }
            defer { self.batchWriteInProgress = false }
            guard await self.backupBefore(.batchAccept) else { return }
            do {
                let applied = try await Task.detached(priority: .utility) {
                    try services.review.acceptCategory(path: path, minConfidence: threshold)
                }.value
                self.lastAnalysisNote = L10n.tr("已接受 %@ 筆「%@」的分類建議", String(describing: applied), String(describing: path))
                self.categoryAcceptCounts = [:]
                self.reloadLibraries()
                self.reload()
            } catch { self.alert = L10n.tr("接受失敗：%@", String(describing: error.localizedDescription)) }
        }
    }

    // MARK: - 單筆審核

    /// 目前選取的音效有沒有待處理的建議。
    var pendingSuggestions: [OrganizerSuggestion] {
        suggestions.filter { $0.status == .suggested }
    }

    var pendingCategorySuggestion: OrganizerSuggestion? {
        pendingSuggestions.first { $0.field == .category }
    }

    /// 接受選取音效的所有建議，然後跳到下一筆。
    ///
    /// 審核是一個「一直往下」的動作——每按一次還要自己按方向鍵，
    /// 一萬多筆就不可能做完。
    func acceptSelectedAndAdvance() {
        let pending = pendingSuggestions
        guard pending.isEmpty == false else { advanceForReview(); return }
        for suggestion in pending {
            guard let id = suggestion.id else { continue }
            try? services.metadata.accept(suggestionId: id)
        }
        clearNeedsReviewForSelection()
        advanceForReview()
    }

    /// 拒絕選取音效的所有建議，然後跳到下一筆。
    func rejectSelectedAndAdvance() {
        for suggestion in pendingSuggestions {
            guard let id = suggestion.id else { continue }
            try? services.metadata.reject(suggestionId: id)
        }
        clearNeedsReviewForSelection()
        advanceForReview()
    }

    /// 人已經看過了，就不該再留在 Needs Review 裡。
    private func clearNeedsReviewForSelection() {
        guard let id = selectedSoundId else { return }
        try? services.database.writer.write { db in
            try db.execute(sql: "UPDATE sounds SET needs_review = 0 WHERE id = ?", arguments: [id])
        }
    }

    private func advanceForReview() {
        // 在 Needs Review 檢視下，處理過的那一筆會從清單消失，
        // 所以 reload 之後同一個位置本來就是下一筆，不需要再往下移。
        let wasIndex = sounds.firstIndex { $0.rowId == selectedSoundId }
        reload()
        refreshCountsAfterReview()
        if let index = wasIndex {
            if index < sounds.count {
                selectionCameFromKeyboard = true
                selectedSoundId = sounds[index].rowId
            } else if sounds.isEmpty == false {
                selectionCameFromKeyboard = true
                selectedSoundId = sounds[min(index, sounds.count - 1)].rowId
            } else if canGoForward {
                nextPage()
                selectionCameFromKeyboard = true
                selectedSoundId = sounds.first?.rowId
            }
        }
    }

    private func refreshCountsAfterReview() {
        reloadLibraries()
    }

    func accept(_ suggestion: OrganizerSuggestion, force: Bool = false) {
        guard let id = suggestion.id else { return }
        do {
            try services.metadata.accept(suggestionId: id, force: force)
            reload()
            refreshCategoryTree()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reject(_ suggestion: OrganizerSuggestion) {
        guard let id = suggestion.id else { return }
        do {
            try services.metadata.reject(suggestionId: id)
            reload()
            refreshCategoryTree()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - 人工編輯（M6）

    /// taxonomy 的完整分類路徑，給 Inspector 的分層選單用。
    var categoryPaths: [String] {
        (try? services.repository.categoryPaths()) ?? []
    }

    /// canonical 標籤詞彙，輸入時給建議。
    var tagVocabulary: [String] {
        services.vocabulary.canonical
    }

    func setCategory(_ path: String?) {
        guard let id = selectedSound?.id else { return }
        do {
            try services.metadata.setCategory(path: path, soundId: id, source: .manual)
            reload()
            refreshCategoryTree()
        } catch {
            alert = L10n.tr("無法設定分類：%@", String(describing: error.localizedDescription))
        }
    }

    func setSubcategory(_ value: String) {
        guard let id = selectedSound?.id else { return }
        do {
            try services.metadata.setSubcategory(value.isEmpty ? nil : value, soundId: id, source: .manual)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addTag(_ raw: String) {
        guard let id = selectedSound?.id else { return }
        do {
            try services.metadata.addTag(raw, soundId: id)
            refreshSelectionDetails()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removeTag(_ tag: SoundTagView) {
        guard let soundId = selectedSound?.id else { return }
        do {
            try services.metadata.removeTag(tagId: tag.id, soundId: soundId)
            refreshSelectionDetails()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setNotes(_ value: String) {
        guard let id = selectedSound?.id else { return }
        do {
            try services.metadata.setNotes(value.isEmpty ? nil : value, soundId: id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - 實體檔案（M17，全部由使用者明確觸發）

    func revealInFinder(_ sound: Sound) {
        FileActions.revealInFinder(path: sound.filePath)
    }

    func copyPath(_ sound: Sound) {
        FileActions.copyPath(sound.filePath)
    }

    /// 拖曳到 Logic Pro：提供原始檔案 URL，不做副本。
    // MARK: - 虛擬資料夾的操作

    func reloadCollections() {
        collections = (try? services.collections.all()) ?? []
        // 上次選的分頁被刪掉了（可能是在別的地方刪的）就回到 LIBRARY。
        if let id = selectedCollectionId, collections.contains(where: { $0.id == id }) == false {
            selectCollection(nil)
        }
    }

    /// 切換分頁。nil = LIBRARY。
    func selectCollection(_ id: Int64?) {
        selectedCollectionId = id
        if let id {
            filter = .collection(id)
        } else if case .collection = filter {
            filter = .all
        }
        UserDefaults.standard.set(id.map(String.init) ?? "", forKey: CollectionKey.selected)
    }

    func createCollection() {
        do {
            let collection = try services.collections.create(name: L10n.tr("新分頁"))
            reloadCollections()
            if let id = collection.id {
                selectCollection(id)
                // 建立後直接進入改名狀態：沒有人想留著一個叫「新分頁」的分頁。
                renamingCollectionId = id
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func renameCollection(id: Int64, to name: String) {
        do {
            try services.collections.rename(id: id, to: name)
            reloadCollections()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 刪除分頁。**音效與檔案完全不受影響。**
    func deleteCollection(id: Int64) {
        do {
            try services.collections.delete(id: id)
            if selectedCollectionId == id { selectCollection(nil) }
            reloadCollections()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func moveCollection(from source: IndexSet, to destination: Int) {
        var ordered = collections
        ordered.move(fromOffsets: source, toOffset: destination)
        do {
            try services.collections.reorder(ids: ordered.compactMap(\.id))
            reloadCollections()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 把**目前這個檢視的全部**加進分頁，不是只有當前這一頁。
    @discardableResult
    func addCurrentViewToCollection(_ collectionId: Int64) -> Int {
        do {
            let ids = try services.repository.allIds(filter: filter,
                                                     search: searchText,
                                                     filters: filters)
            guard ids.isEmpty == false else { return 0 }
            let added = try services.collections.add(soundIds: ids, to: collectionId)
            reloadCollections()
            if selectedCollectionId == collectionId { reload() }
            lastAnalysisNote = L10n.tr("已加入 %@ 筆到「%@」", String(describing: added), String(describing: collectionName(collectionId)))
            return added
        } catch {
            lastError = error.localizedDescription
            return 0
        }
    }

    /// 把目前檢視加到一個新分頁裡。
    func addCurrentViewToNewCollection() {
        do {
            let name = filter.title
            let collection = try services.collections.create(name: name)
            reloadCollections()
            guard let id = collection.id else { return }
            addCurrentViewToCollection(id)
            selectCollection(id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - 命名預覽（M31）

    /// 目前這份命名計畫。**只是一份清單**——不寫資料庫、不碰磁碟。
    @Published private(set) var namingPlan: NamingPlan?
    @Published private(set) var namingPlanIsBuilding = false
    /// 計畫對應的原始列。執行時要靠它把 sound id 對回檔案路徑與庫根目錄。
    private var namingRows: [NamingRow] = []

    // MARK: - 整理執行（M32）

    @Published private(set) var organizeProgress = OrganizeProgress()
    @Published private(set) var organizeBatches: [OrganizeBatch] = []
    private var organizeFlag: OrganizeCancellation?

    private var journal: OrganizeJournal { OrganizeJournal(database: services.database) }

    /// 這次會建立幾個連結，以及建在哪裡。按下去之前要先講清楚。
    var organizeGroups: [OrganizeRun.Group] {
        guard let namingPlan else { return [] }
        return OrganizeRun.groups(from: namingPlan, rows: namingRows)
    }

    func refreshOrganizeBatches() {
        organizeBatches = (try? journal.batches()) ?? []
    }

    /// 執行整理。**這是整個 app 唯一會在磁碟上建立東西的地方。**
    ///
    /// 原檔不動、不覆蓋既有檔案、每一筆都記進 journal 以便撤銷。
    func runOrganize(scope: String) {
        let groups = organizeGroups
        guard groups.isEmpty == false, organizeProgress.isRunning == false else { return }
        guard !batchWriteInProgress, !undoInProgress else { return }
        batchWriteInProgress = true
        let numbers = Dictionary(uniqueKeysWithValues: (namingPlan?.entries ?? []).map { ($0.soundId, $0.number) })
        Task { [weak self] in
            guard let self else { return }
            defer { self.batchWriteInProgress = false }
            guard await self.backupBefore(.organize) else { return }
            self.performOrganize(groups: groups, scope: scope, numbers: numbers)
        }
    }

    private func performOrganize(groups: [OrganizeRun.Group], scope: String, numbers: [Int64: Int]) {
        let flag = OrganizeCancellation()
        organizeFlag = flag
        organizeProgress = OrganizeProgress(phase: .running,
                                            total: OrganizeRun.linkCount(groups))

        let journal = self.journal
        let totals = OrganizeTotals()
        // sound id → 這次分到的號碼。成功建立連結之後要寫回資料庫凍結。
        let database = services.database
        Task.detached(priority: .userInitiated) { [weak self] in
            var cancelled = false
            for group in groups {
                let outcome = OrganizeExecutor.run(
                    group.jobs,
                    root: group.root,
                    scope: scope,
                    journal: journal,
                    shouldContinue: { flag.isCancelled == false },
                    onProgress: { step in
                        // 每一組的進度是分開算的，這裡跟已完成的組累加成整體。
                        let done = totals.snapshot()
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.organizeProgress.completed = done.linked + step.completed
                            self.organizeProgress.skipped = done.skipped + step.skipped
                            self.organizeProgress.failed = done.failed + step.failed
                            self.organizeProgress.currentName = step.currentName
                        }
                    })
                totals.add(linked: outcome.linked, skipped: outcome.skipped, failed: outcome.failed)
                // 編號一定要凍結，否則之後在中間插進新檔案，
                // 後面每一個的號碼都會位移，整棵樹跟著改名。
                LibraryStore.freezeOrganizedNames(outcome.linkedItems,
                                                  numbers: numbers,
                                                  in: database)
                if outcome.cancelled { cancelled = true; break }
            }

            let final = totals.snapshot()
            let wasCancelled = cancelled
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.organizeProgress.phase = wasCancelled ? .cancelled : .finished
                self.organizeProgress.completed = final.linked
                self.organizeProgress.skipped = final.skipped
                self.organizeProgress.failed = final.failed
                self.organizeFlag = nil
                self.refreshOrganizeBatches()
                self.lastAnalysisNote = self.organizeProgress.summary
            }
        }
    }

    func cancelOrganize() { organizeFlag?.cancel() }

    /// 把這次用的編號與名字寫回 `sounds`，凍結起來。
    ///
    /// **原始的 `filename` 與 `relative_path` 永遠不覆寫**（dev-plan §6）：
    /// 哪天懷疑某個 descriptor 抽錯了，要有東西可以比對。
    ///
    /// 資料夾一起存，因為號碼只在那個資料夾裡有效——分類改過之後
    /// 舊號碼就不適用，那時要在新資料夾重新拿一個。
    nonisolated static func freezeOrganizedNames(_ items: [OrganizeLinked],
                                                 numbers: [Int64: Int],
                                                 in database: AppDatabase) {
        guard items.isEmpty == false else { return }
        try? database.writer.write { db in
            for item in items {
                let folder = (item.destination as NSString).deletingLastPathComponent
                let name = (item.destination as NSString).lastPathComponent
                try db.execute(sql: """
                    UPDATE sounds
                       SET organized_number = ?, organized_folder = ?,
                           organized_name = ?, organized_at = ?
                     WHERE id = ?
                    """, arguments: [numbers[item.soundId], folder, name, Date(), item.soundId])
            }
        }
    }

    /// 撤銷一個批次。只刪這個批次建立過的連結，原檔一個位元組都不會變。
    @Published private(set) var undoInProgress = false

    func undoOrganize(batchId: Int64) {
        guard !organizeProgress.isRunning, !undoInProgress, !batchWriteInProgress else { return }
        undoInProgress = true
        let journal = self.journal
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                OrganizeExecutor.undo(batchId: batchId, journal: journal)
            }.value
            guard let self else { return }
            self.undoInProgress = false
            self.refreshOrganizeBatches()
            self.lastAnalysisNote = result.summary
        }
    }

    /// 對**目前這個檢視**算一份命名計畫。
    ///
    /// 用目前的篩選而不是整個庫，是因為一次看四萬筆沒有意義：
    /// 要對的通常是「這個 pack 我調完規則之後長什麼樣」。
    func buildNamingPlan() {
        guard namingPlanIsBuilding == false else { return }
        namingPlanIsBuilding = true
        let services = self.services
        let filter = self.filter
        let search = self.searchText
        let filters = self.filters
        Task.detached(priority: .userInitiated) {
            let built: (plan: NamingPlan, rows: [NamingRow])?
            do {
                let rows = try services.repository.namingRows(filter: filter,
                                                              search: search,
                                                              filters: filters)
                built = (NamingPlanBuilder.build(
                    rows: rows,
                    roleTerms: NamingConventionDetector.roleTerms(from: PathEvidenceReader.rules),
                    styleTerms: NamingConventionDetector.styleTerms(from: services.styles)), rows)
            } catch {
                built = nil
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.namingPlan = built?.plan
                self.namingRows = built?.rows ?? []
                self.namingPlanIsBuilding = false
                if built == nil { self.lastError = L10n.tr("命名預覽失敗") }
            }
        }
    }

    func clearNamingPlan() {
        namingPlan = nil
        namingRows = []
        organizeProgress = OrganizeProgress()
    }

    /// 目前這個檢視的名字，寫進批次紀錄，撤銷清單才認得出來。
    var currentScopeName: String {
        if let id = selectedCollectionId,
           let collection = collections.first(where: { $0.id == id }) {
            return L10n.tr("分頁：%@", String(describing: collection.name))
        }
        if searchText.isEmpty == false { return L10n.tr("搜尋：%@", String(describing: searchText)) }
        if case .category(let path) = filter { return L10n.tr("分類：%@", String(describing: path)) }
        return L10n.tr("檢視：全部")
    }

    /// 匯出 CSV 供人離線比對。這是 M31 唯一會寫出來的東西，
    /// 而且寫在使用者選的位置，不在音色庫裡。
    func exportNamingPlan(to url: URL) {
        guard let namingPlan else { return }
        do {
            try NamingPlanner.csv(namingPlan).write(to: url, atomically: true, encoding: .utf8)
            lastAnalysisNote = L10n.tr("已匯出 %@ 筆命名對照", String(describing: namingPlan.total))
        } catch {
            alert = L10n.tr("匯出失敗：%@", String(describing: error.localizedDescription))
        }
    }

    // MARK: - 依分類自動建立分頁

    @Published private(set) var autoFillCandidates: [CollectionStore.AutoFillCandidate] = []
    @Published var autoFillMinimum: Int = 20

    func refreshAutoFillCandidates() {
        autoFillCandidates = (try? services.collections.autoFillCandidates(minCount: autoFillMinimum)) ?? []
    }

    func applyAutoFill() {
        do {
            let result = try services.collections.autoFillByCategory(minCount: autoFillMinimum)
            reloadCollections()
            reload()
            lastAnalysisNote = L10n.tr("建立了 %@ 個分頁，填入 %@ 筆", String(describing: result.collectionsCreated), String(describing: result.soundsAdded))
        } catch {
            alert = L10n.tr("自動建立分頁失敗：%@", String(describing: error.localizedDescription))
        }
    }

    /// 人工設定風格。人工值的優先權高於任何自動推得的值。
    /// 人工設定材質。人工值的優先權高於任何自動讀到的值。
    func setTexture(_ value: String?, for soundId: Int64) {
        do {
            try services.metadata.setTexture(value, soundId: soundId)
            reloadLibraries()
            reload()
        } catch { lastError = error.localizedDescription }
    }

    /// 材質白名單，給 Inspector 的選單用。
    var availableTextures: [String] { services.textures.textures }

    // MARK: - 備份

    @Published private(set) var backups: [DatabaseBackup.Entry] = []

    var backupFolder: URL? {
        services.database.path.map { DatabaseBackup.folder(beside: $0) }
    }

    func refreshBackups() {
        backups = backupFolder.map { DatabaseBackup.list(in: $0) } ?? []
    }

    /// 批次修改必須先取得可恢復的備份；失敗時不開始寫入。
    private func backupBefore(_ trigger: DatabaseBackup.Trigger) async -> Bool {
        let database = services.database
        do {
            _ = try await Task.detached(priority: .utility) {
                try DatabaseBackup.required(for: database, trigger: trigger)
            }.value
            refreshBackups()
            return true
        } catch {
            lastError = L10n.tr("%@前的自動備份失敗，已停止批次動作", String(describing: L10n.tr(trigger.rawValue)))
            return false
        }
    }

    /// 手動備份到使用者指定的位置。放在外接碟上才擋得住系統碟壞掉。
    func exportBackup(to url: URL) {
        do {
            try DatabaseBackup.make(from: services.database, to: url)
            lastAnalysisNote = L10n.tr("已備份到 %@", String(describing: url.lastPathComponent))
        } catch {
            alert = L10n.tr("備份失敗：%@", String(describing: error.localizedDescription))
        }
    }

    @Published private(set) var rereadProgress: (done: Int, total: Int)?

    /// 只讀路徑重算全庫。**一個音檔都不開。**
    ///
    /// 風格、材質、字面 BPM、調性與 loop 線索全部重讀一遍。
    /// 分類建議必須有音訊量測佐證，這條便宜路徑永遠不碰（D-040）。
    func rereadPaths() {
        guard rereadProgress == nil else { return }
        guard !batchWriteInProgress else { return }
        batchWriteInProgress = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.batchWriteInProgress = false }
            guard await self.backupBefore(.pathReread) else { return }
            self.performRereadPaths()
        }
    }

    private func performRereadPaths() {
        rereadProgress = (0, 0)
        let services = self.services
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = PathRereadService.run(
                database: services.database,
                taxonomy: services.taxonomy,
                vocabulary: services.vocabulary,
                styles: services.styles,
                textures: services.textures,
                onProgress: { done, total in
                    Task { @MainActor [weak self] in self?.rereadProgress = (done, total) }
                })
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.rereadProgress = nil
                self.reloadLibraries()
                self.reload()
                self.lastAnalysisNote = result.summary
            }
        }
    }

    /// 用既有的路徑把材質補上。**不碰音檔**，所以四萬多筆只是一次掃描。
    func backfillTextures() {
        let database = services.database
        let vocabulary = services.textures
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = TextureBackfill.run(database: database, vocabulary: vocabulary)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.reloadLibraries()
                self.reload()
                self.lastAnalysisNote = result.summary
            }
        }
    }

    func setStyle(_ value: String?, for soundId: Int64) {
        do {
            try services.metadata.setStyle(value, soundId: soundId)
            reloadLibraries()
            reload()
        } catch { lastError = error.localizedDescription }
    }

    /// 風格白名單，給 Inspector 的選單用。
    var styleOptions: [String] { services.styles.styles }

    func collectionName(_ id: Int64) -> String {
        collections.first { $0.id == id }?.name ?? L10n.tr("分頁")
    }

    private func restoreSelectedCollection() {
        guard let raw = UserDefaults.standard.string(forKey: CollectionKey.selected),
              raw.isEmpty == false, let id = Int64(raw),
              collections.contains(where: { $0.id == id }) else { return }
        selectCollection(id)
    }

    /// 把拖進分頁的檔案 URL 換回 sound id。
    ///
    /// 這樣就不需要第二套拖曳語意——音檔那一列已經有 onDrag 提供檔案 URL 給
    /// Logic 與 Finder，分頁只是另一個 drop target。一個來源、兩個去處。
    /// 從 Finder 拖進來、不在音色庫裡的檔案會回 nil，直接忽略。
    func soundId(forDroppedFile url: URL) -> Int64? {
        let path = url.resolvingSymlinksInPath().path
        return try? services.database.writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM sounds WHERE file_path = ? LIMIT 1",
                               arguments: [path])
        }
    }

    /// 拖曳帶過來的 id，複選時展開成整批。
    ///
    /// macOS 的 `onDrag` 一次只給得出**一個**檔案 URL，所以拖十個檔案進分頁時，
    /// 放下的那一端只會看到一個。判斷的依據是「被拖的那一列在不在選取裡」：
    /// 在，就是在拖整批；不在，就只是拖那一個（選取不動，Finder 也是這樣）。
    ///
    /// 不改成自訂的拖曳格式，是因為同一個 onDrag 也要餵 Logic 與 Finder——
    /// 它們只認檔案 URL。一個來源、兩個去處的設計不該為了這件事拆成兩套。
    func droppedIds(_ urls: [URL]) -> [Int64] {
        let dropped = urls.compactMap { soundId(forDroppedFile: $0) }
        guard dropped.isEmpty == false else { return [] }
        guard selection.isMultiple, dropped.contains(where: { selection.contains($0) }) else {
            return dropped
        }
        // 從 Finder 一起拖進來、不在選取裡的檔案也要留著。
        var ids = selection.sortedIds
        ids.append(contentsOf: dropped.filter { selection.contains($0) == false })
        return ids
    }

    /// 放下檔案的入口。回傳「有沒有認得這些檔案」，不是「加了幾筆」。
    ///
    /// 這個分別很重要：全部都已經在分頁裡時加入筆數是 0，但那是**成功**——
    /// 拿 0 當失敗會讓 SwiftUI 播退回動畫，使用者看到的是「拖曳失敗」，
    /// 而他要的結果其實已經達成了。
    @discardableResult
    func acceptDrop(_ urls: [URL], into collectionId: Int64) -> Bool {
        let ids = droppedIds(urls)
        guard ids.isEmpty == false else { return false }
        do {
            let added = try services.collections.add(soundIds: ids, to: collectionId)
            reloadCollections()
            if selectedCollectionId == collectionId { reload() }
            lastAnalysisNote = added > 0 ? L10n.tr("加入 %@ 個", String(describing: added)) : L10n.tr("都已經在這個分頁裡了")
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// 把檔案加進分頁。回傳實際加入的筆數（已經在裡面的不重複算）。
    @discardableResult
    func addToCollection(_ collectionId: Int64, urls: [URL]) -> Int {
        let ids = droppedIds(urls)
        guard ids.isEmpty == false else { return 0 }
        do {
            let added = try services.collections.add(soundIds: ids, to: collectionId)
            reloadCollections()
            if selectedCollectionId == collectionId { reload() }
            return added
        } catch {
            lastError = error.localizedDescription
            return 0
        }
    }

    @discardableResult
    func addToCollection(_ collectionId: Int64, soundIds: [Int64]) -> Int {
        do {
            let added = try services.collections.add(soundIds: soundIds, to: collectionId)
            reloadCollections()
            if selectedCollectionId == collectionId { reload() }
            return added
        } catch {
            lastError = error.localizedDescription
            return 0
        }
    }

    // MARK: - 複選

    /// 一般點擊：只選這一列。
    func selectOnly(_ id: Int64) {
        selectedSoundId = id
    }

    /// ⌘ 點擊：單獨加減一列。焦點跟著移到這一列。
    func toggleSelection(_ id: Int64) {
        selection.toggle(id)
        withoutSelectionSync { selectedSoundId = id }
        selectionDidChange()
    }

    /// ⇧ 點擊：從錨點選到這一列。
    func extendSelection(to id: Int64) {
        selection.extend(to: id, in: pageIds)
        withoutSelectionSync { selectedSoundId = id }
        selectionDidChange()
    }

    /// ⌘A：全選當前頁。跨頁的既有選取保留。
    func selectAllOnPage() {
        selection.selectAll(pageIds)
        if selectedSoundId == nil, let first = pageIds.first {
            withoutSelectionSync { selectedSoundId = first }
            selectionDidChange()
        }
    }

    /// ⇧ 方向鍵：把選取往上／往下擴一列。
    ///
    /// **停在這一頁的邊界，不自動翻頁。** 範圍是從錨點算的，
    /// 翻頁之後錨點就不在畫面上了，再擴下去人看不出自己選到哪裡。
    func extendSelectionByOneRow(forward: Bool) {
        let ids = pageIds
        guard ids.isEmpty == false else { return }
        guard let current = selectedSoundId, let index = ids.firstIndex(of: current) else {
            selectOnly(ids[forward ? 0 : ids.count - 1])
            selectionDidChange()
            return
        }
        let next = forward ? index + 1 : index - 1
        guard ids.indices.contains(next) else { return }
        extendSelection(to: ids[next])
    }

    func clearSelection() {
        selection.clear()
        withoutSelectionSync { selectedSoundId = nil }
        selectionDidChange()
    }

    /// 批次動作的對象。
    ///
    /// 複選時是整批，沒有複選時是焦點那一列——所以右鍵選單不必分兩套寫法。
    var actionTargets: [Int64] {
        if selection.isMultiple { return selection.sortedIds }
        if let selectedSoundId { return [selectedSoundId] }
        return []
    }

    /// 把選取的整批加進分頁。回傳實際新增的筆數（已經在裡面的不重複加）。
    @discardableResult
    func addSelectionToCollection(_ collectionId: Int64) -> Int {
        let ids = actionTargets
        guard ids.isEmpty == false else { return 0 }
        return addToCollection(collectionId, soundIds: ids)
    }

    /// 從**目前正在看的**分頁移出選取的整批。**不是刪除檔案。**
    func removeSelectionFromCurrentCollection() {
        guard let collectionId = selectedCollectionId else { return }
        let ids = actionTargets
        guard ids.isEmpty == false else { return }
        removeFromCollection(collectionId, soundIds: ids)
        // 移出去的列已經不在這個分頁的清單裡了，選取要跟著收斂，
        // 否則下一個批次動作會對著看不見的列動作。
        selection.prune(keeping: Set(pageIds))
    }

    /// 從分頁移除。**不是刪除檔案。**
    func removeFromCollection(_ collectionId: Int64, soundIds: [Int64]) {
        do {
            try services.collections.remove(soundIds: soundIds, from: collectionId)
            reloadCollections()
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 分頁內重排：把 `movingIds` 搬到 `targetId` 前面。
    ///
    /// 用「搬到某一筆前面」而不是「從第幾列搬到第幾列」，是因為索引會被翻頁弄亂——
    /// 當前頁的第 3 列在整個分頁裡可能是第 63 筆。用 id 當錨點就沒有這個問題，
    /// 而且寫回的永遠是**整個分頁**的順序，其他頁的 sort_order 不會錯位。
    ///
    /// 還不在這個分頁裡的音檔會先被加進來，再放到指定位置。
    func moveInCollection(soundIds movingIds: [Int64], before targetId: Int64) {
        guard let collectionId = selectedCollectionId else { return }
        let movingIds = movingIds.filter { $0 != targetId }
        guard movingIds.isEmpty == false else { return }
        do {
            let store = services.collections
            let existing = Set(try store.soundIds(in: collectionId))
            let newcomers = movingIds.filter { existing.contains($0) == false }
            if newcomers.isEmpty == false {
                try store.add(soundIds: newcomers, to: collectionId)
            }

            let all = try store.soundIds(in: collectionId)
            guard let reordered = CollectionStore.reordering(all: all,
                                                             moving: movingIds,
                                                             before: targetId) else { return }
            try store.reorderSounds(reordered, in: collectionId)
            reloadCollections()
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 把拖進來的檔案放到分頁裡的指定位置。回傳有沒有真的動到東西。
    @discardableResult
    func dropInCollection(urls: [URL], before targetId: Int64) -> Bool {
        let ids = droppedIds(urls)
        guard ids.isEmpty == false else { return false }
        moveInCollection(soundIds: ids, before: targetId)
        return true
    }

    func dragItem(for sound: Sound) -> NSItemProvider {
        FileActions.dragItem(path: FileActions.dragPath(for: sound))
    }

    func setDisplayName(_ value: String) {
        guard let id = selectedSound?.id else { return }
        do {
            try services.metadata.setDisplayName(value.isEmpty ? nil : value, soundId: id, source: .manual)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggleFavorite() {
        guard let sound = selectedSound, let id = sound.id else { return }
        do {
            try services.metadata.setFavorite(!sound.favorite, soundId: id)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setRating(_ value: Int) {
        guard let id = selectedSound?.id else { return }
        do {
            try services.metadata.setRating(value, soundId: id)
            reload()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
