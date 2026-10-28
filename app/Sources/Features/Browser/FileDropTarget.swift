import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// AppKit 的檔案放置點，疊在 SwiftUI 的 view 上。
///
/// **為什麼不用 SwiftUI 的 `dropDestination`。**
/// 掛在 `Button` 上時它收不到任何東西——實測：同一個拖曳放進 Finder 與 Logic
/// 都成功，就是進不了分頁。而分頁的單擊選取又必須是 `Button`：換成
/// `onTapGesture` 之後單擊會被雙擊（改名）那個手勢吃掉，分頁變成點不動。
///
/// 在 SwiftUI 裡這兩件事只能二選一，所以把放置點交給 AppKit——它本來就分得開：
/// **拖曳的目的地搜尋不走 `hitTest`**，所以 `hitTest` 回 `nil` 讓滑鼠點擊
/// 穿過去給底下的 Button，放置照樣收得到。
struct FileDropTarget: NSViewRepresentable {

    /// 拖曳進入／離開。用來畫分頁的高亮。
    var isTargeted: (Bool) -> Void
    /// 回傳「有沒有接受這些檔案」。
    var onDrop: ([URL]) -> Bool

    final class DropView: NSView {
        var isTargeted: ((Bool) -> Void)?
        var onDrop: (([URL]) -> Bool)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([.fileURL])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError(L10n.tr("不從 nib 建立")) }

        /// 點擊穿過去給底下的 Button。拖曳不走這條路。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard urls(from: sender).isEmpty == false else { return [] }
            isTargeted?(true)
            return .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            isTargeted?(false)
        }

        override func draggingEnded(_ sender: NSDraggingInfo) {
            isTargeted?(false)
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            urls(from: sender).isEmpty == false
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            isTargeted?(false)
            let files = urls(from: sender)
            guard files.isEmpty == false else { return false }
            return onDrop?(files) ?? false
        }

        private func urls(from sender: NSDraggingInfo) -> [URL] {
            sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        }
    }

    func makeNSView(context: Context) -> DropView {
        DropView(frame: .zero)
    }

    func updateNSView(_ view: DropView, context: Context) {
        view.isTargeted = isTargeted
        view.onDrop = onDrop
    }
}
