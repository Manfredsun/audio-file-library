import SwiftUI

/// 接受一個分類底下的分類建議（M41、D-042）。
///
/// 使用者是在「Kick」這一類的檢視裡，聽過幾個之後按下去的。這裡要說清楚三件事：
/// 會套用幾筆、依什麼門檻、以及**不會**動到什麼（已確定的分類、標籤、原始檔案）。
struct CategoryAcceptSheet: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Ma.group) {
            MinchoTitle(text: L10n.tr("接受「%@」的建議", String(describing: store.currentCategoryPath.map { BuiltinNames.category($0) } ?? "")))

            Text(L10n.tr("只套用分類，不動標籤。已經有分類的音效（你設定的或之前接受的）不會被改，原始檔案也不會被動到。"))
                .font(DS.TypeScale.rowMeta)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            MaRule()

            VStack(alignment: .leading, spacing: DS.Ma.tight) {
                SectionLabel(text: L10n.tr("confidence"))
                ForEach(LibraryStore.categoryAcceptThresholds, id: \.value) { option in
                    thresholdRow(option)
                }
            }

            Spacer()

            HStack {
                Button(L10n.tr("取消")) { dismiss() }
                    .buttonStyle(.actionLeading)
                    .foregroundStyle(DS.Palette.textSecondary)
                Spacer()
                Button(applyTitle) {
                    store.acceptCurrentCategory()
                    dismiss()
                }
                .buttonStyle(ActionButtonStyle(flush: .trailing))
                .foregroundStyle(canApply ? DS.Palette.asagi : DS.Palette.textTertiary.opacity(0.4))
                .disabled(canApply == false)
            }
        }
        .padding(DS.Ma.section)
        .frame(width: 460, height: 380)
        .background(DS.Palette.sumi)
        .onAppear { store.refreshCategoryAcceptPreview() }
    }

    private func thresholdRow(_ option: (label: String, value: Double)) -> some View {
        let isSelected = abs(store.categoryAcceptThreshold - option.value) < 0.001
        let count = store.categoryAcceptCounts[option.value]
        return Button {
            store.categoryAcceptThreshold = option.value
        } label: {
            HStack(spacing: DS.Ma.tight) {
                Rectangle()
                    .fill(isSelected ? DS.Palette.asagi : Color.clear)
                    .frame(width: 2, height: 12)
                Text(option.label)
                    .font(DS.TypeScale.value)
                    .foregroundStyle(isSelected ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                Text(option.value > 0 ? String(format: "≥ %.2f", option.value) : "")
                    .font(DS.TypeScale.mono)
                    .foregroundStyle(DS.Palette.textTertiary)
                Spacer()
                Text(count.map { L10n.tr("%@ 筆", String(describing: $0)) } ?? "⋯")
                    .font(DS.TypeScale.monoLarge)
                    .foregroundStyle(isSelected ? DS.Palette.textPrimary : DS.Palette.textTertiary)
            }
            .frame(minHeight: DS.Metrics.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var selectedCount: Int {
        store.categoryAcceptCounts[store.categoryAcceptThreshold] ?? 0
    }

    private var canApply: Bool { selectedCount > 0 }

    private var applyTitle: String {
        selectedCount > 0 ? L10n.tr("接受 %@ 筆", String(describing: selectedCount)) : L10n.tr("接受")
    }
}
