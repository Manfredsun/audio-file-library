import AppKit
import Foundation
import UniformTypeIdentifiers

/// 實體檔案操作。全部由使用者明確觸發，而且沒有任何一個會改動檔案本身。
///
/// 改名／搬移是 M18 的事，而且會是獨立的、需要確認的動作（ROADMAP §8）。
enum FileActions {

    static func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func copyPath(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    /// 拖曳用的項目。
    ///
    /// 提供的是原始檔案的 URL，不做任何複製（ROADMAP §40）。
    /// Logic Pro、Finder 以及其他接受 file URL 的目標都吃這個。
    /// 拖進 DAW 的路徑。**永遠是原始檔案的路徑**（D-019）。
    ///
    /// 整理後的硬連結樹裡的名字會變——調了規則重跑一次，舊名字那個連結就被刪掉，
    /// 引用它的 Logic 專案會斷鏈，而 Logic 不會自己去找回來。
    /// 原始路徑是這個專案唯一承諾過永不改變的東西，所以 DAW 只該拿到它。
    ///
    /// 代價是 Logic 的音軌上顯示原本的檔名而不是整理後的名字。這是刻意的取捨。
    static func dragPath(for sound: Sound) -> String {
        sound.filePath
    }

    /// 拖曳項目**必須同時註冊兩種型別**。
    ///
    /// `NSItemProvider(contentsOf:)` 只註冊檔案自己的型別（`public.wav-audio`
    /// 之類），**不註冊 `public.file-url`**。Logic 與 Finder 吃前者，
    /// 所以拖進 DAW 一直都是好的；但 SwiftUI 的 `dropDestination(for: URL.self)`
    /// 認的是後者——分頁那一端從來沒收到過任何東西，拖過去就是沒反應。
    ///
    /// 兩種都註冊，而且檔案型別先註冊：先註冊的優先，Logic 拿到的東西不變。
    static func dragItem(path: String) -> NSItemProvider {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // 檔案不在時回傳空的 provider：拖曳會失敗，但不會當掉
            return NSItemProvider()
        }
        guard let provider = NSItemProvider(contentsOf: url) else { return NSItemProvider() }
        provider.suggestedName = url.lastPathComponent
        return provider
    }
}
