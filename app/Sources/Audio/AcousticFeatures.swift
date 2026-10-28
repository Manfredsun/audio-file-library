import Foundation

/// 直接從音訊訊號量測出來的特徵。
///
/// 每一個欄位都是計算的結果，不是任何模型的推論。這是 D-013 之後的核心約束：
/// 引擎可以說「我不知道」，但不可以編造。量測值不會編造。
struct AcousticFeatures: Equatable, Codable {
    var duration: Double
    var sampleRate: Double
    var channelCount: Int

    /// 全檔最大絕對振幅 0–1。
    var peak: Float
    /// 全檔均方根振幅 0–1。
    var rms: Float
    /// peak / rms。脈衝類很高（撞擊 > 8），持續音很低（drone < 4）。
    var crestFactor: Float

    /// 從起音到峰值的秒數。打擊極短，弓弦與掃頻長。
    var attackTime: Double
    /// 峰值之後掉到 −20 dB 所需的秒數。殘響會拉長它。
    var decayTime: Double
    /// 包絡在峰值 −20 dB 以上的幀數比例。持續音接近 1，單一撞擊接近 0。
    var sustainRatio: Float

    /// 過零率（每秒次數 ÷ 取樣率，0–1）。噪聲高，低頻正弦低。
    var zeroCrossingRate: Float
    /// 頻譜重心（Hz）。bright／dark 標籤的量測基礎。
    var spectralCentroid: Float
    /// 85% 能量的滾降頻率（Hz）。
    var spectralRolloff: Float
    /// 頻譜平坦度 0–1。接近 1 像白噪，接近 0 是純音。
    var spectralFlatness: Float

    /// < 250 Hz 的能量占比。
    var lowEnergyRatio: Float
    /// 250 Hz – 4 kHz 的能量占比。
    var midEnergyRatio: Float
    /// > 4 kHz 的能量占比。
    var highEnergyRatio: Float

    /// 頻譜重心隨時間的線性斜率（Hz/秒）。正值＝上揚掃頻，負值＝下墜。
    var centroidSlope: Float
    /// 偵測到的起音點數量。1 = 單一事件，多個 = 連續或節奏性。
    var onsetCount: Int

    var leadingSilence: Double
    var trailingSilence: Double

    /// 量測出來的 BPM。nil 代表沒有足夠的節奏證據——不猜。
    var tempo: Double?
    /// 節拍量測的把握度 0–1。兩種獨立方法一致時才高。
    var tempoConfidence: Double
    /// 聲學上像不像 loop：夠長、有多次起音、能量持續。
    var isLoopLike: Bool

    /// 全靜音檔案的合法結果。靜音是事實，不是失敗。
    static func silent(duration: Double, sampleRate: Double, channelCount: Int) -> AcousticFeatures {
        AcousticFeatures(duration: duration,
                         sampleRate: sampleRate,
                         channelCount: channelCount,
                         peak: 0,
                         rms: 0,
                         crestFactor: 0,
                         attackTime: 0,
                         decayTime: 0,
                         sustainRatio: 0,
                         zeroCrossingRate: 0,
                         spectralCentroid: 0,
                         spectralRolloff: 0,
                         spectralFlatness: 0,
                         lowEnergyRatio: 0,
                         midEnergyRatio: 0,
                         highEnergyRatio: 0,
                         centroidSlope: 0,
                         onsetCount: 0,
                         leadingSilence: duration,
                         trailingSilence: duration,
                         tempo: nil,
                         tempoConfidence: 0,
                         isLoopLike: false)
    }

    var isSilent: Bool { peak <= 0 }
}
