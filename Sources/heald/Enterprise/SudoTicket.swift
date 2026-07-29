import Foundation
import OSLog

/// Enterprise sudo ticket: refresh non-interactive sudo for safe privileged heals.
/// Install once: `heald sudo-setup` writes /etc/sudoers.d/heald (requires admin).
enum SudoTicket {
    static let marker = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".heald/data/sudo_ticket_ok")

    /// True if `sudo -n true` works (ticket live or passwordless).
    static func hasTicket() -> Bool {
        ShellRunner.run("/usr/bin/sudo", arguments: ["-n", "true"]).succeeded
    }

    /// Try to keep ticket alive (no password prompt in LaunchAgent).
    static func refreshQuiet() -> Bool {
        let ok = hasTicket()
        if ok {
            try? "\(Date().timeIntervalSince1970)".write(
                to: marker, atomically: true, encoding: .utf8
            )
        }
        return ok
    }

    /// Run privileged command only with live ticket.
    static func runPrivileged(_ executable: String, arguments: [String] = []) -> ShellRunner.Result {
        guard hasTicket() else {
            return ShellRunner.Result(
                output: "",
                errorOutput: "no sudo ticket — run: heald sudo-setup && sudo -v",
                exitCode: 1
            )
        }
        return ShellRunner.run("/usr/bin/sudo", arguments: ["-n", executable] + arguments)
    }

    /// Print instructions / install helper script path.
    static func setupInstructions() -> String {
        """
        heald sudo-setup (enterprise)

        1) Interactive once per session (recommended):
             sudo -v
             # then LaunchAgent inherits if configured with !tty_tickets

        2) Optional drop-in (admin) — review carefully:
             # /etc/sudoers.d/heald
             Defaults!/usr/sbin/purge timestamp_timeout=30
             Defaults!/usr/bin/dscacheutil timestamp_timeout=30
             YOUR_USER ALL=(root) NOPASSWD: /usr/sbin/purge
             YOUR_USER ALL=(root) NOPASSWD: /usr/bin/dscacheutil -flushcache
             YOUR_USER ALL=(root) NOPASSWD: /usr/bin/killall mds

        Install helper:
             heald sudo-setup --write   # writes draft to ~/.heald/sudoers.heald.draft
             sudo cp ~/.heald/sudoers.heald.draft /etc/sudoers.d/heald
             sudo chmod 440 /etc/sudoers.d/heald
             sudo visudo -cf /etc/sudoers.d/heald
        """
    }

    static func writeDraft() -> URL {
        let user = NSUserName()
        let draft = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/sudoers.heald.draft")
        let body = """
        # heald enterprise — review before install
        # Generated for user \(user)
        Defaults timestamp_timeout=30
        \(user) ALL=(root) NOPASSWD: /usr/sbin/purge
        \(user) ALL=(root) NOPASSWD: /usr/bin/dscacheutil
        \(user) ALL=(root) NOPASSWD: /usr/bin/killall
        \(user) ALL=(root) NOPASSWD: /usr/sbin/softwareupdate
        """
        try? FileManager.default.createDirectory(
            at: draft.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? body.write(to: draft, atomically: true, encoding: .utf8)
        return draft
    }
}
