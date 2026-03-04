import Foundation

/// HEAL-03: Processes that must never be killed.
/// Killing these causes system instability, login failure, or kernel panic.
enum ProcessSafelist {
    /// System-critical process names that are never eligible for kill.
    static let protectedNames: Set<String> = [
        // Kernel and core
        "kernel_task", "launchd", "init",

        // Display and UI
        "WindowServer", "loginwindow", "Dock", "Finder",
        "SystemUIServer", "NotificationCenter",

        // Security
        "securityd", "trustd", "authd", "opendirectoryd",
        "endpointsecurityd", "syspolicyd",

        // File system
        "diskarbitrationd", "fseventsd", "mds", "mds_stores",
        "diskmanagementd", "lsd",

        // Network
        "configd", "mDNSResponder", "networkd", "WiFiAgent",
        "airportd", "bluetoothd",

        // Power and hardware
        "powerd", "thermald", "coreduetd", "ioupsd",
        "IOUSBFamily", "AppleHDAEngineOutput",

        // Logging and diagnostics
        "logd", "syslogd", "diagnosticd", "osanalyticshelper",

        // User session
        "sshd", "UserEventAgent", "cfprefsd",
        "coreservicesd", "distnoted",

        // Our own daemon
        "heald",
    ]

    /// UIDs below this threshold are always system processes.
    static let systemUIDThreshold = 500

    /// Returns true if this process must not be killed.
    static func isProtected(name: String, uid: Int) -> Bool {
        if uid < systemUIDThreshold { return true }
        return protectedNames.contains(name)
    }
}
