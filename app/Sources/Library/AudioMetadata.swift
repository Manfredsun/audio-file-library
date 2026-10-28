import AVFoundation
import Foundation

/// 從音訊檔讀出技術資訊。
///
/// 這一層只讀，不解碼整個檔案，也不寫任何東西回磁碟。
struct AudioMetadata: Equatable {
    var duration: Double?
    var sampleRate: Int?
    var bitDepth: Int?
    var channelCount: Int?
}

enum AudioMetadataExtractor {

    /// 支援的副檔名。FLAC 視系統支援而定，讀不到時會被標成 unsupported 而不是讓掃描中斷。
    static let supportedExtensions: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "flac"]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// 讀取失敗回傳 nil。一個壞檔案不能弄垮整個掃描（CLAUDE.md §39）。
    static func extract(from url: URL) -> AudioMetadata? {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.fileFormat
            let sampleRate = format.sampleRate

            var duration: Double?
            if sampleRate > 0 {
                duration = Double(file.length) / sampleRate
            }

            let bits = Int(format.streamDescription.pointee.mBitsPerChannel)

            return AudioMetadata(
                duration: duration,
                sampleRate: sampleRate > 0 ? Int(sampleRate.rounded()) : nil,
                bitDepth: bits > 0 ? bits : nil,
                channelCount: Int(format.channelCount))
        } catch {
            AppLog.library.debug("讀不到音訊詮釋資料：\(url.lastPathComponent, privacy: .public)")
            return nil
        }
    }

    /// 穩定的檔案身分：device id + inode。
    /// 改名或搬移之後仍然相同，是 ROADMAP §29 要的那個識別碼。
    static func fileIdentifier(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            return nil
        }
        return "\(device.uint64Value):\(inode.uint64Value)"
    }
}
