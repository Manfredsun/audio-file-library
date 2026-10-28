import AppKit
import SwiftUI
import XCTest
@testable import FoleyLibrary

@MainActor
final class UIEmptyStateLayoutTests: XCTestCase {
    private func verifyEmptySplitView(locale: String) {
        // Native split views measure their columns at very narrow widths first.
        // Long fixed-height text used to demand a 1,444pt window, clipping every column.
        let root = VStack(spacing: 0) {
            NavigationSplitView {
                ScrollView { Text("Sidebar") }
                    .navigationSplitViewColumnWidth(min: 190, ideal: 208, max: 260)
            } content: {
                VStack(spacing: 0) {
                    Text("Header").frame(height: 72)
                    EmptyStateView(title: L10n.tr("這個分頁還是空的", locale: locale),
                                   message: L10n.tr("回到 LIBRARY 分頁，把音檔拖到上面的分頁名稱上就會加進來。原始檔案不會被移動。", locale: locale))
                    Text("Footer").frame(height: 40)
                }
                .navigationSplitViewColumnWidth(min: 380, ideal: 560)
            } detail: {
                EmptyStateView(title: L10n.tr("未選取", locale: locale),
                               message: L10n.tr("從清單選一個音效，這裡會顯示它的 metadata 與分析結果。", locale: locale))
                    .navigationSplitViewColumnWidth(min: 290, ideal: 320, max: 400)
            }
            Text("Playback").frame(height: 72)
        }
        .frame(minWidth: 1000, minHeight: 600)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.height, 650, "Empty content must fit the minimum window in \(locale)")
        XCTAssertTrue(host.fittingSize.height.isFinite)
    }
    func testEnglishEmptyColumnsFitMinimumWindow() { verifyEmptySplitView(locale: "en") }
    func testChineseEmptyColumnsFitMinimumWindow() { verifyEmptySplitView(locale: "zh-Hant") }
}
