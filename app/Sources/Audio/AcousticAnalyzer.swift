import AVFoundation
import Accelerate
import Foundation

/// 從音檔量測 `AcousticFeatures`。
///
/// 只讀檔、只算數。任何「這是什麼聲音」的判斷都在 Organizer 層，不在這裡。
enum AcousticAnalyzer {

    /// 分析窗上限。超長的 ambience 不需要整檔算完才知道它是持續噪聲，
    /// 而 854 個檔案的批次要能在合理時間內跑完。
    static let maxAnalysisSeconds: Double = 30

    static let frameSize = 2048
    static let hopSize = 512
    /// 低於這個振幅視為靜音（約 −60 dBFS）。
    static let silenceFloor: Float = 0.001

    /// 讀不到檔或格式不支援時回傳 nil。nil 代表「沒量到」，不是「是靜音」。
    static func analyze(url: URL) -> AcousticFeatures? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        let totalFrames = file.length
        guard sampleRate > 0, channelCount > 0, totalFrames > 0 else { return nil }

        let duration = Double(totalFrames) / sampleRate
        guard let mono = readMono(file: file,
                                  format: format,
                                  channelCount: channelCount,
                                  limit: AVAudioFramePosition(maxAnalysisSeconds * sampleRate)),
              !mono.isEmpty else { return nil }

        return features(samples: mono,
                        sampleRate: sampleRate,
                        channelCount: channelCount,
                        duration: duration)
    }

    /// 把任意聲道數降混成單聲道 Float 陣列。降混是為了量測，不影響播放與原檔。
    private static func readMono(file: AVAudioFile,
                                 format: AVAudioFormat,
                                 channelCount: Int,
                                 limit: AVAudioFramePosition) -> [Float]? {
        let chunkFrames: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return nil }
        var mono: [Float] = []
        mono.reserveCapacity(Int(min(file.length, limit)))
        let inverse = 1 / Float(channelCount)

        while file.framePosition < file.length && AVAudioFramePosition(mono.count) < limit {
            do {
                try file.read(into: buffer)
            } catch {
                break
            }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let channels = buffer.floatChannelData else { break }

            if channelCount == 1 {
                mono.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: frames))
            } else {
                var chunk = [Float](repeating: 0, count: frames)
                for channel in 0..<channelCount {
                    vDSP_vadd(chunk, 1, channels[channel], 1, &chunk, 1, vDSP_Length(frames))
                }
                var scale = inverse
                vDSP_vsmul(chunk, 1, &scale, &chunk, 1, vDSP_Length(frames))
                mono.append(contentsOf: chunk)
            }
        }
        return mono
    }

    /// 已在記憶體裡的樣本直接量測。測試用合成訊號走這條路，不需要落地成檔案。
    static func features(samples: [Float],
                         sampleRate: Double,
                         channelCount: Int,
                         duration: Double) -> AcousticFeatures {
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        guard peak > silenceFloor else {
            return .silent(duration: duration, sampleRate: sampleRate, channelCount: channelCount)
        }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        let leading = leadingSilence(samples, sampleRate: sampleRate)
        let trailing = trailingSilence(samples, sampleRate: sampleRate)
        let zcr = zeroCrossingRate(samples)

        let envelope = frameEnvelope(samples)
        let (attack, decay, sustain) = envelopeShape(envelope, sampleRate: sampleRate)

        let spectral = spectralProfile(samples, sampleRate: sampleRate)
        let onsetTimes = onsetTimes(envelope, sampleRate: sampleRate)
        let onsets = onsetTimes.count

        // 聲學上像不像 loop：夠長、有多次起音、能量持續。
        // 這是跟路徑字面互相獨立的第二條證據。
        let loopLike = duration >= 1.0 && onsets >= 4 && sustain > 0.3
        let tempo = TempoAnalyzer.estimate(duration: duration,
                                           onsetTimes: onsetTimes,
                                           isLoopLike: loopLike)

        let totalBandEnergy = spectral.low + spectral.mid + spectral.high
        let lowRatio = totalBandEnergy > 0 ? spectral.low / totalBandEnergy : 0
        let midRatio = totalBandEnergy > 0 ? spectral.mid / totalBandEnergy : 0
        let highRatio = totalBandEnergy > 0 ? spectral.high / totalBandEnergy : 0

        return AcousticFeatures(duration: duration,
                                sampleRate: sampleRate,
                                channelCount: channelCount,
                                peak: peak,
                                rms: rms,
                                crestFactor: rms > 0 ? peak / rms : 0,
                                attackTime: attack,
                                decayTime: decay,
                                sustainRatio: sustain,
                                zeroCrossingRate: zcr,
                                spectralCentroid: spectral.centroid,
                                spectralRolloff: spectral.rolloff,
                                spectralFlatness: spectral.flatness,
                                lowEnergyRatio: lowRatio,
                                midEnergyRatio: midRatio,
                                highEnergyRatio: highRatio,
                                centroidSlope: spectral.centroidSlope,
                                onsetCount: onsets,
                                leadingSilence: leading,
                                trailingSilence: trailing,
                                tempo: tempo.bpm,
                                tempoConfidence: tempo.confidence,
                                isLoopLike: loopLike)
    }

    // MARK: - 時域

    private static func leadingSilence(_ samples: [Float], sampleRate: Double) -> Double {
        for (index, value) in samples.enumerated() where abs(value) > silenceFloor {
            return Double(index) / sampleRate
        }
        return Double(samples.count) / sampleRate
    }

    private static func trailingSilence(_ samples: [Float], sampleRate: Double) -> Double {
        for index in stride(from: samples.count - 1, through: 0, by: -1)
        where abs(samples[index]) > silenceFloor {
            return Double(samples.count - 1 - index) / sampleRate
        }
        return Double(samples.count) / sampleRate
    }

    private static func zeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        for index in 1..<samples.count where (samples[index] >= 0) != (samples[index - 1] >= 0) {
            crossings += 1
        }
        return Float(crossings) / Float(samples.count - 1)
    }

    /// 每 hop 一個 RMS 值。包絡的所有判斷都建立在這上面。
    private static func frameEnvelope(_ samples: [Float]) -> [Float] {
        guard samples.count >= hopSize else {
            var value: Float = 0
            vDSP_rmsqv(samples, 1, &value, vDSP_Length(samples.count))
            return [value]
        }
        var envelope: [Float] = []
        envelope.reserveCapacity(samples.count / hopSize + 1)
        var start = 0
        while start < samples.count {
            let end = min(start + frameSize, samples.count)
            let count = end - start
            var value: Float = 0
            samples.withUnsafeBufferPointer { pointer in
                vDSP_rmsqv(pointer.baseAddress! + start, 1, &value, vDSP_Length(count))
            }
            envelope.append(value)
            start += hopSize
        }
        return envelope
    }

    /// 起音時間、衰減時間、延音比例。三者都以峰值 −20 dB（0.1 倍）為門檻。
    private static func envelopeShape(_ envelope: [Float],
                                      sampleRate: Double) -> (Double, Double, Float) {
        guard let peakValue = envelope.max(), peakValue > 0,
              let peakIndex = envelope.firstIndex(of: peakValue) else { return (0, 0, 0) }
        let hopSeconds = Double(hopSize) / sampleRate
        let threshold = peakValue * 0.1

        // 起音：峰值往回找到最後一次低於門檻的位置。
        // 找不到代表訊號一開始就很大聲（持續音、被切過頭的素材），起音時間視為 0，
        // 不能拿 peakIndex 當起音點——那會把整段前綴誤報成緩慢的起音。
        var onsetIndex: Int?
        for index in stride(from: peakIndex, through: 0, by: -1) where envelope[index] < threshold {
            onsetIndex = index
            break
        }
        let attack = onsetIndex.map { Double(peakIndex - $0) * hopSeconds } ?? 0

        // 衰減：峰值往後找到第一次低於門檻的位置；找不到代表尾巴還沒掉下來。
        var decayIndex = envelope.count - 1
        for index in peakIndex..<envelope.count where envelope[index] < threshold {
            decayIndex = index
            break
        }
        let decay = Double(decayIndex - peakIndex) * hopSeconds

        let aboveThreshold = envelope.filter { $0 >= threshold }.count
        let sustain = Float(aboveThreshold) / Float(envelope.count)

        return (attack, decay, sustain)
    }

    /// 起音點的時間：包絡的正向差分超過自適應門檻，且與前一次相隔至少 50 ms。
    ///
    /// 回傳時間而不只是數量，因為節拍量測需要間隔。
    private static func onsetTimes(_ envelope: [Float], sampleRate: Double) -> [Double] {
        guard envelope.count > 2, let peakValue = envelope.max(), peakValue > 0 else { return [] }
        var flux: [Float] = []
        flux.reserveCapacity(envelope.count - 1)
        for index in 1..<envelope.count {
            flux.append(max(0, envelope[index] - envelope[index - 1]))
        }
        guard let maxFlux = flux.max(), maxFlux > 0 else { return [] }

        let threshold = maxFlux * 0.25
        // hop 是 512 樣本；50 ms 在 44.1 kHz 約 4 個 hop。用固定幀數而非秒數，
        // 是因為這裡只比較相對位置，取樣率差異的影響在可接受範圍內。
        let minimumSeparation = 4
        let hopSeconds = Double(hopSize) / sampleRate
        var times: [Double] = []
        var lastIndex = -minimumSeparation
        for (index, value) in flux.enumerated()
        where value >= threshold && index - lastIndex >= minimumSeparation {
            // flux[i] 是 envelope[i+1] 相對 envelope[i] 的上升，所以起音在 i+1。
            times.append(Double(index + 1) * hopSeconds)
            lastIndex = index
        }
        return times
    }

    // MARK: - 頻域

    private struct SpectralProfile {
        var centroid: Float
        var rolloff: Float
        var flatness: Float
        var low: Float
        var mid: Float
        var high: Float
        var centroidSlope: Float
    }

    private static func spectralProfile(_ samples: [Float], sampleRate: Double) -> SpectralProfile {
        guard let processor = SpectrumProcessor(size: frameSize) else {
            return SpectralProfile(centroid: 0, rolloff: 0, flatness: 0,
                                   low: 0, mid: 0, high: 0, centroidSlope: 0)
        }

        var centroidSum: Float = 0
        var rolloffSum: Float = 0
        var flatnessSum: Float = 0
        var weightSum: Float = 0
        var low: Float = 0
        var mid: Float = 0
        var high: Float = 0
        // 只有有聲的幀才進入重心斜率的回歸；靜音幀的重心沒有意義。
        var times: [Float] = []
        var centroids: [Float] = []

        var start = 0
        while start < samples.count {
            let end = min(start + frameSize, samples.count)
            let frame = Array(samples[start..<end])
            let magnitudes = processor.magnitudes(of: frame)
            let stats = SpectrumStatistics.compute(magnitudes: magnitudes,
                                                   sampleRate: sampleRate,
                                                   fftSize: frameSize)
            if stats.totalEnergy > 0 {
                // 以能量加權：大聲的幀比雜訊底噪更能代表這個檔案的音色。
                let weight = stats.totalEnergy
                centroidSum += stats.centroid * weight
                rolloffSum += stats.rolloff * weight
                flatnessSum += stats.flatness * weight
                weightSum += weight
                low += stats.lowEnergy
                mid += stats.midEnergy
                high += stats.highEnergy
                times.append(Float(start) / Float(sampleRate))
                centroids.append(stats.centroid)
            }
            start += hopSize
        }

        guard weightSum > 0 else {
            return SpectralProfile(centroid: 0, rolloff: 0, flatness: 0,
                                   low: 0, mid: 0, high: 0, centroidSlope: 0)
        }

        return SpectralProfile(centroid: centroidSum / weightSum,
                               rolloff: rolloffSum / weightSum,
                               flatness: flatnessSum / weightSum,
                               low: low,
                               mid: mid,
                               high: high,
                               centroidSlope: linearSlope(x: times, y: centroids))
    }

    /// 最小平方法的斜率。點數不足或 x 無變異時回傳 0。
    private static func linearSlope(x: [Float], y: [Float]) -> Float {
        guard x.count == y.count, x.count >= 3 else { return 0 }
        let n = Float(x.count)
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n
        var numerator: Float = 0
        var denominator: Float = 0
        for index in 0..<x.count {
            let dx = x[index] - meanX
            numerator += dx * (y[index] - meanY)
            denominator += dx * dx
        }
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }
}
