import OSLog

extension Logger {
    static let lifecycle  = Logger(subsystem: "com.heald.daemon", category: "lifecycle")
    static let core       = Logger(subsystem: "com.heald.daemon", category: "core")
    static let collector  = Logger(subsystem: "com.heald.daemon", category: "collector")
    static let storage    = Logger(subsystem: "com.heald.daemon", category: "storage")
    static let healer     = Logger(subsystem: "com.heald.daemon", category: "healer")
    static let health     = Logger(subsystem: "com.heald.daemon", category: "health")
    static let ai         = Logger(subsystem: "com.heald.daemon", category: "ai")
    static let maintenance = Logger(subsystem: "com.heald.daemon", category: "maintenance")
    static let benchmark  = Logger(subsystem: "com.heald.daemon", category: "benchmark")
    static let update     = Logger(subsystem: "com.heald.daemon", category: "update")
}
