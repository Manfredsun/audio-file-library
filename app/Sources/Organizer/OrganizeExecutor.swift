import Foundation

/// 整理的執行結果。
/// 一筆成功建立的連結。編號要寫回資料庫凍結，靠的就是這份清單。
struct OrganizeLinked: Equatable {
    var soundId: Int64
    var destination: String
}

struct OrganizeOutcome: Equatable {
    var batchId: Int64?
    var linkedItems: [OrganizeLinked] = []
    var linked: Int { linkedItems.count }
    /// 目標已經存在，跳過。**不是錯誤**，而且絕不覆蓋（安全模型第二條）。
    var skipped: Int = 0
    var failed: Int = 0
    var cancelled: Bool = false
}

/// 執行的進度。
struct OrganizeProgress: Equatable {
    enum Phase: String, Equatable {
        case idle, running, finished, cancelled
    }
    var phase: Phase = .idle
    var total = 0
    var completed = 0
    var skipped = 0
    var failed = 0
    var currentName = ""

    var isRunning: Bool { phase == .running }
    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed + skipped + failed) / Double(total))
    }

    var summary: String {
        switch phase {
        case .idle: return ""
        case .running: return L10n.tr("建立連結中 %@/%@", String(describing: completed + skipped + failed), String(describing: total))
        case .cancelled: return L10n.tr("已中止，已建立 %@ 個連結（可撤銷）", String(describing: completed))
        case .finished:
            var parts = [L10n.tr("organize.created", completed)]
            if skipped > 0 { parts.append(L10n.tr("%@ 個目標已存在，跳過", String(describing: skipped))) }
            if failed > 0 { parts.append(L10n.tr("%@ 個失敗", String(describing: failed))) }
            return parts.joined(separator: L10n.tr("separator.list"))
        }
    }
}

/// 檔案系統的動作。抽成協定是為了讓測試在臨時資料夾裡跑真的 `link()`——
/// 假的檔案系統測不出硬連結真正會踩到的東西（同碟限制、大小寫、既有檔案）。
protocol OrganizeFileSystem {
    func fileExists(at path: String) -> Bool
    func link(from source: String, to destination: String, root: String) throws -> String
    func removeVerifiedLink(at path: String, root: String, identifier: String, recordRecovery: (String) throws -> Void) throws -> OrganizeFileSafety.Removal
}

struct RealOrganizeFileSystem: OrganizeFileSystem {
    func fileExists(at path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
    func link(from source: String, to destination: String, root: String) throws -> String {
        try OrganizeFileSafety.link(source: source, destination: destination, root: root)
    }
    func removeVerifiedLink(at path: String, root: String, identifier: String, recordRecovery: (String) throws -> Void) throws -> OrganizeFileSafety.Removal {
        try OrganizeFileSafety.remove(path: path, root: root, expected: identifier, recordRecovery: recordRecovery)
    }
}

struct OrganizeUndoOutcome: Equatable {
    var removed = 0
    var missing = 0
    var skippedChanged = 0
    var failed = 0
    var recoveryPaths: [String] = []

    var summary: String {
        L10n.tr("已移除 %@ 個連結，%@ 個已不存在，%@ 個因身分或位置改變而保留，%@ 個未完成（可重試）", String(describing: removed), String(describing: missing), String(describing: skippedChanged), String(describing: failed))
            + (recoveryPaths.isEmpty ? "" : L10n.tr("。已保留檔案：") + recoveryPaths.joined(separator: L10n.tr("separator.list")))
    }
}

/// 逐檔建立硬連結，每一筆都寫進 journal。
///
/// **三條不可越過的線**（dev-plan §8）：
/// 1. 永不刪除原始檔案。
/// 2. 永不覆蓋既有檔案——目標存在就跳過並標記。
/// 3. 執行前必須有人看過 manifest；這一層不提供「分析完直接整理」的入口。
///
/// 撤銷靠 journal：只刪這個 batch 記錄過的路徑。沒有紀錄就不刪任何東西。
enum OrganizeExecutor {

    /// 一筆待執行的連結。
    struct Job: Equatable {
        var soundId: Int64
        var sourcePath: String
        /// 相對於整理樹根目錄的路徑，例如 `Drums/Kick/Boom Bap Kick dirt 01.wav`。
        var destination: String
    }

    /// 檔名裡不能出現的字元。
    ///
    /// `/` 是路徑分隔符，`:` 在 Finder 裡會顯示成 `/`（HFS 的歷史包袱），
    /// 兩個都會讓檔案落在意料之外的位置。
    static let illegalCharacters = CharacterSet(charactersIn: "/:")

    /// 執行前的檢查。回傳有問題的那幾筆，**其餘照跑**。
    ///
    /// 大小寫要一起比：HFS+ 不分大小寫，`Kick 01.wav` 與 `kick 01.wav`
    /// 是同一個檔案，用區分大小寫的比對會讓第二個靜默覆蓋第一個。
    static func problems(in jobs: [Job]) -> [Int64: String] {
        var seen: [String: Int64] = [:]
        var problems: [Int64: String] = [:]
        for job in jobs {
            let name = (job.destination as NSString).lastPathComponent
            if !OrganizeFileSafety.validRelativePath(job.destination) || name.rangeOfCharacter(from: illegalCharacters) != nil {
                problems[job.soundId] = L10n.tr("檔名含有不能用的字元")
                continue
            }
            let key = job.destination.lowercased()
            if let other = seen[key] {
                problems[job.soundId] = L10n.tr("跟另一筆的目標相同")
                problems[other] = L10n.tr("跟另一筆的目標相同")
                continue
            }
            seen[key] = job.soundId
        }
        return problems
    }

    /// 執行。`shouldContinue` 回 false 就停下來——已經建立的連結留著，可以撤銷。
    ///
    /// `onProgress` 每完成一筆呼叫一次。
    static func run(_ jobs: [Job],
                    root: String,
                    scope: String,
                    fileSystem: OrganizeFileSystem = RealOrganizeFileSystem(),
                    journal: OrganizeJournalWriting,
                    shouldContinue: () -> Bool = { true },
                    onProgress: (OrganizeProgress) -> Void = { _ in }) -> OrganizeOutcome {

        var outcome = OrganizeOutcome()
        guard let root = try? OrganizeFileSafety.canonicalRoot(root) else {
            outcome.failed = jobs.count
            return outcome
        }
        let blocked = problems(in: jobs)
        let runnable = jobs.filter { blocked[$0.soundId] == nil }
        outcome.failed = blocked.count
        guard runnable.isEmpty == false else { return outcome }

        var progress = OrganizeProgress(phase: .running, total: runnable.count)
        onProgress(progress)

        guard let batchId = try? journal.beginBatch(scope: scope, root: root) else {
            outcome.failed = runnable.count
            return outcome
        }
        outcome.batchId = batchId

        for job in runnable {
            guard shouldContinue() else {
                outcome.cancelled = true
                progress.phase = .cancelled
                onProgress(progress)
                break
            }

            let destination = (root as NSString).appendingPathComponent(job.destination)
            progress.currentName = (job.destination as NSString).lastPathComponent

            // 目標已經存在就跳過。**絕不覆蓋**（安全模型第二條）。
            if fileSystem.fileExists(at: destination) {
                outcome.skipped += 1
                progress.skipped += 1
                onProgress(progress)
                continue
            }

            do {
                let identity = try fileSystem.link(from: job.sourcePath, to: destination, root: root)
                // 先建連結再記帳：記了卻沒建，撤銷時會去刪一個不是我們建的檔案。
                // 反過來（建了沒記）最壞是留下一個孤兒連結，遠比誤刪安全。
                try journal.record(batchId: batchId, soundId: job.soundId, linkPath: destination, fileIdentifier: identity)
                outcome.linkedItems.append(OrganizeLinked(soundId: job.soundId,
                                                          destination: job.destination))
                progress.completed += 1
            } catch {
                outcome.failed += 1
                progress.failed += 1
            }
            onProgress(progress)
        }

        try? journal.finishBatch(batchId, linkCount: outcome.linked)
        if progress.phase == .running {
            progress.phase = .finished
            onProgress(progress)
        }
        return outcome
    }

    /// 撤銷一個批次：刪掉**這個批次記錄過的**連結，一個都不多。
    ///
    /// 原檔從未被動過，而且刪掉一個硬連結不會刪到資料（只有最後一個連結被刪才會），
    /// 所以撤銷是真的乾淨。
    @discardableResult
    static func undo(batchId: Int64,
                     fileSystem: OrganizeFileSystem = RealOrganizeFileSystem(),
                     journal: OrganizeJournalWriting) -> OrganizeUndoOutcome {
        var outcome = OrganizeUndoOutcome()
        do {
            let entries = try journal.entries(batchId: batchId)
            for entry in entries {
                if entry.undoState == "removing" {
                    outcome.failed += 1
                    if let path = entry.recoveryPath { outcome.recoveryPaths.append(path) }
                    continue
                }
                guard ["pending", "failed"].contains(entry.undoState) else { continue }
                do {
                    guard try journal.claimUndo(entryId: entry.id) else { continue }
                    let state: String
                    var recoveryPath: String?
                    if let identity = entry.fileIdentifier {
                        switch try fileSystem.removeVerifiedLink(at: entry.path, root: entry.root, identifier: identity, recordRecovery: { path in
                            try journal.recordUndo(entryId: entry.id, state: "removing", recoveryPath: path)
                        }) {
                        case .removed: outcome.removed += 1; state = "removed"
                        case .missing: outcome.missing += 1; state = "missing"
                        case .changed: outcome.skippedChanged += 1; state = "changed"
                        case .preserved(let path):
                            outcome.skippedChanged += 1
                            outcome.recoveryPaths.append(path)
                            recoveryPath = path
                            state = "preserved"
                        }
                    } else {
                        // Legacy entries without an identity are never safe to delete.
                        outcome.skippedChanged += 1
                        state = "changed"
                    }
                    // A failed journal update leaves 'removing': never delete it again automatically.
                    do { try journal.recordUndo(entryId: entry.id, state: state, recoveryPath: recoveryPath) }
                    catch { outcome.failed += 1 }
                } catch {
                    outcome.failed += 1
                    try? journal.recordUndo(entryId: entry.id, state: "failed", recoveryPath: nil)
                }
            }
            try journal.markUndone(batchId)
        } catch { outcome.failed += 1 }
        return outcome
    }
}

/// 跨執行緒的中止旗標。
///
/// 執行跑在背景，中止按鈕在主執行緒，兩邊都要碰到同一個布林值。
/// 用鎖而不是 @MainActor 的屬性：執行迴圈每一筆都要問一次，
/// 每次都跳回主執行緒問會把背景工作變成主執行緒工作。
final class OrganizeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}

/// 跨組累加的計數。理由同上。
final class OrganizeTotals: @unchecked Sendable {
    private let lock = NSLock()
    private var linked = 0
    private var skipped = 0
    private var failed = 0

    func add(linked: Int, skipped: Int, failed: Int) {
        lock.lock()
        self.linked += linked; self.skipped += skipped; self.failed += failed
        lock.unlock()
    }

    func snapshot() -> (linked: Int, skipped: Int, failed: Int) {
        lock.lock(); defer { lock.unlock() }
        return (linked, skipped, failed)
    }
}
