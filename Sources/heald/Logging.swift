import OSLog

extension Logger {
    static let lifecycle  = Logger(subsystem: "com.heald.daemon", category: "lifecycle")
    static let core       = Logger(subsystem: "com.heald.daemon", category: "core")
    static let collector  = Logger(subsystem: "com.heald.daemon", category: "collector")
    // Phase 5 adds: .healer
}
