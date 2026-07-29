import Foundation

/// Storage candidates report — native, read-only (meister-inspired, not meister-linked).
enum StorageReport {
    struct Row: Sendable {
        let path: String
        let mb: Int
        let note: String
    }

    static func scan() -> [Row] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates: [(String, String)] = [
            ("\(home)/Library/Developer/Xcode/DerivedData", "Xcode DerivedData"),
            ("\(home)/Library/Developer/CoreSimulator", "iOS Simulators"),
            ("\(home)/Library/Caches", "User caches"),
            ("\(home)/.Trash", "Trash"),
            ("\(home)/Library/Logs", "User logs"),
            ("\(home)/.npm", "npm cache"),
            ("\(home)/.cargo/registry", "Cargo registry"),
            ("\(home)/go/pkg/mod", "Go module cache"),
        ]
        var rows: [Row] = []
        for (path, note) in candidates {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let r = ShellRunner.run("/usr/bin/du", arguments: ["-sm", path])
            let mb = Int(r.output.split(separator: "\t").first ?? "0") ?? 0
            if mb > 0 {
                rows.append(Row(path: path, mb: mb, note: note))
            }
        }
        return rows.sorted { $0.mb > $1.mb }
    }

    static func printReport() {
        print("heald storage — safe-to-delete candidates (read-only)")
        print("")
        print(String(format: "  %-8s  %@", "MB", "Path"))
        print("  " + String(repeating: "─", count: 56))
        for row in scan() {
            print(String(format: "  %-8d  %@", row.mb, row.path))
            print(String(format: "  %8s  %@", "", row.note))
        }
        print("")
        print("  Apply: heald maintain --profile deep")
    }
}
