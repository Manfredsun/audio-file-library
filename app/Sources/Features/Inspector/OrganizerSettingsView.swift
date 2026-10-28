import AppKit
import SwiftUI

/// 分析設定。
///
/// 這裡曾經是引擎選單（本機／假引擎／Antigravity CLI）。實測證明
/// Antigravity 讀不到音訊而且會用高信心編造描述（D-013），選項因此整個移除——
/// 留一個「知情的錯誤選項」在選單上，只會讓人有一天選下去。
struct OrganizerSettingsView: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Ma.group) {
            MinchoTitle(text: L10n.tr("分析"))

            Text(store.organizerStatus)
                .font(DS.TypeScale.value)
                .foregroundStyle(DS.Palette.textPrimary)

            MaRule()

            VStack(alignment: .leading, spacing: DS.Ma.block) {
                row(L10n.tr("量測音訊本身"),
                    L10n.tr("起音、衰減、頻譜重心、平坦度、起音點。只記錄量到的，不詮釋。"))
                row(L10n.tr("讀取路徑字面"),
                    L10n.tr("資料夾與檔名裡的分類、風格、材質、BPM 與調性。讀不到就留空，不猜。"))
                row(L10n.tr("重讀路徑欄位"),
                    L10n.tr("只補風格、材質與字面節拍資料；既有分類建議一筆都不會改。"))
                row(L10n.tr("不連網"),
                    L10n.tr("不呼叫任何模型，也不會把你的檔名送到任何地方。"))
            }

            MaRule()

            VStack(alignment: .leading, spacing: DS.Ma.tight) {
                SectionLabel(text: L10n.tr("backup"))
                Text(L10n.tr("分頁、人工設定的分類與風格、接受過的建議，只存在這個資料庫裡，而且它在系統碟上不在你的音色庫碟上。大量寫入前會自動備份，保留最新 %@ 份。", String(describing: DatabaseBackup.keepCount)))
                    .font(DS.TypeScale.label)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if store.backups.isEmpty {
                    Text(L10n.tr("還沒有備份"))
                        .font(DS.TypeScale.label)
                        .foregroundStyle(DS.Palette.textTertiary)
                } else {
                    ForEach(store.backups.prefix(3)) { entry in
                        HStack {
                            Text(entry.trigger.isEmpty ? L10n.tr("備份") : L10n.tr(entry.trigger))
                                .font(DS.TypeScale.label)
                                .foregroundStyle(DS.Palette.textSecondary)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: entry.bytes,
                                                           countStyle: .file))
                                .font(DS.TypeScale.mono)
                                .foregroundStyle(DS.Palette.textTertiary)
                        }
                    }
                }

                HStack(spacing: DS.Ma.block) {
                    Button(L10n.tr("備份到⋯⋯")) { exportBackup() }
                        .buttonStyle(.action)
                        .foregroundStyle(DS.Palette.asagi)
                    if let folder = store.backupFolder, store.backups.isEmpty == false {
                        Button(L10n.tr("在 Finder 顯示")) {
                            NSWorkspace.shared.activateFileViewerSelecting([folder])
                        }
                        .buttonStyle(.action)
                        .foregroundStyle(DS.Palette.textSecondary)
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button(L10n.tr("關閉")) { dismiss() }
                    .buttonStyle(.action)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .padding(DS.Ma.section)
        .frame(width: 460, height: 520)
        .background(DS.Palette.sumi)
        .onAppear { store.refreshBackups() }
    }

    /// 備份到使用者指定的位置。**建議放在音色庫那顆碟上**——
    /// 自動備份跟資料庫在同一顆碟，擋得住做壞了，擋不住碟壞了。
    private func exportBackup() {
        let panel = NSSavePanel()
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        panel.nameFieldStringValue = "AudioFileLibrary-\(stamp).sqlite"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.exportBackup(to: url)
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Ma.hair) {
            Text(title)
                .font(DS.TypeScale.value)
                .foregroundStyle(DS.Palette.textPrimary)
            Text(detail)
                .font(DS.TypeScale.label)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
