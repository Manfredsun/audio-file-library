import AVFoundation
import Foundation

/// 播放器介面。抽成 protocol 是為了讓引擎的狀態機能在沒有音訊裝置的情況下測試。
/// `AVAudioPlayer` 的簽章剛好完全吻合，所以不需要任何轉接程式碼。
protocol AudioPlayback: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    var isPlaying: Bool { get }
    var volume: Float { get set }
    @discardableResult func play() -> Bool
    func pause()
    func stop()
}

extension AVAudioPlayer: AudioPlayback {}

enum PreviewState: Equatable {
    case idle
    case playing(soundId: Int64)
    case paused(soundId: Int64)
    case failed(soundId: Int64, reason: String)

    var soundId: Int64? {
        switch self {
        case .idle: return nil
        case .playing(let id), .paused(let id): return id
        case .failed(let id, _): return id
        }
    }

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
}

/// 音訊預覽。
///
/// 產品上最重要的行為（ROADMAP §32）：
///     選 A → 播 A；選 B → 立刻停 A、播 B。
/// 沒有淡出、沒有等待、沒有排隊。
@MainActor
final class AudioPreviewEngine: ObservableObject {

    @Published private(set) var state: PreviewState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var volume: Float = 0.8 {
        didSet {
            player?.volume = volume
            UserDefaults.standard.set(volume, forKey: Self.volumeKey)
        }
    }

    private static let volumeKey = "preview.volume"

    private var player: AudioPlayback?
    private var ticker: Timer?
    private let makePlayer: (URL) throws -> AudioPlayback

    init(makePlayer: @escaping (URL) throws -> AudioPlayback = { try AVAudioPlayer(contentsOf: $0) }) {
        self.makePlayer = makePlayer
        if let saved = UserDefaults.standard.object(forKey: Self.volumeKey) as? Float {
            volume = saved
        }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    // MARK: - 播放

    func play(sound: Sound) {
        guard let soundId = sound.id else { return }

        // 先停掉上一個，不管它是什麼狀態。延遲比優雅重要。
        stopInternal()

        let url = URL(fileURLWithPath: sound.filePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            state = .failed(soundId: soundId, reason: "檔案不在了")
            AppLog.app.error("預覽失敗，檔案不存在：\(sound.filename, privacy: .public)")
            return
        }

        do {
            let player = try makePlayer(url)
            player.volume = volume
            self.player = player
            duration = player.duration
            currentTime = 0

            guard player.play() else {
                state = .failed(soundId: soundId, reason: "無法播放這個檔案")
                return
            }
            state = .playing(soundId: soundId)
            startTicker()
        } catch {
            state = .failed(soundId: soundId, reason: "讀不到音訊")
            AppLog.app.error("預覽失敗 \(sound.filename, privacy: .public)：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 同一個音效時切換播放／暫停；不同音效則直接播新的。
    func toggle(sound: Sound) {
        guard let soundId = sound.id else { return }

        switch state {
        case .playing(let playing) where playing == soundId:
            pause()
        case .paused(let paused) where paused == soundId:
            resume()
        default:
            play(sound: sound)
        }
    }

    func pause() {
        guard let player, case .playing(let soundId) = state else { return }
        player.pause()
        stopTicker()
        state = .paused(soundId: soundId)
    }

    func resume() {
        guard let player, case .paused(let soundId) = state else { return }
        guard player.play() else {
            state = .failed(soundId: soundId, reason: "無法繼續播放")
            return
        }
        state = .playing(soundId: soundId)
        startTicker()
    }

    func stop() {
        stopInternal()
        state = .idle
    }

    /// 依比例跳轉（0–1）。
    func seek(to fraction: Double) {
        guard let player, duration > 0 else { return }
        let target = min(max(0, fraction), 1) * duration
        player.currentTime = target
        currentTime = target
    }

    // MARK: - 內部

    private func stopInternal() {
        stopTicker()
        player?.stop()
        player = nil
        currentTime = 0
        duration = 0
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// 用輪詢判斷播完，而不是 AVAudioPlayerDelegate——
    /// delegate 回呼的執行緒不保證，為了一件小事引入跨執行緒問題不划算。
    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime

        if !player.isPlaying, case .playing(let soundId) = state {
            // 已經播到底
            stopInternal()
            state = .idle
            AppLog.app.debug("預覽結束 sound=\(soundId, privacy: .public)")
        }
    }
}
