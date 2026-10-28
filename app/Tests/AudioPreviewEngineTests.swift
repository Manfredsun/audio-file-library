import XCTest
@testable import FoleyLibrary

/// 假播放器。讓狀態機能在沒有音訊裝置的情況下被測試。
private final class FakePlayer: AudioPlayback {
    var duration: TimeInterval = 2.0
    var currentTime: TimeInterval = 0
    var isPlaying: Bool = false
    var volume: Float = 1
    var stopCount = 0
    var playCount = 0
    var shouldFailToPlay = false

    func play() -> Bool {
        if shouldFailToPlay { return false }
        playCount += 1
        isPlaying = true
        return true
    }

    func pause() { isPlaying = false }

    func stop() {
        stopCount += 1
        isPlaying = false
    }
}

@MainActor
final class AudioPreviewEngineTests: XCTestCase {

    private var scratch: URL!
    private var players: [FakePlayer] = []

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("foley-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        players = []
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    private func makeEngine() -> AudioPreviewEngine {
        AudioPreviewEngine { [weak self] _ in
            let player = FakePlayer()
            self?.players.append(player)
            return player
        }
    }

    private func makeSound(id: Int64, name: String) throws -> Sound {
        let url = scratch.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return Sound(id: id,
                     libraryId: 1,
                     filePath: url.path,
                     relativePath: name,
                     filename: name,
                     fileExtension: "wav")
    }

    func testPlayingSetsState() throws {
        let engine = makeEngine()
        let sound = try makeSound(id: 1, name: "a.wav")

        engine.play(sound: sound)

        XCTAssertEqual(engine.state, .playing(soundId: 1))
        XCTAssertEqual(engine.duration, 2.0)
        XCTAssertEqual(players.count, 1)
    }

    /// 這是這個引擎存在的理由：選 B 時 A 必須立刻停，不排隊、不疊加。
    func testSelectingAnotherSoundStopsThePreviousOne() throws {
        let engine = makeEngine()
        let a = try makeSound(id: 1, name: "a.wav")
        let b = try makeSound(id: 2, name: "b.wav")

        engine.play(sound: a)
        engine.play(sound: b)

        XCTAssertEqual(engine.state, .playing(soundId: 2))
        XCTAssertEqual(players.count, 2)
        XCTAssertEqual(players[0].stopCount, 1, "前一個音效必須被停掉")
        XCTAssertFalse(players[0].isPlaying)
        XCTAssertTrue(players[1].isPlaying)
    }

    func testToggleOnSameSoundPausesAndResumes() throws {
        let engine = makeEngine()
        let sound = try makeSound(id: 7, name: "c.wav")

        engine.toggle(sound: sound)
        XCTAssertEqual(engine.state, .playing(soundId: 7))

        engine.toggle(sound: sound)
        XCTAssertEqual(engine.state, .paused(soundId: 7))

        engine.toggle(sound: sound)
        XCTAssertEqual(engine.state, .playing(soundId: 7))
        XCTAssertEqual(players.count, 1, "暫停後繼續不應該重新建立播放器")
    }

    func testToggleOnDifferentSoundStartsTheNewOne() throws {
        let engine = makeEngine()
        let a = try makeSound(id: 1, name: "a.wav")
        let b = try makeSound(id: 2, name: "b.wav")

        engine.play(sound: a)
        engine.pause()
        engine.toggle(sound: b)

        XCTAssertEqual(engine.state, .playing(soundId: 2))
    }

    func testMissingFileFailsWithoutCrashing() {
        let engine = makeEngine()
        let sound = Sound(id: 9,
                          libraryId: 1,
                          filePath: "/nowhere/gone.wav",
                          relativePath: "gone.wav",
                          filename: "gone.wav",
                          fileExtension: "wav")

        engine.play(sound: sound)

        XCTAssertEqual(engine.state, .failed(soundId: 9, reason: "檔案不在了"))
        XCTAssertTrue(players.isEmpty, "檔案不存在時不該建立播放器")
    }

    func testPlayerRefusingToPlayIsReportedNotSwallowed() throws {
        var created: [FakePlayer] = []
        let engine = AudioPreviewEngine { _ in
            let player = FakePlayer()
            player.shouldFailToPlay = true
            created.append(player)
            return player
        }
        let sound = try makeSound(id: 3, name: "d.wav")

        engine.play(sound: sound)

        XCTAssertEqual(engine.state, .failed(soundId: 3, reason: "無法播放這個檔案"))
        XCTAssertEqual(created.count, 1)
    }

    func testSeekClampsToBounds() throws {
        let engine = makeEngine()
        let sound = try makeSound(id: 1, name: "a.wav")
        engine.play(sound: sound)

        engine.seek(to: 0.5)
        XCTAssertEqual(engine.currentTime, 1.0, accuracy: 0.001)

        engine.seek(to: 5)
        XCTAssertEqual(engine.currentTime, 2.0, accuracy: 0.001)

        engine.seek(to: -3)
        XCTAssertEqual(engine.currentTime, 0.0, accuracy: 0.001)
    }

    func testVolumeReachesThePlayer() throws {
        let engine = makeEngine()
        engine.volume = 0.25
        let sound = try makeSound(id: 1, name: "a.wav")
        engine.play(sound: sound)

        XCTAssertEqual(players[0].volume, 0.25, accuracy: 0.001)
    }

    func testStopClearsEverything() throws {
        let engine = makeEngine()
        let sound = try makeSound(id: 1, name: "a.wav")
        engine.play(sound: sound)

        engine.stop()

        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.currentTime, 0)
        XCTAssertEqual(engine.duration, 0)
        XCTAssertEqual(players[0].stopCount, 1)
    }

    func testProgressIsZeroWithoutDuration() {
        let engine = makeEngine()
        XCTAssertEqual(engine.progress, 0)
    }
}
