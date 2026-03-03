import OSLog

extension Logger {
    static let lifecycle = Logger(subsystem: "com.heald.daemon", category: "lifecycle")
    static let core      = Logger(subsystem: "com.heald.daemon", category: "core")
    // Phase 2 adds: .collector, .analyzer
    // Phase 5 adds: .healer
}
