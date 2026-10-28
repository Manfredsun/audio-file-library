import AppKit
import SwiftUI

/// 選單的一個項目。
enum MenuEntry {
    case item(String, checked: Bool = false, enabled: Bool = true, action: @MainActor () -> Void)
    case divider
    case submenu(String, [MenuEntry])
    /// 不可點的說明文字。
    case note(String)
}

/// 用 AppKit 的 NSMenu 彈出選單，觸發它的是一般的 SwiftUI Button。
///
/// 為什麼不用 SwiftUI 的 `Menu`（D-041）：macOS 會把 `Menu` 的標籤轉成 NSPopUpButton，
/// 標籤上的 padding、frame、contentShape 全部被忽略。實測「分析」「整理」和篩選 chip
/// 放大之後，點擊範圍仍然只有 30×15。改用 Button 觸發，點擊範圍就由 `ActionButtonStyle`
/// 決定，跟其他文字按鈕一致。
@MainActor
enum PopUpMenu {
    /// 在滑鼠位置彈出。按鈕是在放開滑鼠時觸發的，所以滑鼠位置就在按鈕上。
    static func show(_ entries: [MenuEntry]) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let view = window.contentView else { return }
        let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        build(entries).popUp(positioning: nil, at: point, in: view)
    }

    static func build(_ entries: [MenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            switch entry {
            case .divider:
                menu.addItem(.separator())
            case .note(let title):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            case .submenu(let title, let children):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = build(children)
                menu.addItem(item)
            case .item(let title, let checked, let enabled, let action):
                let target = MenuTarget(action)
                let item = NSMenuItem(title: title, action: #selector(MenuTarget.fire), keyEquivalent: "")
                item.target = target
                // NSMenuItem 的 target 是 weak；靠 representedObject 把它留住。
                item.representedObject = target
                item.state = checked ? .on : .off
                item.isEnabled = enabled
                menu.addItem(item)
            }
        }
        return menu
    }
}

@MainActor
private final class MenuTarget: NSObject {
    let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func fire() { action() }
}

/// 文字按鈕外觀的選單按鈕。項目在按下的那一刻才產生，所以分頁清單之類的動態內容永遠是最新的。
struct MenuButton<Label: View>: View {
    var style: ActionButtonStyle = ActionButtonStyle()
    let entries: () -> [MenuEntry]
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            PopUpMenu.show(entries())
        } label: {
            label()
        }
        .buttonStyle(style)
    }
}
