import Darwin
import Foundation

/// Only regular files with the recorded identity may be unlinked. Directory descriptors
/// keep traversal inside the selected tree and never follow symbolic links.
enum OrganizeFileSafety {
    enum Removal { case removed, missing, changed, preserved(String) }

    static func canonicalRoot(_ root: String) throws -> String {
        let url = URL(fileURLWithPath: root).standardizedFileURL
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue, url.lastPathComponent != "/" else { throw failure() }
        return parent.appendingPathComponent(url.lastPathComponent).path
    }

    static func validRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.utf8.contains(0)
            && !path.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    static func link(source: String, destination: String, root: String) throws -> String {
        var sourceStat = stat()
        guard lstat(source, &sourceStat) == 0,
              sourceStat.st_mode & S_IFMT == S_IFREG else { throw failure() }
        return try withParent(path: destination, root: root, create: true) { fd, name in
            guard linkat(AT_FDCWD, source, fd, name, 0) == 0 else { throw failure() }
            var info = stat()
            guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                  info.st_mode & S_IFMT == S_IFREG,
                  info.st_dev == sourceStat.st_dev, info.st_ino == sourceStat.st_ino else { throw failure() }
            return identifier(info)
        }
    }

    static func remove(path: String, root: String, expected: String, recordRecovery: (String) throws -> Void = { _ in }) throws -> Removal {
        do {
            return try withParent(path: path, root: root, create: false) { fd, name in
                var info = stat()
                guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                    if errno == ENOENT { return .missing }
                    throw failure()
                }
                // Preserve directories, symlinks, replacements, and the last surviving copy.
                guard info.st_mode & S_IFMT == S_IFREG,
                      identifier(info) == expected, info.st_nlink > 1 else { return .changed }
                // Claim the directory entry atomically before checking it again. A
                // preflight stat alone can delete a replacement swapped in before unlink.
                let quarantine = ".foley-undo-" + UUID().uuidString
                guard mkdirat(fd, quarantine, 0o700) == 0 else { throw failure() }
                let holding = openat(fd, quarantine, O_SEARCH | O_NOFOLLOW)
                guard holding >= 0 else { throw failure() }
                defer {
                    close(holding)
                    _ = unlinkat(fd, quarantine, AT_REMOVEDIR) // succeeds only if empty
                }
                var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                guard fcntl(fd, F_GETPATH, &buffer) == 0 else { throw failure() }
                let recoveryPath = String(cString: buffer) + "/" + quarantine + "/item"
                try recordRecovery(recoveryPath)
                guard renameatx_np(fd, name, holding, "item", UInt32(RENAME_EXCL)) == 0 else { throw failure() }
                var claimed = stat()
                let matches = fstatat(holding, "item", &claimed, AT_SYMLINK_NOFOLLOW) == 0
                    && claimed.st_mode & S_IFMT == S_IFREG
                    && identifier(claimed) == expected && claimed.st_nlink > 1
                if matches && unlinkat(holding, "item", 0) == 0 { return .removed }
                let removalError = errno
                // Never overwrite something placed at the original name while claimed.
                if renameatx_np(holding, "item", fd, name, UInt32(RENAME_EXCL)) != 0 {
                    return .preserved(recoveryPath)
                }
                if matches { throw failure(removalError) }
                return .changed
            }
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            // An offline library is retryable. Only missing descendants of a verified
            // reachable root are terminal; otherwise an offline drive would lose undo.
            try withParent(path: root + "/.undo-root-check", root: root, create: false) { _, _ in () }
            return .missing
        }
    }

    private static func identifier(_ info: stat) -> String { "\(UInt32(bitPattern: info.st_dev)):\(info.st_ino)" }

    private static func failure(_ code: Int32 = errno) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code == 0 ? EINVAL : code))
    }

    private static func withParent<T>(path: String, root: String, create: Bool,
                                      body: (Int32, String) throws -> T) throws -> T {
        guard root.hasPrefix("/"), path.hasPrefix(root + "/") else { throw failure(EINVAL) }
        let relative = String(path.dropFirst(root.count + 1))
        guard validRelativePath(relative) else { throw failure(EINVAL) }
        let rootURL = URL(fileURLWithPath: root)
        // Foundation intentionally preserves macOS system aliases such as /var.
        // Resolve the existing parent with POSIX realpath before opening components.
        guard let parent = realpath(rootURL.deletingLastPathComponent().path, nil) else { throw failure() }
        let physicalRoot = String(cString: parent) + "/" + rootURL.lastPathComponent
        free(parent)
        let rootParts = physicalRoot.split(separator: "/").map(String.init)
        guard !rootParts.isEmpty, !rootParts.contains("..") else { throw failure(EINVAL) }
        // Known-path traversal needs search permission, never directory listing.
        // Reading ancestors can request broad Documents access even when the user
        // already authorized the selected library through the folder picker.
        var fd = open("/", O_SEARCH | O_NOFOLLOW)
        guard fd >= 0 else { throw failure() }
        defer { close(fd) }
        let parts = rootParts + relative.split(separator: "/").dropLast().map(String.init)
        for (index, component) in parts.enumerated() {
            var next = openat(fd, component, O_SEARCH | O_NOFOLLOW)
            if next < 0 && errno == ENOENT && create && index >= rootParts.count - 1 {
                guard mkdirat(fd, component, 0o755) == 0 || errno == EEXIST else { throw failure() }
                next = openat(fd, component, O_SEARCH | O_NOFOLLOW)
            }
            guard next >= 0 else { throw failure() }
            close(fd)
            fd = next
        }
        return try body(fd, (relative as NSString).lastPathComponent)
    }
}
