import Foundation

/// 訊號的形狀。這是量測能誠實支持的最粗粒度描述——
/// 它能分辨「單一撞擊」與「持續噪聲」，但分不出「金屬」與「木頭」。
/// 材質留給路徑證據，不在這裡猜。
enum SoundShape: String, Equatable, Codable {
    /// 單一短促事件，能量集中在開頭。
    case impulse
    /// 多次分離的撞擊。
    case rhythmic
    /// 持續且有明確音高。
    case tonal
    /// 持續且接近寬頻噪聲。
    case noise
    /// 頻譜重心明顯移動（掃頻、whoosh、riser）。
    case sweep
    /// 全靜音。是事實，不是失敗。
    case silent
    /// 量測結果不指向任何一種。說不知道好過硬選一個。
    case ambiguous
}

/// 從量測值推出的證據。所有欄位都可以回溯到具體數字。
struct AcousticEvidence: Equatable {
    var shape: SoundShape
    /// 只包含量測直接支持的標籤，不含任何材質或情境的想像。
    var tags: [String]
    /// 形狀判斷本身的把握度 0–1。
    var confidence: Double
    /// 給審核介面看的量測摘要。人可以據此判斷引擎憑什麼這樣說。
    var notes: [String]
}

/// 把 `AcousticFeatures` 轉成形狀與標籤。
///
/// 門檻全部集中在 `Thresholds`，方便日後用真實素材校準；
/// 散落在判斷式裡的魔術數字沒辦法被檢討。
enum AcousticClassifier {

    enum Thresholds {
        /// 重心每秒移動超過這個值才算掃頻。
        static let sweepSlope: Float = 800
        /// 太短的素材算不出可信的斜率。
        static let sweepMinimumDuration: Double = 0.25
        /// 這個數量以上的起音點視為節奏性。
        static let rhythmicOnsets = 3
        /// 脈衝的波峰因數下限。
        static let impulseCrest: Float = 4
        /// 脈衝的延音比例上限。
        static let impulseSustain: Float = 0.45
        /// 持續音的延音比例下限。
        static let sustainedSustain: Float = 0.6
        /// 低於此平坦度視為調性。
        static let tonalFlatness: Float = 0.15
        /// 高於此平坦度視為噪聲。
        static let noiseFlatness: Float = 0.25

        static let brightCentroid: Float = 3000
        static let darkCentroid: Float = 700
        static let sharpAttack: Double = 0.02
        static let dullAttack: Double = 0.15
        static let reverberantDecay: Double = 0.8
        static let dryDecay: Double = 0.15
        static let heavyLowRatio: Float = 0.55
        static let shortDuration: Double = 1
        static let longDuration: Double = 5
    }

    static func evidence(from features: AcousticFeatures) -> AcousticEvidence {
        guard !features.isSilent else {
            return AcousticEvidence(shape: .silent,
                                    tags: [],
                                    confidence: 1,
                                    notes: ["整段皆為靜音"])
        }

        let (shape, confidence) = classify(features)
        return AcousticEvidence(shape: shape,
                                tags: tags(for: features, shape: shape),
                                confidence: confidence,
                                notes: notes(for: features))
    }

    // MARK: - 形狀

    /// 判斷順序有意義：掃頻的重心變化會蓋過其他特徵，必須先判；
    /// 節奏性要在脈衝之前判，否則連續撞擊會被當成單一撞擊。
    private static func classify(_ features: AcousticFeatures) -> (SoundShape, Double) {
        if abs(features.centroidSlope) >= Thresholds.sweepSlope,
           features.duration >= Thresholds.sweepMinimumDuration {
            // 斜率越陡越確定，但不讓它無上限地接近 1。
            let magnitude = Double(abs(features.centroidSlope) / Thresholds.sweepSlope)
            return (.sweep, min(0.9, 0.55 + 0.1 * magnitude))
        }

        if features.onsetCount >= Thresholds.rhythmicOnsets,
           features.sustainRatio < Thresholds.sustainedSustain {
            return (.rhythmic, 0.75)
        }

        if features.crestFactor >= Thresholds.impulseCrest,
           features.sustainRatio <= Thresholds.impulseSustain {
            let margin = Double(features.crestFactor / Thresholds.impulseCrest)
            return (.impulse, min(0.9, 0.6 + 0.1 * margin))
        }

        if features.sustainRatio >= Thresholds.sustainedSustain {
            if features.spectralFlatness <= Thresholds.tonalFlatness {
                return (.tonal, 0.8)
            }
            if features.spectralFlatness >= Thresholds.noiseFlatness {
                return (.noise, 0.75)
            }
            // 持續但介於調性與噪聲之間——這是真的模糊，不要硬選。
            return (.ambiguous, 0.35)
        }

        return (.ambiguous, 0.3)
    }

    // MARK: - 標籤

    /// 只發出量測直接支持的詞。材質（metal/wood/glass）一律不在這裡產生。
    private static func tags(for features: AcousticFeatures, shape: SoundShape) -> [String] {
        var tags: [String] = []

        // 時長是定義性的對應，沒有詮釋空間。
        if features.duration < Thresholds.shortDuration {
            tags.append("short")
        } else if features.duration <= Thresholds.longDuration {
            tags.append("medium")
        } else {
            tags.append("long")
        }

        if features.onsetCount <= 1 {
            tags.append("single")
        } else if features.onsetCount >= Thresholds.rhythmicOnsets {
            tags.append("repeating")
        }

        if features.sustainRatio >= Thresholds.sustainedSustain {
            tags.append("sustained")
        }

        // 亮／暗對應頻譜重心，是音訊領域的標準用法。
        if features.spectralCentroid >= Thresholds.brightCentroid {
            tags.append("bright")
        } else if features.spectralCentroid > 0, features.spectralCentroid <= Thresholds.darkCentroid {
            tags.append("dark")
        }

        // 銳利／鈍對應起音時間。持續音沒有明確起音，不套這組詞。
        if shape == .impulse || shape == .rhythmic {
            if features.attackTime <= Thresholds.sharpAttack {
                tags.append("sharp")
            } else if features.attackTime >= Thresholds.dullAttack {
                tags.append("dull")
            }

            // 撞擊之後的尾巴長度就是殘響的量測定義。
            if features.decayTime >= Thresholds.reverberantDecay {
                tags.append("reverberant")
                tags.append("resonant")
            } else if features.decayTime <= Thresholds.dryDecay {
                tags.append("dry")
            }
        }

        // 低頻主導 + 夠大的峰值＝聽感上的「重」。這是啟發式，不是定義，
        // 所以門檻訂得保守，寧可漏標也不亂標。
        if features.lowEnergyRatio >= Thresholds.heavyLowRatio, features.peak >= 0.3 {
            tags.append("heavy")
        }

        return tags
    }

    // MARK: - 摘要

    /// 給 M11 審核介面：讓人一眼看到引擎憑什麼這樣判斷。
    private static func notes(for features: AcousticFeatures) -> [String] {
        var notes: [String] = []
        notes.append(String(format: "時長 %.2f 秒", features.duration))
        notes.append(String(format: "波峰因數 %.1f", features.crestFactor))
        notes.append(String(format: "起音 %.0f ms、衰減 %.2f 秒",
                            features.attackTime * 1000, features.decayTime))
        notes.append(String(format: "延音比例 %.0f%%", features.sustainRatio * 100))
        notes.append(String(format: "頻譜重心 %.0f Hz、平坦度 %.2f",
                            features.spectralCentroid, features.spectralFlatness))
        notes.append(String(format: "低/中/高頻能量 %.0f%% / %.0f%% / %.0f%%",
                            features.lowEnergyRatio * 100,
                            features.midEnergyRatio * 100,
                            features.highEnergyRatio * 100))
        if abs(features.centroidSlope) >= 100 {
            notes.append(String(format: "重心斜率 %+.0f Hz/秒", features.centroidSlope))
        }
        notes.append("起音點 \(features.onsetCount) 次")
        return notes
    }
}
