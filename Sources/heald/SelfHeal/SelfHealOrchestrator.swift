import Foundation
import ServiceLifecycle
import OSLog

/// Enterprise self-heal loop: **detect → remediate → log → notify**.
/// **No Meister / meisterSiri dependency** — all actions are native heald modules.
struct SelfHealOrchestrator: Service {
    let store: MetricsStore
    let activityLog: ActivityLog

    private let pollSeconds: Int = 45
    private let autofix = AutofixEngine()
    private let proactive = ProactiveHealer()
    private let ramPurge = RAMPurge()
    private let cleaner = SystemCleaner()
    private let deepClean = DeepClean()

    private let cooldowns: [String: TimeInterval] = [
        "ram_purge": 600,
        "disk_cleanup": 1800,
        "deep_trim": 3600,
        "firewall_on": 3600,
        "proactive_heal": 1800,
        "notify_thermal": 1800,
        "brew_light": 7200,
    ]

    func run() async throws {
        Logger.healer.info("SelfHealOrchestrator started (enterprise native — no Meister)")
        let state = HealCooldownState()

        // First proactive pass shortly after boot
        try await Task.sleep(for: .seconds(20))
        await fire(state: state, key: "proactive_heal", reason: "boot hygiene") {
            await self.proactive.run(activityLog: self.activityLog)
        }

        while true {
            try await Task.sleep(for: .seconds(pollSeconds))
            await evaluateAndHeal(state: state)
        }
    }

    private func evaluateAndHeal(state: HealCooldownState) async {
        let ram = await store.ram
        let disk = await store.disk
        let thermal = await store.thermal
        let security = await store.security

        // 1) RAM pressure
        if ram.timestamp != .distantPast, ram.pressureLevel >= 2 {
            await fire(state: state, key: "ram_purge", reason: "RAM pressure=\(ram.pressureLevel)") {
                await self.ramPurge.purge(activityLog: self.activityLog)
            }
        } else if ram.timestamp != .distantPast, ram.swapUsed > 1_073_741_824 {
            // >1 GB swap
            await fire(state: state, key: "ram_purge", reason: "swap>\(Int(ram.swapUsed / 1_048_576))MB") {
                await self.ramPurge.purge(activityLog: self.activityLog)
            }
        }

        // 2) Disk pressure
        if let root = disk.volumes.first(where: { $0.mountPoint == "/" }),
           root.totalBytes > 0 {
            let freePct = Double(root.freeBytes) / Double(root.totalBytes) * 100
            if freePct < 15 {
                await fire(state: state, key: "disk_cleanup", reason: String(format: "disk free %.0f%%", freePct)) {
                    try? await self.cleaner.cleanCaches(activityLog: self.activityLog)
                    try? await self.cleaner.emptyTrash(activityLog: self.activityLog)
                    try? await self.cleaner.cleanXcodeDerivedData(activityLog: self.activityLog)
                }
            }
            if freePct < 8 {
                await fire(state: state, key: "deep_trim", reason: String(format: "disk critical %.0f%%", freePct)) {
                    await self.deepClean.run(activityLog: self.activityLog)
                    await self.autofix.brewCleanupLight(activityLog: self.activityLog)
                }
            }
        }

        // 3) Thermal serious/critical
        if thermal.timestamp != .distantPast {
            switch thermal.thermalState {
            case .serious, .critical:
                await fire(state: state, key: "notify_thermal", reason: "thermal \(thermal.thermalState.rawValue)") {
                    NotificationService.sendNotification(
                        title: "heald",
                        message: "Mac thermal \(thermal.thermalState.rawValue) — self-heal free RAM"
                    )
                    await self.ramPurge.purge(activityLog: self.activityLog)
                }
            case .nominal, .fair:
                break
            }
        }

        // 4) Firewall
        if security.timestamp != .distantPast, !security.firewallEnabled {
            await fire(state: state, key: "firewall_on", reason: "firewall disabled") {
                await self.autofix.enableFirewall(activityLog: self.activityLog)
            }
        }

        // 5) Periodic proactive (uses longer cooldown)
        await fire(state: state, key: "proactive_heal", reason: "scheduled proactive") {
            await self.proactive.run(activityLog: self.activityLog)
        }

        await writeStatus(state: state, ram: ram, disk: disk)
    }

    private func fire(
        state: HealCooldownState,
        key: String,
        reason: String,
        action: @escaping () async -> Void
    ) async {
        let cd = cooldowns[key] ?? 900
        guard await state.canFire(key: key, cooldown: cd) else { return }

        Logger.healer.info("Self-heal [\(key)]: \(reason)")
        try? await activityLog.log(event: ActivityEvent(
            type: .healingAttempt,
            summary: "Self-heal \(key): \(reason)"
        ))

        await action()
        await state.markFired(key: key)

        try? await activityLog.log(event: ActivityEvent(
            type: .selfHealed,
            summary: "Self-heal done: \(key)",
            detail: reason
        ))
        // Don't notify on every proactive_heal tick — only meaningful remediations
        if key != "proactive_heal" {
            NotificationService.sendNotification(
                title: "heald self-heal",
                message: "\(key): \(reason)"
            )
        }
    }

    private func writeStatus(state: HealCooldownState, ram: RAMSnapshot, disk: DiskSnapshot) async {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let freePct: Double
        if let root = disk.volumes.first(where: { $0.mountPoint == "/" }), root.totalBytes > 0 {
            freePct = Double(root.freeBytes) / Double(root.totalBytes) * 100
        } else {
            freePct = -1
        }
        let last = await state.snapshot()
        let dict: [String: Any] = [
            "schema": "heald.self_heal/v1",
            "ts": ISO8601DateFormatter().string(from: Date()),
            "edition": "enterprise",
            "meister_dependency": false,
            "ram_pressure": ram.pressureLevel,
            "disk_free_pct": freePct,
            "last_actions": last,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("self_heal.json"), options: .atomic)
        }
    }
}

actor HealCooldownState {
    private var last: [String: Date] = [:]

    func canFire(key: String, cooldown: TimeInterval) -> Bool {
        guard let t = last[key] else { return true }
        return Date().timeIntervalSince(t) >= cooldown
    }

    func markFired(key: String) {
        last[key] = Date()
    }

    func snapshot() -> [String: String] {
        let f = ISO8601DateFormatter()
        var out: [String: String] = [:]
        for (k, v) in last {
            out[k] = f.string(from: v)
        }
        return out
    }
}
