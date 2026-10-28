import AppKit
import SwiftUI

/// 命名預覽（M31）。
///
/// **這個面板不會改任何東西。** 它只是把「如果照現在的規則整理，
/// 每個檔案會叫什麼名字」整份列出來，讓人在任何東西被建立之前先看過。
///
/// 真正會動磁碟的是 M32，而且到那時人已經看過這份清單了。
struct NamingPreviewSheet: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var undoCandidate: OrganizeBatch?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Ma.group) {
            MinchoTitle(text: L10n.tr("命名預覽"))

            Text(L10n.tr("確認預覽後可建立整理連結；歷史紀錄可撤銷已建立的連結。拖進 Logic 的是原始音檔。"))
                .font(DS.TypeScale.label)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            MaRule()
            organizeHistory

            if store.namingPlanIsBuilding {
                Text(L10n.tr("計算中…"))
                    .font(DS.TypeScale.value)
                    .foregroundStyle(DS.Palette.textSecondary)
                Spacer()
            } else if let plan = store.namingPlan {
                summary(plan)
                MaRule()
                table(plan)
                MaRule()
                footer(plan)
            } else {
                Text(L10n.tr("沒有資料。"))
                    .font(DS.TypeScale.value)
                    .foregroundStyle(DS.Palette.textSecondary)
                Spacer()
            }
        }
        .padding(DS.Ma.section)
        .frame(width: 760, height: 560)
        .background(DS.Palette.sumi)
                .onAppear {
            store.buildNamingPlan()
            store.refreshOrganizeBatches()
        }
        .alert(item: $undoCandidate) { batch in
            Alert(title: Text(L10n.tr("撤銷這次整理？")),
                  message: Text(L10n.tr("%@，%@ 個連結。只移除身分相符的整理連結，保留原始音檔及後來替換的檔案。", String(describing: batch.scope), String(describing: batch.linkCount))),
                  primaryButton: .destructive(Text(L10n.tr("撤銷"))) { store.undoOrganize(batchId: batch.id) },
                  secondaryButton: .cancel(Text(L10n.tr("取消"))))
        }
    }

    @ViewBuilder
    private var organizeHistory: some View {
        if !store.organizeBatches.isEmpty {
            SectionLabel(text: L10n.tr("整理紀錄"))
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Ma.tight) {
                    ForEach(store.organizeBatches) { batch in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(L10n.tr("%@ · %@ 個連結", String(describing: batch.scope), String(describing: batch.linkCount)))
                                    .font(DS.TypeScale.label)
                                Spacer()
                                if batch.isUndone {
                                    Text(L10n.tr("已撤銷")).font(DS.TypeScale.label)
                                } else {
                                    Button(L10n.tr("撤銷／重試")) { undoCandidate = batch }
                                        .buttonStyle(.action)
                                        .disabled(store.organizeProgress.isRunning || store.undoInProgress || store.batchWriteInProgress)
                                }
                            }
                            ForEach(batch.recoveryPaths, id: \.self) { path in
                                HStack {
                                    Text(path).font(DS.TypeScale.label).textSelection(.enabled)
                                    Button(L10n.tr("在 Finder 顯示")) { FileActions.revealInFinder(path: path) }
                                        .buttonStyle(.action)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 110)
            MaRule()
        }
    }

    // MARK: - 統計

    @ViewBuilder
    private func summary(_ plan: NamingPlan) -> some View {
        HStack(spacing: DS.Ma.block) {
            stat(L10n.tr("檔案"), "\(plan.total)")
            stat(L10n.tr("有描述詞"), "\(plan.withDescriptor)")
            stat(L10n.tr("覆蓋率"), percent(plan.withDescriptor, plan.total))
            Spacer()
            if plan.canExecute {
                Text(L10n.tr("沒有碰撞"))
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.textTertiary)
            } else {
                // 碰撞是**錯誤**，不是狀況：兩個檔案要進同一個位置。
                Text(L10n.tr("%@ 筆有衝突，必須先解決", String(describing: plan.blocking.count)))
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.kihada)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: DS.Ma.tight) {
            SectionLabel(text: label)
            Text(value)
                .font(DS.TypeScale.mono)
                .foregroundStyle(DS.Palette.textPrimary)
        }
    }

    private func percent(_ part: Int, _ whole: Int) -> String {
        guard whole > 0 else { return "－" }
        return String(format: "%.0f%%", Double(part) / Double(whole) * 100)
    }

    // MARK: - 對照表

    private func table(_ plan: NamingPlan) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(plan.entries.prefix(rowLimit), id: \.soundId) { entry in
                    HStack(alignment: .top, spacing: DS.Ma.block) {
                        // 原檔名在左邊：要對照的人先看的是它。
                        Text(entry.originalName)
                            .font(DS.TypeScale.rowMeta)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 250, alignment: .leading)

                        Text("→")
                            .font(DS.TypeScale.label)
                            .foregroundStyle(DS.Palette.textTertiary.opacity(0.5))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.newName)
                                .font(DS.TypeScale.rowTitle)
                                .foregroundStyle(entry.issues.contains(where: \.isBlocking)
                                                 ? DS.Palette.kihada : DS.Palette.textPrimary)
                                .lineLimit(1)
                            Text(entry.folder)
                                .font(DS.TypeScale.rowMeta)
                                .foregroundStyle(DS.Palette.textTertiary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: DS.Ma.block)

                        if let note = noteText(entry.issues) {
                            Text(note)
                                .font(DS.TypeScale.label)
                                .foregroundStyle(DS.Palette.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 1)
                }

                if plan.total > rowLimit {
                    Text(L10n.tr("還有 %@ 筆——整份請用 CSV 看", String(describing: plan.total - rowLimit)))
                        .font(DS.TypeScale.label)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .padding(.top, DS.Ma.block)
                }
            }
        }
    }

    /// 畫面只畫前面這些筆。四萬列的 LazyVStack 捲起來仍然是四萬個 view，
    /// 而且沒有人會用捲的去看四萬筆——整份要看就匯 CSV。
    private let rowLimit = 500

    private func noteText(_ issues: [NamingIssue]) -> String? {
        if issues.contains(.collision) { return L10n.tr("衝突：位置已被占用") }
        if issues.contains(.wordNotInSource) { return L10n.tr("描述詞不在原路徑裡") }
        if issues.contains(.noCategory) { return L10n.tr("沒有分類") }
        if issues.contains(.loopWithoutTempo) { return L10n.tr("loop 但沒有 BPM") }
        if issues.contains(.noDescriptor) { return L10n.tr("沒有描述詞（留空）") }
        return nil
    }

    // MARK: - 底部

    private func footer(_ plan: NamingPlan) -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.block) {
            // 按下去之前把會發生什麼事寫清楚：建在哪、建幾個、原檔怎麼樣。
            if store.organizeProgress.isRunning == false,
               store.organizeProgress.phase != .finished,
               let destination = store.organizeGroups.first?.root {
                Text(L10n.tr("執行會在 %@ 底下建立 %@ 個硬連結。原始檔案不會被改名、搬移或刪除，而且可以整批撤銷。", String(describing: shortPath(destination)), String(describing: OrganizeRun.linkCount(store.organizeGroups))))
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.organizeProgress.phase != .idle {
                Text(store.organizeProgress.summary)
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.asagi)
            }

            HStack {
                Button(L10n.tr("關閉")) { dismiss() }
                    .buttonStyle(.action)
                    .foregroundStyle(DS.Palette.textSecondary)

                Spacer()

                Button(L10n.tr("匯出 CSV")) { exportCSV() }
                    .buttonStyle(.action)
                    .foregroundStyle(DS.Palette.asagi)

                if store.organizeProgress.isRunning {
                    Button(L10n.tr("中止")) { store.cancelOrganize() }
                        .buttonStyle(.action)
                        .foregroundStyle(DS.Palette.kihada)
                } else {
                    // 有碰撞就不准執行——兩個檔案要進同一個位置，先決定哪一個該改。
                    Button(executeTitle) { store.runOrganize(scope: store.currentScopeName) }
                        .buttonStyle(.action)
                        .foregroundStyle(canExecute(plan) ? DS.Palette.asagi
                                         : DS.Palette.textTertiary.opacity(0.4))
                        .disabled(canExecute(plan) == false)
                }
            }
        }
    }

    private func canExecute(_ plan: NamingPlan) -> Bool {
        plan.canExecute && store.organizeGroups.isEmpty == false && !store.batchWriteInProgress && !store.undoInProgress
    }

    private var executeTitle: String {
        let count = OrganizeRun.linkCount(store.organizeGroups)
        return count > 0 ? L10n.tr("建立 %@ 個連結", String(describing: count)) : L10n.tr("建立連結")
    }

    /// 路徑只顯示最後兩段。整條 /Volumes/… 太長，擠掉真正要看的東西。
    private func shortPath(_ path: String) -> String {
        let parts = path.split(separator: "/").suffix(2)
        return parts.joined(separator: "/")
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "naming-plan.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        // 預設位置刻意不指向音色庫：這份檔案是給人看的，不屬於音色庫。
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.exportNamingPlan(to: url)
    }
}
