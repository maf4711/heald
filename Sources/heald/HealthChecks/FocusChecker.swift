import Foundation
import OSLog

/// Detects Focus/DND mode status via defaults.
/// Used to suppress non-critical notifications when Focus is active.
struct FocusChecker {
    func check(store: MetricsStore) async -> FocusSnapshot {
        let snapshot = readFocusState()
        await store.updateFocus(snapshot)

        if snapshot.isActive {
            Logger.health.info("Focus mode active: \(snapshot.modeName ?? "DND")")
        }

        return snapshot
    }

    private func readFocusState() -> FocusSnapshot {
        // Check DND/Focus via defaults (macOS 12+)
        // The assertion store tracks active Focus modes
        _ = ShellRunner.run("/usr/bin/defaults", arguments: [
            "read", "com.apple.controlcenter", "NSStatusItem Visible FocusModes"
        ])

        // Also check via do-not-disturb plists
        let dndResult = ShellRunner.run("/usr/bin/plutil", arguments: [
            "-p",
            "\(NSHomeDirectory())/Library/DoNotDisturb/DB/Assertions.json"
        ])

        var isActive = false
        var modeName: String?

        // Parse assertions JSON output
        if dndResult.succeeded {
            let output = dndResult.output
            // Look for active assertions with storeAssertionRecords
            if output.contains("storeAssertionRecords") {
                // If there are assertion records with non-empty data, Focus is active
                let lines = output.split(separator: "\n")
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.contains("assertionDetails") && !trimmed.contains("=> {}") {
                        isActive = true
                    }
                    if trimmed.contains("modeIdentifier") {
                        let parts = trimmed.split(separator: "=>")
                        if let modeId = parts.last {
                            let cleaned = modeId.trimmingCharacters(in: .whitespaces)
                                .replacingOccurrences(of: "\"", with: "")
                            if cleaned.contains("donotdisturb") {
                                modeName = "Do Not Disturb"
                            } else if cleaned.contains("personalFocus") {
                                modeName = "Personal"
                            } else if cleaned.contains("workFocus") {
                                modeName = "Work"
                            } else {
                                modeName = cleaned.components(separatedBy: ".").last ?? cleaned
                            }
                        }
                    }
                }
            }
        }

        return FocusSnapshot(isActive: isActive, modeName: modeName, timestamp: Date())
    }
}
