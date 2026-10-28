import AVFoundation
import Foundation

/// 波形峰值資料。
///
/// 每個 bucket 存一個 0–255 的峰值，整檔正規化到最大值——
/// 不正規化的話，小音量的素材在瀏覽器裡會是一條看不見的直線。
/// 這是視覺呈現的選擇，不改變任何音訊資料。
enum WaveformGenerator {

    /// 儲存解析度。列表縮圖會從這份資料降採樣，不重新讀檔。
    static let storedResolution = 512

    static func generate(url: URL, buckets: Int = storedResolution) -> [UInt8]? {
        guard buckets > 0,
              let file = try? AVAudioFile(forReading: url) else { return nil }

        let total = file.length
        guard total > 0 else { return nil }

        let format = file.processingFormat
        let channelCount = Int(format.channelCount)
        guard channelCount > 0 else { return nil }

        let framesPerBucket = max(1, Int(total) / buckets)
        var peaks = [Float](repeating: 0, count: buckets)

        let chunkFrames: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return nil }

        var frameIndex = 0
        while file.framePosition < total {
            do {
                try file.read(into: buffer)
            } catch {
                break
            }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let channels = buffer.floatChannelData else { break }

            for offset in 0..<frames {
                var value: Float = 0
                for channel in 0..<channelCount {
                    value = max(value, abs(channels[channel][offset]))
                }
                let bucket = min(buckets - 1, (frameIndex + offset) / framesPerBucket)
                if value > peaks[bucket] { peaks[bucket] = value }
            }
            frameIndex += frames
        }

        let loudest = peaks.max() ?? 0
        guard loudest > 0 else {
            // 全靜音是合法的結果，不是失敗
            return [UInt8](repeating: 0, count: buckets)
        }

        return peaks.map { peak in
            UInt8(clamping: Int((peak / loudest * 255).rounded()))
        }
    }

    /// 降採樣給列表縮圖用。取區間最大值，不取平均——
    /// 平均會把短促的衝擊音抹平成一條線，而那正是使用者要辨認的特徵。
    static func downsample(_ peaks: [UInt8], to buckets: Int) -> [UInt8] {
        guard buckets > 0 else { return [] }
        guard peaks.count > buckets else { return peaks }

        let ratio = Double(peaks.count) / Double(buckets)
        return (0..<buckets).map { index in
            let start = Int(Double(index) * ratio)
            let end = min(peaks.count, max(start + 1, Int(Double(index + 1) * ratio)))
            return peaks[start..<end].max() ?? 0
        }
    }
}
