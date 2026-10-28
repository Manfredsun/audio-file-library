import SwiftUI

/// 依分類自動建立分頁。
///
/// 執行前先把「會建立哪些分頁、各幾筆」整份列出來——
/// 一次生出十幾個分頁，按下去才發現不是自己要的，代價太高。
struct AutoFillSheet: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    private static let minimums = [10, 20, 50, 100]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Ma.group) {
            MinchoTitle(text: L10n.tr("依分類建立分頁"))

            Text(L10n.tr("每個分類開一個分頁並填好。填進去之後就是你的了——是快照不是動態查詢，之後拖進拖出、重新排序都不會被程式改回去。"))
                .font(DS.TypeScale.label)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            MaRule()

            HStack(spacing: DS.Ma.block) {
                SectionLabel(text: L10n.tr("minimum"))
                ForEach(Self.minimums, id: \.self) { value in
                    Button {
                        store.autoFillMinimum = value
                        store.refreshAutoFillCandidates()
                    } label: {
                        Text("\(value)")
                            .font(DS.TypeScale.monoLarge)
                            .foregroundStyle(store.autoFillMinimum == value
                                             ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                            .padding(.horizontal, DS.Ma.tight)
                            .frame(minWidth: DS.Metrics.hitTarget, minHeight: DS.Metrics.hitTarget)
                            .background {
                                if store.autoFillMinimum == value {
                                    Rectangle().fill(DS.Palette.nezumi.opacity(0.5))
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text(L10n.tr("筆以上才開分頁"))
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.textTertiary)
                Spacer()
            }

            MaRule()

            if store.autoFillCandidates.isEmpty {
                VStack(alignment: .leading, spacing: DS.Ma.tight) {
                    Text(L10n.tr("沒有符合的分類。"))
                        .font(DS.TypeScale.value)
                        .foregroundStyle(DS.Palette.textSecondary)
                    // 這是最容易卡住的地方，直接講清楚怎麼解。
                    Text(L10n.tr("分頁是從**已經接受**的分類來的，不是從建議。先用「批次接受建議」把分析結果套用上去，這裡才會有東西。"))
                        .font(DS.TypeScale.label)
                        .foregroundStyle(DS.Palette.kihada)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(store.autoFillCandidates) { candidate in
                            HStack {
                                Text(BuiltinNames.category(candidate.path))
                                    .font(DS.TypeScale.value)
                                    .foregroundStyle(DS.Palette.textPrimary)
                                Spacer()
                                Text("\(candidate.count)")
                                    .font(DS.TypeScale.mono)
                                    .foregroundStyle(DS.Palette.textTertiary)
                            }
                        }
                    }
                }
            }

            HStack {
                Button(L10n.tr("取消")) { dismiss() }
                    .buttonStyle(.action)
                    .foregroundStyle(DS.Palette.textSecondary)
                Spacer()
                Button(applyTitle) {
                    store.applyAutoFill()
                    dismiss()
                }
                .buttonStyle(.action)
                .foregroundStyle(store.autoFillCandidates.isEmpty
                                 ? DS.Palette.textTertiary.opacity(0.4) : DS.Palette.asagi)
                .disabled(store.autoFillCandidates.isEmpty)
            }
        }
        .padding(DS.Ma.section)
        .frame(width: 460, height: 460)
        .background(DS.Palette.sumi)
        .onAppear { store.refreshAutoFillCandidates() }
    }

    private var applyTitle: String {
        let collections = store.autoFillCandidates.count
        let sounds = store.autoFillCandidates.reduce(0) { $0 + $1.count }
        guard collections > 0 else { return L10n.tr("建立") }
        return L10n.tr("建立 %@ 個分頁，填入 %@ 筆", String(describing: collections), String(describing: sounds))
    }
}
