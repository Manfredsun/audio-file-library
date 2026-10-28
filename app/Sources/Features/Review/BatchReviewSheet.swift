import SwiftUI

/// 批次接受建議。
///
/// 這個畫面的重點是**執行前先說清楚會發生什麼**：套用幾筆、跳過幾筆、為什麼跳過。
/// 41,293 個檔案裡有一萬多筆建議，按下去之後才發現不是自己要的，代價太高。
struct BatchReviewSheet: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    private static let thresholds: [(label: String, value: Double)] = [
        (L10n.tr("只接受兩條證據一致的"), ConfidencePolicy.default.strongMin),
        (L10n.tr("也接受路徑證據強的"), ConfidencePolicy.default.moderateMin),
        (L10n.tr("連弱證據也接受"), ConfidencePolicy.default.weakMin),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Ma.group) {
            MinchoTitle(text: L10n.tr("批次接受"))

            Text(L10n.tr("AI 的建議一直都只寫在建議欄裡，要你接受才會生效。這裡只是讓你按一次算幾千次——不是讓程式替你決定。"))
                .font(DS.TypeScale.label)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            MaRule()

            VStack(alignment: .leading, spacing: DS.Ma.tight) {
                SectionLabel(text: L10n.tr("confidence"))
                ForEach(Self.thresholds, id: \.value) { option in
                    thresholdRow(option)
                }
            }

            Toggle(isOn: $store.reviewIncludesTags) {
                Text(L10n.tr("同時接受量測得到的標籤（short、bright、sharp⋯⋯）"))
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: store.reviewIncludesTags) { _, _ in store.refreshBatchReviewPreview() }

            MaRule()

            preview

            Spacer()

            HStack {
                Button(L10n.tr("取消")) { dismiss() }
                    .buttonStyle(.action)
                    .foregroundStyle(DS.Palette.textSecondary)
                Spacer()
                Button(applyTitle) {
                    store.applyBatchReview()
                    dismiss()
                }
                .buttonStyle(.action)
                .foregroundStyle(canApply ? DS.Palette.asagi : DS.Palette.textTertiary.opacity(0.4))
                .disabled(canApply == false)
            }
        }
        .padding(DS.Ma.section)
        .frame(width: 460, height: 420)
        .background(DS.Palette.sumi)
        .onAppear { store.refreshBatchReviewPreview() }
    }

    private func thresholdRow(_ option: (label: String, value: Double)) -> some View {
        let isSelected = abs(store.reviewThreshold - option.value) < 0.001
        return Button {
            store.reviewThreshold = option.value
            store.refreshBatchReviewPreview()
        } label: {
            HStack(spacing: DS.Ma.tight) {
                Rectangle()
                    .fill(isSelected ? DS.Palette.asagi : Color.clear)
                    .frame(width: 2, height: 12)
                Text(option.label)
                    .font(DS.TypeScale.value)
                    .foregroundStyle(isSelected ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                Text(String(format: "≥ %.2f", option.value))
                    .font(DS.TypeScale.mono)
                    .foregroundStyle(DS.Palette.textTertiary)
                Spacer()
            }
            .frame(minHeight: DS.Metrics.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        if let preview = store.batchReviewPreview {
            VStack(alignment: .leading, spacing: DS.Ma.tight) {
                SectionLabel(text: L10n.tr("preview"))
                line(L10n.tr("套用分類"), L10n.sounds(preview.categories), DS.Palette.textPrimary)
                if store.reviewIncludesTags {
                    line(L10n.tr("加上標籤"), L10n.tr("%@ 筆", String(describing: preview.tags)), DS.Palette.textSecondary)
                }
                if preview.skippedManual > 0 {
                    line(L10n.tr("跳過"), L10n.tr("%@ 個你已經人工設定過的", String(describing: preview.skippedManual)), DS.Palette.kihada)
                }
                if preview.isEmpty {
                    Text(L10n.tr("這個門檻下沒有待處理的建議。"))
                        .font(DS.TypeScale.label)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
        } else {
            Text(L10n.tr("計算中⋯⋯"))
                .font(DS.TypeScale.label)
                .foregroundStyle(DS.Palette.textTertiary)
        }
    }

    private func line(_ label: String, _ value: String, _ colour: Color) -> some View {
        HStack(spacing: DS.Ma.tight) {
            Text(label)
                .font(DS.TypeScale.label)
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(DS.TypeScale.value)
                .foregroundStyle(colour)
        }
    }

    private var canApply: Bool {
        (store.batchReviewPreview?.isEmpty ?? true) == false
    }

    private var applyTitle: String {
        guard let preview = store.batchReviewPreview, preview.categories > 0 else { return L10n.tr("套用") }
        return L10n.tr("套用到 %@ 個音效", String(describing: preview.categories))
    }
}
