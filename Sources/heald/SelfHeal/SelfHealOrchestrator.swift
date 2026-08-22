import Foundation
import HealdCore
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
    private let perf = PerformanceHealer()

    private let cooldowns: [String: TimeInterval] = [
        "ram_purge": 600,
        "disk_cleanup": 1800,
        "deep_trim": 3600,
        "firewall_on": 3600,
        "filevault_warn": 86400,
        "proactive_heal": 1800,
        "notify_thermal": 1800,
        "brew_light": 7200,
        "perf_autoheal": 300,
    ]

    private let batteryGuardian = BatteryGuardian()
    private let networkHeal = NetworkSelfHeal()
    private let safeUpdate = SafeSoftwareUpdate()

    func run() async throws {
        Logger.healer.info("SelfHealOrchestrator started (enterprise native — no Meister)")
        _ = PolicyPack.load() // ensure default policy exists
        let state = HealCooldownState()

        try await Task.sleep(for: .seconds(180))
        let policy0 = await PolicyStore.shared.current()
        if policy0.selfHealEnabled {
            await fire(state: state, key: "proactive_heal", reason: "boot hygiene", policy: policy0) {
                await self.proactive.run(activityLog: self.activityLog)
            }
            if policy0.performanceAutohealEnabled ?? true {
                await fire(state: state, key: "perf_autoheal", reason: "boot settle", policy: policy0) {
                    _ = await self.perf.run(
                        activityLog: self.activityLog,
                        cpuOverall: 1,
                        force: true
                    )
                }
            }
        }

        var tick = 0
        while true {
            try await Task.sleep(for: .seconds(pollSeconds))
            tick += 1
            await PolicyStore.shared.reload()
            await evaluateAndHeal(state: state, tick: tick)
        }
    }

    private func evaluateAndHeal(state: HealCooldownState, tick: Int) async {
        let policy = await PolicyStore.shared.current()
        guard policy.selfHealEnabled else {
            await writeStatus(state: state, ram: await store.ram, disk: await store.disk, policy: policy)
            return
        }

        let ram = await store.ram
        let disk = await store.disk
        let thermal = await store.thermal
        let security = await store.security
        let cpu = await store.cpu

        // Battery + network every ~3 min
        if tick % 4 == 0 {
            await batteryGuardian.evaluate(store: store, activityLog: activityLog, policy: policy)
            await networkHeal.evaluate(store: store, activityLog: activityLog, policy: policy)
        }
        // Safe softwareupdate hourly-ish
        if tick % 80 == 0 {
            await safeUpdate.maybeRun(activityLog: activityLog, policy: policy)
        }

        // 0) Performance stampede — high load or first tick after boot settle
        if policy.performanceAutohealEnabled ?? true {
            let degraded = PerformanceAutoheal.isDegraded(
                load1: PerformanceHealer.loadAverage1(),
                ncpu: ProcessInfo.processInfo.activeProcessorCount,
                cpuOverall: cpu.overall,
                uptime: ProcessInfo.processInfo.systemUptime
            )
            if degraded || tick <= 1 {
                await fire(state: state, key: "perf_autoheal", reason: degraded ? "cpu/load degraded" : "boot settle", policy: policy) {
                    _ = await self.perf.run(
                        activityLog: self.activityLog,
                        cpuOverall: cpu.overall,
                        force: true
                    )
                }
            }
        }

        // 1) RAM
        if policy.ramPurgeEnabled, ram.timestamp != .distantPast,
           ram.pressureLevel >= policy.ramPressureMin {
            await fire(state: state, key: "ram_purge", reason: "RAM pressure=\(ram.pressureLevel)", policy: policy) {
                await self.ramPurge.purge(activityLog: self.activityLog)
            }
        } else if policy.ramPurgeEnabled, ram.timestamp != .distantPast, ram.swapUsed > 1_073_741_824 {
            await fire(state: state, key: "ram_purge", reason: "swap>\(Int(ram.swapUsed / 1_048_576))MB", policy: policy) {
                await self.ramPurge.purge(activityLog: self.activityLog)
            }
        }

        // 2) Disk
        if policy.diskCleanupEnabled,
           let root = disk.volumes.first(where: { $0.mountPoint == "/" }),
           root.totalBytes > 0 {
            let freePct = Double(root.freeBytes) / Double(root.totalBytes) * 100
            if freePct < policy.diskFreePctWarn {
                await fire(state: state, key: "disk_cleanup", reason: String(format: "disk free %.0f%%", freePct), policy: policy) {
                    try? await self.cleaner.cleanCaches(activityLog: self.activityLog)
                    try? await self.cleaner.emptyTrash(activityLog: self.activityLog)
                    try? await self.cleaner.cleanXcodeDerivedData(activityLog: self.activityLog)
                    await FleetAck.record(action: "disk_cleanup", result: "ok", detail: String(format: "%.0f%% free", freePct))
                }
            }
            if freePct < policy.diskFreePctCritical {
                await fire(state: state, key: "deep_trim", reason: String(format: "disk critical %.0f%%", freePct), policy: policy) {
                    await self.deepClean.run(activityLog: self.activityLog)
                    await self.autofix.brewCleanupLight(activityLog: self.activityLog)
                }
            }
        }

        // 3) Thermal
        if thermal.timestamp != .distantPast {
            switch thermal.thermalState {
            case .serious, .critical:
                await fire(state: state, key: "notify_thermal", reason: "thermal \(thermal.thermalState.rawValue)", policy: policy) {
                    NotificationService.sendNotification(
                        title: "heald",
                        message: "Mac thermal \(thermal.thermalState.rawValue) — self-heal free RAM"
                    )
                    if policy.ramPurgeEnabled {
                        await self.ramPurge.purge(activityLog: self.activityLog)
                    }
                }
            case .nominal, .fair:
                break
            }
        }

        // 4) Firewall
        if policy.firewallEnforce, security.timestamp != .distantPast, !security.firewallEnabled {
            await fire(state: state, key: "firewall_on", reason: "firewall disabled", policy: policy) {
                await self.autofix.enableFirewall(activityLog: self.activityLog)
                await WebhookNotifier.shared.emit(title: "Firewall", text: "Enforced enable", severity: "warning")
            }
        }

        // 5) FileVault warn only
        if policy.fileVaultWarn, security.timestamp != .distantPast, !security.fileVaultEnabled {
            await fire(state: state, key: "filevault_warn", reason: "FileVault off", policy: policy) {
                NotificationService.sendNotification(
                    title: "heald compliance",
                    message: "FileVault is disabled — enable in System Settings"
                )
                await WebhookNotifier.shared.emit(
                    title: "FileVault",
                    text: "disabled on host",
                    severity: "critical"
                )
            }
        }

        // 6) Proactive
        await fire(state: state, key: "proactive_heal", reason: "scheduled proactive", policy: policy) {
            await self.proactive.run(activityLog: self.activityLog)
        }

        await writeStatus(state: state, ram: ram, disk: disk, policy: policy)
    }

    private func fire(
        state: HealCooldownState,
        key: String,
        reason: String,
        policy: PolicyPack,
        action: @escaping () async -> Void
    ) async {
        let cd = cooldowns[key] ?? 900
        guard await state.canFire(key: key, cooldown: cd) else { return }

        // Consent: log-only never remediates; ask needs `heald approve <key>` (or consent=auto)
        if !policy.allowsRemediation() {
            if policy.consent == .ask, ApprovalStore.consume(action: key) {
                Logger.healer.info("Self-heal [\(key)]: approved one-shot — \(reason)")
                // fall through to remediate
            } else {
                try? await activityLog.log(event: ActivityEvent(
                    type: .healingAttempt,
                    summary: "Self-heal BLOCKED by consent=\(policy.consent.rawValue): \(key)",
                    detail: reason
                ))
                if policy.consent == .ask {
                    NotificationService.sendNotification(
                        title: "heald needs approval",
                        message: "\(key): \(reason) — heald approve \(key)"
                    )
                }
                await state.markFired(key: key) // avoid spam
                return
            }
        }

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
        await FleetAck.record(action: key, result: "ok", detail: reason)
        if key != "proactive_heal" && key != "perf_autoheal" {
            NotificationService.sendNotification(
                title: "heald self-heal",
                message: "\(key): \(reason)"
            )
            await WebhookNotifier.shared.emit(title: key, text: reason, severity: "info")
        }
    }

    private func writeStatus(
        state: HealCooldownState,
        ram: RAMSnapshot,
        disk: DiskSnapshot,
        policy: PolicyPack
    ) async {
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
            "consent": policy.consent.rawValue,
            "self_heal_enabled": policy.selfHealEnabled,
            "sudo_ticket": SudoTicket.hasTicket(),
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
