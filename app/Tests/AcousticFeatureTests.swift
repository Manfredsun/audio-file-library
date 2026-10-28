import XCTest
@testable import FoleyLibrary

/// 用程式合成的訊號測量測層。
///
/// 合成訊號的好處是「正確答案」由數學決定，不是由我猜的。
/// 440 Hz 正弦的頻譜重心就該在 440 Hz 附近，這不是主觀判斷。
final class AcousticFeatureTests: XCTestCase {

    private let sampleRate: Double = 44_100

    // MARK: - 合成

    private func sine(frequency: Double, seconds: Double, amplitude: Float = 0.8) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { index in
            amplitude * Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate))
        }
    }

    /// 固定種子的偽隨機，測試才能重跑出同樣的數字。
    private func whiteNoise(seconds: Double, amplitude: Float = 0.8) -> [Float] {
        let count = Int(seconds * sampleRate)
        var state: UInt64 = 0x2545F491_4F6CDD1D
        return (0..<count).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Float(Double((state >> 11)) / Double(UInt64(1) << 53))
            return amplitude * (unit * 2 - 1)
        }
    }

    /// 指數衰減的寬頻脈衝——撞擊聲的理想化形狀。
    private func impulse(seconds: Double, decay: Double = 30) -> [Float] {
        let noise = whiteNoise(seconds: seconds)
        return noise.enumerated().map { index, value in
            value * Float(exp(-decay * Double(index) / sampleRate))
        }
    }

    private func sweep(from start: Double, to end: Double, seconds: Double) -> [Float] {
        let count = Int(seconds * sampleRate)
        var phase = 0.0
        var output = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let progress = Double(index) / Double(count)
            let frequency = start + (end - start) * progress
            phase += 2 * Double.pi * frequency / sampleRate
            output[index] = 0.8 * Float(sin(phase))
        }
        return output
    }

    private func measure(_ samples: [Float]) -> AcousticFeatures {
        AcousticAnalyzer.features(samples: samples,
                                  sampleRate: sampleRate,
                                  channelCount: 1,
                                  duration: Double(samples.count) / sampleRate)
    }

    // MARK: - 頻譜

    func testSpectrumProcessorFindsPureToneBin() throws {
        let processor = try XCTUnwrap(SpectrumProcessor(size: 2048))
        let tone = sine(frequency: 1000, seconds: 0.1, amplitude: 1)
        let magnitudes = processor.magnitudes(of: Array(tone.prefix(2048)))
        let peakBin = try XCTUnwrap(magnitudes.enumerated().max(by: { $0.element < $1.element })?.offset)
        let binWidth = sampleRate / 2048
        let peakFrequency = Double(peakBin) * binWidth
        // bin 寬約 21.5 Hz，允許一個 bin 的誤差。
        XCTAssertEqual(peakFrequency, 1000, accuracy: binWidth * 1.5)
    }

    func testSpectrumProcessorRejectsNonPowerOfTwo() {
        XCTAssertNil(SpectrumProcessor(size: 1000))
        XCTAssertNil(SpectrumProcessor(size: 0))
    }

    // MARK: - 音色

    func testPureToneIsTonalNotNoisy() {
        let features = measure(sine(frequency: 440, seconds: 2))
        XCTAssertEqual(Double(features.spectralCentroid), 440, accuracy: 120)
        XCTAssertLessThan(features.spectralFlatness, 0.1, "純音的頻譜平坦度應該很低")
        // 頻帶切在 250 Hz / 4 kHz，440 Hz 落在中頻帶而不是低頻帶。
        XCTAssertGreaterThan(features.midEnergyRatio, 0.8, "440 Hz 的能量幾乎全在中頻帶")
        // 正弦的波峰因數是 √2，這是數學事實不是經驗值。
        XCTAssertEqual(Double(features.crestFactor), 2.0.squareRoot(), accuracy: 0.1)
    }

    func testWhiteNoiseIsFlatAndBright() {
        let features = measure(whiteNoise(seconds: 2))
        XCTAssertGreaterThan(features.spectralFlatness, 0.2, "白噪的頻譜平坦度應該明顯高於純音")
        XCTAssertGreaterThan(features.spectralCentroid, 4000, "白噪的重心應該落在頻譜中段偏高")
        XCTAssertGreaterThan(features.zeroCrossingRate, 0.2)
    }

    func testToneAndNoiseAreSeparableByFlatness() {
        let tone = measure(sine(frequency: 440, seconds: 2))
        let noise = measure(whiteNoise(seconds: 2))
        XCTAssertGreaterThan(noise.spectralFlatness, tone.spectralFlatness * 3,
                             "平坦度必須能拉開調性與噪聲，否則分類層沒有依據")
    }

    func testBandRatiosFollowFrequency() {
        let low = measure(sine(frequency: 100, seconds: 1))
        let high = measure(sine(frequency: 9000, seconds: 1))
        XCTAssertGreaterThan(low.lowEnergyRatio, 0.8)
        XCTAssertGreaterThan(high.highEnergyRatio, 0.8)
    }

    // MARK: - 包絡

    func testImpulseHasHighCrestAndLowSustain() {
        let features = measure(impulse(seconds: 1))
        XCTAssertGreaterThan(features.crestFactor, 4, "指數衰減的脈衝波峰因數應該遠高於持續音")
        XCTAssertLessThan(features.sustainRatio, 0.4, "能量集中在開頭，延音比例應該低")
        XCTAssertLessThan(features.attackTime, 0.05)
        XCTAssertGreaterThan(features.decayTime, 0)
    }

    func testSustainedToneHasHighSustainRatio() {
        let features = measure(sine(frequency: 440, seconds: 2))
        XCTAssertGreaterThan(features.sustainRatio, 0.9)
        XCTAssertLessThan(features.crestFactor, 3)
    }

    func testImpulseAndToneAreSeparableByCrestFactor() {
        let impulseFeatures = measure(impulse(seconds: 1))
        let toneFeatures = measure(sine(frequency: 440, seconds: 2))
        XCTAssertGreaterThan(impulseFeatures.crestFactor, toneFeatures.crestFactor * 2)
        XCTAssertGreaterThan(toneFeatures.sustainRatio, impulseFeatures.sustainRatio * 2)
    }

    func testLeadingAndTrailingSilenceAreMeasured() {
        let silence = [Float](repeating: 0, count: Int(0.5 * sampleRate))
        let samples = silence + sine(frequency: 440, seconds: 1) + silence
        let features = measure(samples)
        XCTAssertEqual(features.leadingSilence, 0.5, accuracy: 0.02)
        XCTAssertEqual(features.trailingSilence, 0.5, accuracy: 0.02)
    }

    // MARK: - 起音點

    func testSpacedClicksAreCountedIndividually() {
        let gap = [Float](repeating: 0, count: Int(0.3 * sampleRate))
        var samples: [Float] = []
        for _ in 0..<4 {
            samples += gap
            samples += impulse(seconds: 0.1, decay: 200)
        }
        let features = measure(samples)
        XCTAssertEqual(features.onsetCount, 4, "四個明顯分開的撞擊應該被數成四次")
    }

    func testSingleImpulseCountsOnce() {
        let gap = [Float](repeating: 0, count: Int(0.2 * sampleRate))
        let features = measure(gap + impulse(seconds: 0.5, decay: 60))
        XCTAssertEqual(features.onsetCount, 1)
    }

    // MARK: - 掃頻

    func testRisingSweepHasPositiveCentroidSlope() {
        let features = measure(sweep(from: 200, to: 8000, seconds: 2))
        XCTAssertGreaterThan(features.centroidSlope, 500, "上揚掃頻的重心斜率必須明顯為正")
    }

    func testFallingSweepHasNegativeCentroidSlope() {
        let features = measure(sweep(from: 8000, to: 200, seconds: 2))
        XCTAssertLessThan(features.centroidSlope, -500)
    }

    func testSteadyToneHasNearZeroCentroidSlope() {
        let features = measure(sine(frequency: 1000, seconds: 2))
        XCTAssertLessThan(abs(features.centroidSlope), 200, "穩定的音高不該被誤判成掃頻")
    }

    // MARK: - 靜音

    func testSilenceIsReportedAsSilenceNotFailure() {
        let features = measure([Float](repeating: 0, count: Int(sampleRate)))
        XCTAssertTrue(features.isSilent)
        XCTAssertEqual(features.peak, 0)
        XCTAssertEqual(features.onsetCount, 0)
        XCTAssertEqual(features.duration, 1, accuracy: 0.01)
    }

    func testUnreadableFileReturnsNil() {
        let url = URL(fileURLWithPath: "/tmp/definitely-not-audio-\(UUID().uuidString).wav")
        XCTAssertNil(AcousticAnalyzer.analyze(url: url))
    }
}
