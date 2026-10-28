import XCTest
@testable import FoleyLibrary

final class WaveformTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("foley-wave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    /// 寫一個 16-bit 單聲道 WAV，樣本由 `amplitude(frameIndex, totalFrames)` 決定（-1…1）。
    @discardableResult
    private func writeWAV(_ name: String,
                          seconds: Double = 1.0,
                          sampleRate: Int = 44_100,
                          amplitude: (Int, Int) -> Double) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        let frames = Int(Double(sampleRate) * seconds)
        let dataSize = frames * 2

        var data = Data()
        func put(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func p32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func p16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        put("RIFF"); p32(UInt32(36 + dataSize)); put("WAVE")
        put("fmt "); p32(16); p16(1); p16(1); p32(UInt32(sampleRate))
        p32(UInt32(sampleRate * 2)); p16(2); p16(16)
        put("data"); p32(UInt32(dataSize))

        for index in 0..<frames {
            let value = max(-1, min(1, amplitude(index, frames)))
            p16(UInt16(bitPattern: Int16(value * 32_000)))
        }

        try data.write(to: url)
        return url
    }

    // MARK: - 產生

    func testSilenceProducesFlatWaveformNotFailure() throws {
        let url = try writeWAV("silence.wav") { _, _ in 0 }
        let peaks = try XCTUnwrap(WaveformGenerator.generate(url: url, buckets: 64))

        XCTAssertEqual(peaks.count, 64)
        XCTAssertTrue(peaks.allSatisfy { $0 == 0 }, "全靜音是合法結果，不是失敗")
    }

    func testLoudSectionShowsUpInTheRightPlace() throws {
        // 前半靜音，後半滿幅
        let url = try writeWAV("half.wav") { index, total in
            index < total / 2 ? 0 : 1
        }
        let peaks = try XCTUnwrap(WaveformGenerator.generate(url: url, buckets: 100))

        let firstQuarter = peaks[0..<25]
        let lastQuarter = peaks[75..<100]

        XCTAssertTrue(firstQuarter.allSatisfy { $0 < 10 }, "前段應該接近靜音")
        XCTAssertTrue(lastQuarter.allSatisfy { $0 > 200 }, "後段應該接近滿幅")
    }

    func testQuietFileIsNormalisedSoItIsVisible() throws {
        // 整檔只有 5% 音量：不正規化的話在瀏覽器裡等於一條直線
        let url = try writeWAV("quiet.wav") { _, _ in 0.05 }
        let peaks = try XCTUnwrap(WaveformGenerator.generate(url: url, buckets: 32))

        XCTAssertTrue(peaks.contains { $0 > 200 }, "正規化後最大值應該接近滿幅")
    }

    func testMissingFileReturnsNil() {
        let peaks = WaveformGenerator.generate(url: scratch.appendingPathComponent("nope.wav"))
        XCTAssertNil(peaks)
    }

    func testRequestedResolutionIsHonoured() throws {
        let url = try writeWAV("res.wav") { _, _ in 0.5 }
        XCTAssertEqual(WaveformGenerator.generate(url: url, buckets: 16)?.count, 16)
        XCTAssertEqual(WaveformGenerator.generate(url: url, buckets: 256)?.count, 256)
    }

    // MARK: - 降採樣

    func testDownsampleKeepsPeaksNotAverages() {
        // 一個孤立的尖峰淹沒在靜音裡：取平均會讓它消失
        var peaks = [UInt8](repeating: 0, count: 100)
        peaks[42] = 255

        let small = WaveformGenerator.downsample(peaks, to: 10)

        XCTAssertEqual(small.count, 10)
        XCTAssertEqual(small.max(), 255, "短促的衝擊音不可以被平均掉")
    }

    func testDownsampleLeavesShortDataAlone() {
        let peaks: [UInt8] = [1, 2, 3]
        XCTAssertEqual(WaveformGenerator.downsample(peaks, to: 10), peaks)
    }

    func testDownsampleToZeroIsEmpty() {
        XCTAssertTrue(WaveformGenerator.downsample([1, 2, 3], to: 0).isEmpty)
    }

    // MARK: - 快取

    func testWaveformIsCachedAndReusedAcrossCalls() throws {
        let database = try TestSupport.database()
        let store = WaveformStore(database: database)
        let url = try writeWAV("cached.wav") { _, _ in 0.8 }

        let library = try LibraryManager(database: database).add(url: scratch)
        let sound = try database.writer.write { db -> Sound in
            var sound = Sound(libraryId: library.id ?? 0,
                              filePath: url.path,
                              relativePath: "cached.wav",
                              filename: "cached.wav",
                              fileExtension: "wav")
            try sound.insert(db)
            return sound
        }
        let soundId = try XCTUnwrap(sound.id)

        XCTAssertNil(store.cached(soundId: soundId), "一開始不該有快取")

        let first = try XCTUnwrap(store.peaks(soundId: soundId, url: url))
        let cached = try XCTUnwrap(store.cached(soundId: soundId))
        XCTAssertEqual(first, cached, "第二次應該直接從資料庫拿到同一份資料")

        // 檔案刪掉之後，快取仍然可用——重繪不該重新解碼
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(store.peaks(soundId: soundId, url: url), first)

        store.invalidate(soundId: soundId)
        XCTAssertNil(store.cached(soundId: soundId))
    }
}
