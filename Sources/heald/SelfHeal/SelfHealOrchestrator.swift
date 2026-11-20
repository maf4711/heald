import Foundation
import HealdCore
import ServiceLifecycle
import OSLog

/// Enterprise self-heal loop: **detect → remediate → log → notify**.
/// **No Meister / meisterSiri dependency** — all actions are native heald modules.
struct SelfHealOrchestrator: Service {
    let store: MetricsStore
    let activityLog: ActivityLog
    let ai: AppleIntelligenceClient

    private let pollSeconds: Int = 45
    private let autofix = AutofixEngine()
    private let proactive = ProactiveHealer()
    private let ramPurge = RAMPurge()
    private let cleaner = SystemCleaner()
    private let deepClean = DeepClean()
    let perf = PerformanceHealer()
    let scannerRemediation = ScannerRemediation()

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
        "app_restart": 60,
        "dns_flush": 600,
    ]

    func cooldown(for key: String) -> TimeInterval { cooldowns[key] ?? 900 }

    let batteryGuardian = BatteryGuardian()
    let networkHeal = NetworkSelfHeal()
    let safeUpdate = SafeSoftwareUpdate()

    func run() async throws {
        Logger.healer.info("SelfHealOrchestrator started (enterprise native — no Meister)")
        _ = PolicyPack.load() // ensure default policy exists
        let state = HealCooldownState()

        try await Task.sleep(for: .seconds(180))
        let policy0 = await PolicyStore.shared.current()
        if policy0.selfHealEnabled {
            var bootBudget = AdvisorBudget()
            await fire(state: state, key: "proactive_heal", reason: "boot hygiene", policy: policy0, budget: &bootBudget) {
                await self.proactive.run(activityLog: self.activityLog)
                return true
            }
            if PerformanceAutoheal.isEnabled(policy0.performanceAutohealEnabled) {
                await fire(state: state, key: "perf_autoheal", reason: "boot settle", policy: policy0, budget: &bootBudget) {
                    _ = await self.perf.run(
                        activityLog: self.activityLog,
                        cpuOverall: 1,
                        force: true
                    )
                    return true
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

        // CPU storm, battery, network, softwareupdate: heals outside fire (own gates), reported directly.
        await runDirectHeals(policy: policy, tick: tick)

        let ram = await store.ram
        let disk = await store.disk
        let thermal = await store.thermal
        let security = await store.security
        let cpu = await store.cpu
        let memoryCritical = AutohealAdvisor.isMemoryCritical(pressureLevel: ram.pressureLevel)
        var budget = AdvisorBudget()

        // 0) Performance stampede — high load or first tick after boot settle
        let degraded = PerformanceAutoheal.isDegraded(
            load1: PerformanceHealer.loadAverage1(),
            ncpu: ProcessInfo.processInfo.activeProcessorCount,
            cpuOverall: cpu.overall,
            uptime: ProcessInfo.processInfo.systemUptime
        )
        if PerformanceAutoheal.shouldFire(
            degraded: degraded || tick <= 1,
            enabled: PerformanceAutoheal.isEnabled(policy.performanceAutohealEnabled),
            selfHealEnabled: policy.selfHealEnabled
        ) {
            await fire(state: state, key: "perf_autoheal", reason: degraded ? "cpu/load degraded" : "boot settle", policy: policy, memoryCritical: memoryCritical, budget: &budget) {
                // A perf pass has no failure mode: it either fixed something or found nothing left.
                _ = await self.perf.run(
                    activityLog: self.activityLog,
                    cpuOverall: cpu.overall,
                    force: true
                )
                return true
            }
        }

        // 1) RAM
        if policy.ramPurgeEnabled, ram.timestamp != .distantPast,
           ram.pressureLevel >= policy.ramPressureMin {
            await fire(state: state, key: "ram_purge", reason: "RAM pressure=\(ram.pressureLevel)", policy: policy, memoryCritical: memoryCritical, budget: &budget) {
                await self.ramPurge.purge(activityLog: self.activityLog)
            }
        } else if policy.ramPurgeEnabled, ram.timestamp != .distantPast, ram.swapUsed > 1_073_741_824 {
            await fire(state: state, key: "ram_purge", reason: "swap>\(Int(ram.swapUsed / 1_048_576))MB", policy: policy, memoryCritical: memoryCritical, budget: &budget) {
                await self.ramPurge.purge(activityLog: self.activityLog)
            }
        }

        // 2) Disk
        if policy.diskCleanupEnabled,
           let root = disk.volumes.first(where: { $0.mountPoint == "/" }),
           root.totalBytes > 0 {
            let freePct = Double(root.freeBytes) / Double(root.totalBytes) * 100
            if freePct < policy.diskFreePctWarn {
                await fire(state: state, key: "disk_cleanup", reason: String(format: "disk free %.0f%%", freePct), policy: policy, memoryCritical: memoryCritical, budget: &budget) {
                    let caches = (try? await self.cleaner.cleanCaches(activityLog: self.activityLog)) != nil
                    let trash = (try? await self.cleaner.emptyTrash(activityLog: self.activityLog)) != nil
                    let derived = (try? await self.cleaner.cleanXcodeDerivedData(activityLog: self.activityLog)) != nil
                    let ok = caches && trash && derived
                    await FleetAck.record(action: "disk_cleanup", result: ok ? "ok" : "partial", detail: String(format: "%.0f%% free", freePct))
                    return ok
                }
            }
            if freePct < policy.diskFreePctCritical {
                await fire(state: state, key: "deep_trim", reason: String(format: "disk critical %.0f%%", freePct), policy: policy, memoryCritical: memoryCritical, budget: &budget) {
                    await self.deepClean.run(activityLog: self.activityLog) // best-effort, no failure signal
                    return await self.autofix.brewCleanupLight(activityLog: self.activityLog)
                }
            }
        }

        // 3) Thermal
        if thermal.timestamp != .distantPast {
            switch thermal.thermalState {
            case .serious, .critical:
                await fire(state: state, key: "notify_thermal", reason: "thermal \(thermal.thermalState.rawValue)", policy: policy, memoryCritical: memoryCritical, budget: &budget) {
                    NotificationService.sendNotification(
                        title: "heald",
                        message: "Mac thermal \(thermal.thermalState.rawValue) — self-heal free RAM"
                    )
                    // Notification always goes out; success = the RAM purge when enabled.
                    guard policy.ramPurgeEnabled else { return true }
                    return await self.ramPurge.purge(activityLog: self.activityLog)
                }
            case .nominal, .fair:
                break
            }
        }

        // 4) Firewall
        if policy.firewallEnforce, security.timestamp != .distantPast, !security.firewallEnabled {
            await fire(state: state, key: "firewall_on", reason: "firewall disabled", policy: policy, memoryCritical: memoryCritical, budget: &budget) {
                let ok = await self.autofix.enableFirewall(activityLog: self.activityLog)
                await WebhookNotifier.shared.emit(title: "Firewall", text: ok ? "Enforced enable" : "Enable failed", severity: "warning")
                return ok
            }
        }

        // 5) FileVault warn only
        if policy.fileVaultWarn, security.timestamp != .distantPast, !security.fileVaultEnabled {
            await fire(state: state, key: "filevault_warn", reason: "FileVault off", policy: policy, memoryCritical: memoryCritical, budget: &budget) {
                NotificationService.sendNotification(
                    title: "heald compliance",
                    message: "FileVault is disabled — enable in System Settings"
                )
                await WebhookNotifier.shared.emit(
                    title: "FileVault",
                    text: "disabled on host",
                    severity: "critical"
                )
                return true
            }
        }

        // 6) Proactive
        await fire(state: state, key: "proactive_heal", reason: "scheduled proactive", policy: policy, memoryCritical: memoryCritical, budget: &budget) {
            await self.proactive.run(activityLog: self.activityLog) // best-effort hygiene, no failure signal
            return true
        }

        // 7) Device findings (SystemErrorScanner) — fixes run only through the consent gate in fire
        await healScannerFindings(state: state, policy: policy, memoryCritical: memoryCritical, budget: &budget)

        await writeStatus(state: state, ram: ram, disk: disk, policy: policy)
    }

    /// Gate shared by every action: cooldown → advisor → consent → run.
    /// Every decision past the cooldown appends one heal report; `action` returns whether it succeeded.
    @discardableResult
    func fire(
        state: HealCooldownState,
        key: String,
        reason: String,
        policy: PolicyPack,
        memoryCritical: Bool = false,
        findingFingerprint: String? = nil,
        budget: inout AdvisorBudget,
        action: @escaping () async -> Bool
    ) async -> GateOutcome {
        let cd = cooldown(for: key)
        guard await state.canFire(key: key, cooldown: cd) else { return .cooldown }
        var verdict: AdvisorVerdict?
        var approved = false
        var succeeded = false
        var durationMs = 0
        func report(_ gate: GateOutcome) async -> GateOutcome {
            await recordHealReport(
                gate, key: key, reason: reason, policy: policy, verdict: verdict,
                approved: approved, succeeded: succeeded, durationMs: durationMs,
                findingFingerprint: findingFingerprint
            )
            return gate
        }

        // Advisor (Apple FM, on-device): may only downgrade proceed → defer/skip. Never executes.
        if let healAction = HealdCore.HealAction(rawValue: key) {
            let v = await advise(
                healAction,
                reason: reason,
                context: "cooldown=\(Int(cd))s consent=\(policy.consent.rawValue)",
                memoryCritical: memoryCritical,
                budget: &budget
            )
            verdict = v
            await logAdvice(v)
            switch AutohealAdvisor.disposition(v, cooldown: cd) {
            case .run:
                break // continue to the consent gate below
            case .defer(let retryAfter):
                // Re-arm after min(cooldown, 300 s) instead of the full cooldown.
                await state.markFired(
                    key: key,
                    at: AutohealAdvisor.cooldownMark(now: Date(), cooldown: cd, retryAfter: retryAfter)
                )
                return await report(.advisorDeferred)
            case .skip:
                await state.markFired(key: key)
                try? await activityLog.log(event: ActivityEvent(
                    type: .healingAttempt,
                    summary: "Self-heal SKIPPED by advisor: \(key)",
                    detail: v.rationale,
                    aiGenerated: v.source == .appleFM
                ))
                return await report(.advisorSkipped)
            }
        }

        // Consent: log-only never remediates; ask needs `heald approve <key>` (or consent=auto)
        if !policy.allowsRemediation() {
            if policy.consent == .ask, ApprovalStore.consume(action: key) {
                Logger.healer.info("Self-heal [\(key)]: approved one-shot — \(reason)")
                approved = true
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
                return await report(policy.consent == .ask ? .blockedAsk : .blockedLog)
            }
        }

        Logger.healer.info("Self-heal [\(key)]: \(reason)")
        try? await activityLog.log(event: ActivityEvent(
            type: .healingAttempt,
            summary: "Self-heal \(key): \(reason)"
        ))

        let start = ContinuousClock.now
        succeeded = await action()
        durationMs = Self.ms(since: start)
        await state.markFired(key: key)

        try? await activityLog.log(event: ActivityEvent(
            type: succeeded ? .selfHealed : .healingFailed,
            summary: succeeded ? "Self-heal done: \(key)" : "Self-heal failed: \(key)",
            detail: reason
        ))
        await FleetAck.record(action: key, result: succeeded ? "ok" : "failed", detail: reason)
        _ = await report(.ran)
        if key != "proactive_heal" && key != "perf_autoheal" {
            NotificationService.sendNotification(
                title: "heald self-heal",
                message: "\(key): \(reason)"
            )
            await WebhookNotifier.shared.emit(title: key, text: reason, severity: "info")
        }
        return .ran
    }

    /// One heal report per decision → `HealReportOutbox` (CloudPusher delivers it when cloud is allowed).
    private func recordHealReport(
        _ gate: GateOutcome,
        key: String,
        reason: String,
        policy: PolicyPack,
        verdict: AdvisorVerdict?,
        approved: Bool,
        succeeded: Bool,
        durationMs: Int,
        findingFingerprint: String?
    ) async {
        guard let outcome = HealOutcome.from(gate, approved: approved, succeeded: succeeded) else { return }
        let advisor = verdict ?? AdvisorVerdict(
            action: HealdCore.HealAction(rawValue: key) ?? .proactiveHeal, recommendation: .proceed,
            confidence: 0, rationale: "no advisor for \(key)", source: .rules, latencyMs: 0
        )
        let detail: String? = switch outcome {
        case .blockedConsent: "consent=\(policy.consent.rawValue)"
        case .advisorSkipped, .advisorDeferred: advisor.rationale
        case .executedFailed: "action reported failure"
        case .executedOk, .approvedExecuted: nil
        }
        await HealReportOutbox.shared.append(HealReport(
            machineId: DeviceIdentity.machineId(),
            healdVersion: HealdApp.version,
            action: key,
            trigger: reason,
            consent: policy.healConsent,
            outcome: outcome,
            durationMs: durationMs,
            findingFingerprint: findingFingerprint,
            detail: detail,
            advisor: HealAdvisor(advisor),
            redact: PIIRedactor.redact
        ))
    }

    /// Consult Apple FM within this tick's budget; rules fallback once the budget/breaker is spent.
    private func advise(
        _ healAction: HealdCore.HealAction,
        reason: String,
        context: String,
        memoryCritical: Bool,
        budget: inout AdvisorBudget
    ) async -> AdvisorVerdict {
        guard let timeout = budget.nextTimeout() else {
            return .rulesFallback(healAction, rationale: "advisor budget/circuit open this tick")
        }
        let ai = self.ai
        let verdict = await AutohealAdvisor.consult(
            ruleAction: healAction,
            timeout: timeout,
            available: await ai.isAvailable,
            memoryCritical: memoryCritical
        ) {
            await ai.adviseHeal(action: healAction.rawValue, reason: reason, context: context)
        }
        budget.record(verdict)
        return verdict
    }

    private func logAdvice(_ v: AdvisorVerdict) async {
        try? await activityLog.log(event: ActivityEvent(
            type: .aiAdvice,
            summary: "Advisor \(v.action.rawValue): \(v.recommendation.rawValue) (\(String(format: "%.2f", v.confidence)))",
            detail: String(v.rationale.prefix(AutohealAdvisor.maxRationaleChars)),
            afterState: v.structuredJSON,
            aiGenerated: v.source == .appleFM
        ))
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
