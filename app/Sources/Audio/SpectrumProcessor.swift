import Accelerate
import Foundation

/// 實數 FFT 的薄包裝。用 Accelerate 是因為純 Swift 的 radix-2 在 854 個檔案上太慢。
///
/// 只負責「一幀樣本 → magnitude 頻譜」，沒有任何音訊語意。
final class SpectrumProcessor {
    let size: Int
    /// magnitude 的長度，等於 size / 2（bin 0 是 DC，bin i 的頻率是 i * sampleRate / size）。
    var binCount: Int { size / 2 }

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]

    /// size 必須是 2 的次方且 >= 4，否則回傳 nil——不要用斷言處理外部輸入。
    init?(size: Int = 2048) {
        guard size >= 4, size & (size - 1) == 0 else { return nil }
        let log2n = vDSP_Length(round(log2(Double(size))))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        self.size = size
        self.log2n = log2n
        self.setup = setup
        var hann = [Float](repeating: 0, count: size)
        vDSP_hann_window(&hann, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        self.window = hann
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// 回傳 binCount 個 magnitude。frame 長度不足時補零。
    func magnitudes(of frame: [Float]) -> [Float] {
        var padded = frame
        if padded.count < size {
            padded.append(contentsOf: [Float](repeating: 0, count: size - padded.count))
        } else if padded.count > size {
            padded.removeLast(padded.count - size)
        }

        var windowed = [Float](repeating: 0, count: size)
        vDSP_vmul(padded, 1, window, 1, &windowed, 1, vDSP_Length(size))

        let half = binCount
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var output = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { src in
                    src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // vDSP 把 Nyquist 疊在 imag[0]。留著會污染 DC bin 的 magnitude。
                split.imagp[0] = 0
                vDSP_zvabs(&split, 1, &output, 1, vDSP_Length(half))
            }
        }

        // vDSP_fft_zrip 的輸出帶 2 倍縮放。
        var scale: Float = 0.5
        vDSP_vsmul(output, 1, &scale, &output, 1, vDSP_Length(half))
        return output
    }
}

/// 一幀頻譜的統計量。
struct SpectrumStatistics: Equatable {
    var centroid: Float
    var rolloff: Float
    var flatness: Float
    var lowEnergy: Float
    var midEnergy: Float
    var highEnergy: Float
    var totalEnergy: Float

    /// magnitudes 以 power（magnitude²）加權——能量而不是振幅，才是頻譜重心的標準定義。
    static func compute(magnitudes: [Float],
                        sampleRate: Double,
                        fftSize: Int,
                        rolloffFraction: Float = 0.85) -> SpectrumStatistics {
        let binWidth = Float(sampleRate) / Float(fftSize)
        var totalPower: Float = 0
        var weighted: Float = 0
        var low: Float = 0
        var mid: Float = 0
        var high: Float = 0
        // 幾何平均用 log 累加，避免大量小數連乘下溢到 0。
        var logSum: Double = 0
        var counted = 0

        for (index, magnitude) in magnitudes.enumerated() {
            let power = magnitude * magnitude
            let frequency = Float(index) * binWidth
            totalPower += power
            weighted += power * frequency
            if frequency < 250 {
                low += power
            } else if frequency < 4000 {
                mid += power
            } else {
                high += power
            }
            // DC bin 不參與平坦度：它反映的是直流偏移，不是音色。
            if index > 0 {
                logSum += log(Double(power) + 1e-20)
                counted += 1
            }
        }

        guard totalPower > 0, counted > 0 else {
            return SpectrumStatistics(centroid: 0, rolloff: 0, flatness: 0,
                                      lowEnergy: 0, midEnergy: 0, highEnergy: 0, totalEnergy: 0)
        }

        var cumulative: Float = 0
        var rolloff: Float = 0
        let target = totalPower * rolloffFraction
        for (index, magnitude) in magnitudes.enumerated() {
            cumulative += magnitude * magnitude
            if cumulative >= target {
                rolloff = Float(index) * binWidth
                break
            }
        }

        let geometricMean = exp(logSum / Double(counted))
        // 算術平均同樣排除 DC bin，兩者的分母才一致。
        let arithmeticMean = Double(totalPower - magnitudes[0] * magnitudes[0]) / Double(counted)
        let flatness = arithmeticMean > 0 ? Float(geometricMean / arithmeticMean) : 0

        return SpectrumStatistics(centroid: weighted / totalPower,
                                  rolloff: rolloff,
                                  flatness: min(1, max(0, flatness)),
                                  lowEnergy: low,
                                  midEnergy: mid,
                                  highEnergy: high,
                                  totalEnergy: totalPower)
    }
}
