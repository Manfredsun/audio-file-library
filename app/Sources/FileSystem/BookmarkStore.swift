import Foundation

/// 資料夾書籤。
///
/// ROADMAP §20 原本指定 security-scoped bookmarks，但那需要 App Sandbox；
/// D-002 決定不啟用沙盒，所以這裡用一般書籤（見 DECISIONS D-010）。
/// 一般書籤同樣能在使用者搬移或改名資料夾之後解析回同一個目標，
/// 差別只在於它不攜帶沙盒的權限授與——非沙盒 App 本來就不需要。
enum BookmarkStore {

    enum BookmarkError: Error, LocalizedError {
        case cannotCreate(String)
        case cannotResolve(String)

        var errorDescription: String? {
            switch self {
            case .cannotCreate(let path):  return "無法為 \(path) 建立書籤"
            case .cannotResolve(let name): return "無法解析 \(name) 的書籤"
            }
        }
    }

    /// Resolve existing ancestors even when the final file/folder has moved away.
    /// This keeps macOS aliases (/var and /private/var) consistent during relinking.
    static func normalizedURL(_ url: URL) -> URL {
        var ancestor = url.standardizedFileURL
        var suffix: [String] = []
        while ancestor.path != "/" && !FileManager.default.fileExists(atPath: ancestor.path) {
            suffix.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var normalized = ancestor.resolvingSymlinksInPath().standardizedFileURL
        for component in suffix.reversed() { normalized.appendPathComponent(component) }
        return normalized
    }

    static func makeBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(options: [],
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        } catch {
            throw BookmarkError.cannotCreate(url.path)
        }
    }

    struct Resolved {
        let url: URL
        /// 書籤過期代表目標可能被搬移過，應該重新產生一份。
        let isStale: Bool
    }

    static func resolve(_ data: Data) throws -> Resolved {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data,
                              options: [],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            return Resolved(url: url, isStale: isStale)
        } catch {
            throw BookmarkError.cannotResolve(error.localizedDescription)
        }
    }

    /// 目標是否為現存的資料夾。外接碟拔掉時這裡會是 false，那是正常狀態，不是錯誤。
    static func isReachableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
