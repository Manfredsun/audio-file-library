import Foundation
import GRDB

struct WaveformRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "waveform_cache"

    var soundId: Int64
    var waveformData: Data
    var resolution: Int
    var generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case soundId = "sound_id"
        case waveformData = "waveform_data"
        case resolution
        case generatedAt = "generated_at"
    }
}

/// 波形的產生與快取。
///
/// 不在畫面重繪時解碼音訊（CLAUDE.md §24）：資料只算一次，存進資料庫，
/// 之後永遠從快取讀。這個型別不綁 main actor，可以在背景執行緒被呼叫。
struct WaveformStore {
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// 只讀快取，不產生。用於畫面需要立即知道「有沒有」的場合。
    func cached(soundId: Int64) -> [UInt8]? {
        guard let record = try? database.writer.read({ db in
            try WaveformRecord.fetchOne(db, key: soundId)
        }) else { return nil }
        return [UInt8](record.waveformData)
    }

    /// 取得波形：先找快取，沒有才解碼並寫回快取。
    func peaks(soundId: Int64, url: URL) -> [UInt8]? {
        if let cached = cached(soundId: soundId) { return cached }

        guard let peaks = WaveformGenerator.generate(url: url) else { return nil }

        let record = WaveformRecord(soundId: soundId,
                                    waveformData: Data(peaks),
                                    resolution: WaveformGenerator.storedResolution,
                                    generatedAt: Date())
        try? database.writer.write { db in
            try record.insert(db, onConflict: .replace)
        }
        return peaks
    }

    /// 檔案被取代時清掉舊波形。
    func invalidate(soundId: Int64) {
        try? database.writer.write { db in
            _ = try WaveformRecord.deleteOne(db, key: soundId)
        }
    }
}
