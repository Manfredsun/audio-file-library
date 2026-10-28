import SwiftUI

/// 文字按鈕的共用樣式（D-041）。
///
/// 視覺上維持原本的「只有字、沒有框」，但：
///   - 字級用 `DS.TypeScale.action`（12pt）
///   - 點擊範圍至少 `DS.Metrics.hitTarget`（28pt）見方，含字周圍的內距
///   - 滑過時有淡底，看得出這是可以按的
///
/// `flush` 用在靠左或靠右對齊的按鈕：內距仍然可以點，但版面位置跟改之前一樣，
/// 不會因為多了內距而讓左緣內縮。
struct ActionButtonStyle: ButtonStyle {
    var flush: Edge.Set = []

    func makeBody(configuration: Configuration) -> some View {
        ActionSurface(isPressed: configuration.isPressed, flush: flush) {
            configuration.label
                .font(DS.TypeScale.action)
        }
    }
}

extension ButtonStyle where Self == ActionButtonStyle {
    /// 一般的文字按鈕。
    static var action: ActionButtonStyle { ActionButtonStyle() }
    /// 靠左對齊的文字按鈕：左側內距不佔版面。
    static var actionLeading: ActionButtonStyle { ActionButtonStyle(flush: .leading) }
}

/// 可點範圍與滑過底色。
struct ActionSurface<Content: View>: View {
    var isPressed: Bool = false
    var flush: Edge.Set = []
    let content: Content

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    init(isPressed: Bool = false, flush: Edge.Set = [], @ViewBuilder content: () -> Content) {
        self.isPressed = isPressed
        self.flush = flush
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, DS.Ma.inline)
            .frame(minWidth: DS.Metrics.hitTarget, minHeight: DS.Metrics.hitTarget)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(fill)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            // 內距仍然可以點，但不把對齊邊推進去。
            .padding(.leading, flush.contains(.leading) ? -DS.Ma.inline : 0)
            .padding(.trailing, flush.contains(.trailing) ? -DS.Ma.inline : 0)
    }

    private var fill: Color {
        guard isEnabled else { return .clear }
        if isPressed { return DS.Palette.pressed }
        if hovering { return DS.Palette.hover }
        return .clear
    }
}

// `Menu` 的標籤會被 macOS 轉成 NSPopUpButton，padding 與 frame 都不生效；
// 需要選單的地方用 `MenuButton`／`PopUpMenu`（Shared/PopUpMenu.swift）。
