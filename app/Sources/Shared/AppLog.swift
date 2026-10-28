import Foundation
import OSLog

/// 結構化日誌（CLAUDE.md §40）。
enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.manfredsun.foleylibrary"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let database = Logger(subsystem: subsystem, category: "database")
    static let library = Logger(subsystem: subsystem, category: "library")
    static let organizer = Logger(subsystem: subsystem, category: "organizer")
}
