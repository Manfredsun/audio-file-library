import AppKit
import Foundation

/// 資料夾選取。抽成 protocol 是為了讓 LibraryManager 的邏輯能在沒有 UI 的情況下測試。
@MainActor
protocol FolderPicker {
    func pickFolders() -> [URL]
}

@MainActor
struct SystemFolderPicker: FolderPicker {
    func pickFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("加入音色庫")
        panel.message = L10n.tr("選擇包含音效檔的資料夾。原始檔案不會被移動或改名。")
        panel.prompt = L10n.tr("加入")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }
}
