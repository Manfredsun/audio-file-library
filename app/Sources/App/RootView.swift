import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Group {
            if let services = environment.services {
                MainWindow(services: services)
            } else {
                StartupErrorView(message: environment.startupError ?? L10n.tr("未知的啟動錯誤"))
            }
        }
        .preferredColorScheme(preferences.appearance.colorScheme)
        .tint(DS.Palette.asagi)
    }
}

struct StartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: DS.Ma.block) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DS.Palette.kihada)
            Text(L10n.tr("無法啟動"))
                .font(DS.TypeScale.display)
                .foregroundStyle(DS.Palette.textPrimary)
            Text(message)
                .font(DS.TypeScale.rowMeta)
                .foregroundStyle(DS.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 360)
        }
        .padding(DS.Ma.chapter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Palette.sumi)
    }
}

struct MainWindow: View {
    @Environment(\.openSettings) private var openSettings
    @StateObject private var store: LibraryStore
    @State private var showingOrganizerSettings = false
    @State private var showingBatchReview = false
    @State private var showingAutoFill = false
    @State private var showingNamingPreview = false
    @State private var showingCategoryAccept = false

    init(services: AppEnvironment.Services) {
        _store = StateObject(wrappedValue: LibraryStore(services: services))
    }

    var body: some View {
        // 播放列用明確的 VStack 疊在底下，不用 safeAreaInset——
        // safeAreaInset 不會把 NavigationSplitView 各欄的內容往上推，
        // 結果是瀏覽器底部那一列被壓在播放列底下看不見。
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(store: store)
                    .navigationSplitViewColumnWidth(min: 190, ideal: 208, max: 260)
            } content: {
                SoundBrowserView(store: store,
                                 onBatchReview: { showingBatchReview = true },
                                 onAutoFill: { showingAutoFill = true },
                                 onNamingPreview: { showingNamingPreview = true },
                                 onCategoryAccept: { showingCategoryAccept = true },
                                 onOrganizerSettings: { showingOrganizerSettings = true })
                    .navigationSplitViewColumnWidth(min: 380, ideal: 560)
            } detail: {
                InspectorView(store: store)
                    .navigationSplitViewColumnWidth(min: 290, ideal: 320, max: 400)
            }

            SelectionBar(store: store)
            ReviewBar(store: store)
            PlaybackBar(store: store)
        }
        .onChange(of: store.selectedSoundId) {
            store.selectionDidChange()
        }
        .alert(L10n.tr("音色庫"), isPresented: Binding(
            get: { store.alert != nil },
            set: { if !$0 { store.alert = nil } }
        )) {
            Button(L10n.tr("好")) { store.alert = nil }
        } message: {
            Text(store.alert ?? "")
        }
        .sheet(isPresented: $showingOrganizerSettings) {
            OrganizerSettingsView(store: store)
        }
        .sheet(isPresented: $showingBatchReview) {
            BatchReviewSheet(store: store)
        }
        .sheet(isPresented: $showingNamingPreview) {
            NamingPreviewSheet(store: store)
        }
        .sheet(isPresented: $showingAutoFill) {
            AutoFillSheet(store: store)
        }
        .sheet(isPresented: $showingCategoryAccept) {
            CategoryAcceptSheet(store: store)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.addLibrary()
                } label: {
                    Label(L10n.tr("加入音色庫"), systemImage: "plus")
                }
                .help(L10n.tr("加入音色庫資料夾"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openSettings()
                } label: {
                    Label(L10n.tr("設定"), systemImage: "gearshape")
                }
                .help(L10n.tr("外觀與語言設定"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.analyzeSelected()
                } label: {
                    // 原本用 sparkles（閃亮的 AI 圖示），但這個動作跑的是**本機量測**，
                    // 不連網也不呼叫任何模型。圖示要說實話。
                    Label(L10n.tr("量測"), systemImage: "ruler")
                }
                .disabled(store.selectedSound == nil)
                .help(store.selectedSound == nil
                      ? L10n.tr("先在清單裡選一個音效，這個按鈕才會作用")
                      : L10n.tr("量測選取的音效（本機，不連網）"))
            }
        }
    }
}
