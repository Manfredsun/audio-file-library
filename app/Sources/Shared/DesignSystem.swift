import AppKit
import Foundation
import SwiftUI

/// 設計 token —— 墨色日式簡約。
///
/// 三個原則：
///   間（ma）      結構由間距與髮絲線構成，不用方框
///   余白（yohaku）留白是內容的一部分，不是浪費
///   不均整        不置中、不對稱，重量靠左
///
/// view 裡不出現任何字面數值。
enum DS {

    enum Palette {
        private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                               green: Double((value >> 8) & 255) / 255,
                               blue: Double(value & 255) / 255, alpha: 1)
            })
        }
        static let sumi = adaptive(0xF7F5F0, 0x14161A)
        static let kozumi = adaptive(0xEEEBE4, 0x1A1D22)
        static let nezumi = adaptive(0xD7D4CC, 0x2B2F36)
        static let kinari = adaptive(0x22262D, 0xE6E2D9)
        static let asagi = adaptive(0x286B7B, 0x7FB3C0)
        static let kihada = adaptive(0x7D5E13, 0xC4A24C)
        static let hi = adaptive(0xA63730, 0xD46C62)
        static let textPrimary = kinari
        static let textSecondary = adaptive(0x56616C, 0xAAA9A4)
        static let textTertiary = adaptive(0x65717B, 0x8C9399)
        static let hairline = kinari.opacity(0.12)
        static let hairlineFaint = kinari.opacity(0.07)
        static let selection = kinari.opacity(0.065)
        static let hover = kinari.opacity(0.08)
        static let pressed = kinari.opacity(0.13)
    }

    /// 間。刻意用大跨距——小間距負責行內，大間距負責分段，中間不要有模稜兩可的值。
    enum Ma {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let inline: CGFloat = 8
        static let block: CGFloat = 12
        static let group: CGFloat = 20
        static let section: CGFloat = 32
        static let chapter: CGFloat = 52
    }

    enum Metrics {
        static let rowHeight: CGFloat = 46
        static let sidebarRowHeight: CGFloat = 30
        static let playbackBarHeight: CGFloat = 72
        static let durationLane: CGFloat = 104
        static let numeralColumn: CGFloat = 46
        static let shioriWidth: CGFloat = 2
        /// 任何可點的東西，點擊範圍至少這麼高（寬度至少同值）。
        /// 使用者回饋「文字按鍵太小，很難按」：9.5pt 的字配 plain 樣式，
        /// 點擊範圍只有字形本身約 12pt 高（D-041）。
        static let hitTarget: CGFloat = 28
    }

    enum TypeScale {
        /// 明朝體。只用於分區標題——用多了就變成裝扮。
        static func mincho(_ size: CGFloat) -> Font { Font.custom("HiraMinProN-W3", size: size) }
        static func minchoStrong(_ size: CGFloat) -> Font { Font.custom("HiraMinProN-W6", size: size) }

        static let display    = minchoStrong(15)
        static let sectionJP  = mincho(11)

        static let rowTitle   = Font.system(size: 13, weight: .regular)
        static let rowMeta    = Font.system(size: 10.5)
        /// 不可點的標示（分區標題、單位、來源）。**不要**拿來當按鈕文字——按鈕用 `action`。
        static let label      = Font.system(size: 9.5, weight: .medium)
        /// 按鈕文字。
        static let action     = Font.system(size: 12, weight: .medium)
        /// 播放列、翻頁之類的符號按鈕。
        static let glyph      = Font.system(size: 13)
        static let value      = Font.system(size: 12)
        static let mono       = Font.system(size: 10.5, design: .monospaced)
        static let monoLarge  = Font.system(size: 12, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}

// MARK: - 結構元件

/// 分區標題。明朝體、字距放開、低對比——路標，不是內容。
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(DS.TypeScale.label)
            .tracking(1.4)
            .foregroundStyle(DS.Palette.textTertiary)
    }
}

/// 明朝體標題。
struct MinchoTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.TypeScale.display)
            .tracking(0.5)
            .foregroundStyle(DS.Palette.textPrimary)
    }
}

/// 內縮的髮絲線。不貫穿整個寬度——留一段余白，線才有起訖。
struct MaRule: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(DS.Palette.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// provenance。manari 是浅葱點，其餘是灰點；文字極小。
struct ProvenanceDot: View {
    let source: MetadataSource?

    var body: some View {
        if let source {
            HStack(spacing: DS.Ma.tight) {
                Circle()
                    .fill(source.isManual ? DS.Palette.asagi : DS.Palette.textTertiary)
                    .frame(width: 4, height: 4)
                Text(L10n.tr("source." + source.rawValue))
                    .font(DS.TypeScale.label)
                    .tracking(0.4)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }
}

/// 音の間 —— 這個介面的記號。
///
/// 髮絲線是靜默，其上較粗的一道墨痕是聲音，長度依時長對數縮放。
/// 一整欄看下去，短促的敲擊與綿長的環境音的節奏一眼可見。
/// 畫的是真實資料；M5 波形接上時，墨痕的位置就是波形的位置。
struct DurationMark: View {
    let duration: Double?
    var emphasized: Bool = false
    var lane: CGFloat = DS.Metrics.durationLane

    private static let minSeconds = 0.1
    private static let maxSeconds = 60.0

    private var fraction: CGFloat {
        guard let duration, duration > 0 else { return 0 }
        let clamped = min(max(duration, Self.minSeconds), Self.maxSeconds)
        let span = log(Self.maxSeconds) - log(Self.minSeconds)
        return CGFloat((log(clamped) - log(Self.minSeconds)) / span)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(DS.Palette.hairlineFaint)
                .frame(height: 1)
            Rectangle()
                .fill(emphasized ? DS.Palette.asagi : DS.Palette.asagi.opacity(0.5))
                .frame(width: max(3, lane * fraction), height: 2)
        }
        .frame(width: lane, height: 2)
    }
}

/// 空狀態。一行字，其餘是余白。
struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Ma.block) {
            Text(title)
                .font(DS.TypeScale.sectionJP)
                .foregroundStyle(DS.Palette.textSecondary)
            Text(message)
                .font(DS.TypeScale.rowMeta)
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(maxWidth: 240, alignment: .leading)
        }
        .padding(DS.Ma.chapter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

enum Format {
    /// 時長顯示成 M:SS 或 H:MM:SS。
    ///
    /// 小數秒對挑音效沒有用——沒有人會因為 104.94 秒還是 104.9 秒而做不同決定，
    /// 但「1:44」可以一眼看出這是一段長素材。超過一小時才補上小時位。
    static func seconds(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        let total = Int(value.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
