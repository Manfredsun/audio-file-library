import SwiftUI

/// 審核列。選取的音效有待處理的建議時才出現。
///
/// 審核是一個「一直往下」的動作，所以每個按鈕按完都會自動跳到下一筆——
/// 每處理一筆還要自己按方向鍵的話，一萬多筆不可能做完。
struct ReviewBar: View {
    @ObservedObject var store: LibraryStore

    var body: some View {
        if store.pendingSuggestions.isEmpty == false {
            VStack(spacing: 0) {
                MaRule()
                HStack(spacing: DS.Ma.block) {
                    SectionLabel(text: L10n.tr("review"))

                    if let category = store.pendingCategorySuggestion {
                        Text(BuiltinNames.category(category.value))
                            .font(DS.TypeScale.value)
                            .foregroundStyle(DS.Palette.textPrimary)
                        if let confidence = category.confidence {
                            Text(String(format: "%.0f%%", confidence * 100))
                                .font(DS.TypeScale.mono)
                                .foregroundStyle(confidence >= ConfidencePolicy.default.reviewBelow
                                                 ? DS.Palette.asagi : DS.Palette.kihada)
                        }
                    } else {
                        Text(L10n.tr("沒有分類建議"))
                            .font(DS.TypeScale.label)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }

                    if let style = store.selectedSound?.style {
                        Text(BuiltinNames.style(style))
                            .font(DS.TypeScale.label)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }

                    // 引擎的量測摘要。人要能看出它憑什麼這樣說。
                    if let summary = store.analysis?.summary {
                        Text(summary)
                            .font(DS.TypeScale.label)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: DS.Ma.block)

                    action(L10n.tr("接受"), key: "A", colour: DS.Palette.asagi) {
                        store.acceptSelectedAndAdvance()
                    }
                    action(L10n.tr("拒絕"), key: "R", colour: DS.Palette.textSecondary) {
                        store.rejectSelectedAndAdvance()
                    }
                }
                .padding(.horizontal, DS.Ma.group)
                .padding(.vertical, DS.Ma.tight)
                .background(DS.Palette.kozumi)
            }
        }
    }

    private func action(_ title: String, key: String, colour: Color,
                        _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: DS.Ma.tight) {
                Text(title)
                    .foregroundStyle(colour)
                Text(key)
                    .font(DS.TypeScale.mono)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .padding(.horizontal, 3)
                    .background(Rectangle().fill(DS.Palette.nezumi.opacity(0.5)))
            }
        }
        .buttonStyle(.action)
    }
}
