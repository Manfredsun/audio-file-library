import SwiftUI

/// 波形。已播放的部分較亮，其餘較暗，播放頭是一條細線。
///
/// 用 Canvas 一次畫完，不做成上百個 View——
/// 列表捲動時每一列都有波形，view 數量會直接變成效能問題。
struct WaveformView: View {
    let peaks: [UInt8]
    var progress: Double = 0
    var played: Color = DS.Palette.asagi
    var unplayed: Color = DS.Palette.asagi.opacity(0.35)
    var showsPlayhead: Bool = false

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty, size.width > 0, size.height > 0 else { return }

            let count = peaks.count
            let step = size.width / CGFloat(count)
            let barWidth = max(0.6, step * 0.72)
            let mid = size.height / 2
            let splitX = size.width * CGFloat(min(max(progress, 0), 1))

            var playedPath = Path()
            var unplayedPath = Path()

            for index in 0..<count {
                let x = CGFloat(index) * step
                let height = max(1, CGFloat(peaks[index]) / 255 * size.height)
                let rect = CGRect(x: x, y: mid - height / 2, width: barWidth, height: height)
                if x < splitX {
                    playedPath.addRect(rect)
                } else {
                    unplayedPath.addRect(rect)
                }
            }

            context.fill(unplayedPath, with: .color(unplayed))
            if progress > 0 {
                context.fill(playedPath, with: .color(played))
            }

            if showsPlayhead, progress > 0 {
                var head = Path()
                head.addRect(CGRect(x: splitX - 0.5, y: 0, width: 1, height: size.height))
                context.fill(head, with: .color(DS.Palette.kinari))
            }
        }
    }
}

/// 清單用的小波形。沒有波形資料時退回長度墨痕——
/// 兩者畫的都是真實資料，只是精細度不同。
struct RowWaveform: View {
    let peaks: [UInt8]?
    let duration: Double?
    let emphasized: Bool

    var body: some View {
        if let peaks, !peaks.isEmpty {
            WaveformView(peaks: peaks,
                         progress: 0,
                         played: DS.Palette.asagi,
                         unplayed: emphasized ? DS.Palette.asagi.opacity(0.85) : DS.Palette.asagi.opacity(0.45))
                .frame(width: DS.Metrics.durationLane, height: 16)
        } else {
            DurationMark(duration: duration, emphasized: emphasized)
        }
    }
}
