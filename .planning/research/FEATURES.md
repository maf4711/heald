# Feature Research

**Domain:** macOS System Monitoring and Self-Healing Daemon
**Researched:** 2026-03-03
**Confidence:** MEDIUM (competitive landscape from WebSearch + official product pages; auto-healing specifics extrapolated from domain patterns)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features every macOS monitoring tool provides. Missing any of these makes the product feel unfinished.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| CPU usage monitoring (overall + per-core) | iStat Menus, htop, Activity Monitor all do this; baseline expectation | LOW | Use `host_processor_info()` or `top -l 1 -s 0` / `sysctl` |
| RAM / memory pressure monitoring | Memory pressure is the primary pain point for Mac users; "memory compression, swap used" must be shown | LOW | `vm_stat`, `sysctl vm.swapusage` |
| Disk space remaining (per volume) | Users fear silent "disk full" failures; every tool shows this | LOW | `df -h` or `statvfs()` |
| Disk I/O activity monitoring | Active disk thrashing degrades performance visibly | MEDIUM | `iostat` or IOKit framework |
| Process list with CPU/RAM per process | Power users need to know what's consuming resources | MEDIUM | `/proc`-style via `proc_pidinfo`, `ps`, `sysctl` |
| Identifying top resource consumers | "Which app is eating my CPU?" is the #1 user question | LOW | Sort process list descending by CPU/RAM |
| Structured activity log (what happened when) | Users need to audit what the daemon actually did; without this there's no trust | MEDIUM | Timestamped JSON or plain text log file |
| Persistent background operation (LaunchAgent) | Tool must survive reboots and run without user action | LOW | `launchd` plist in `~/Library/LaunchAgents/` |
| Minimal resource footprint | The monitor itself must not become the problem it's solving | MEDIUM | Polling interval tuning; avoid tight loops |
| Graceful termination and restart | Daemon must handle SIGTERM cleanly without corrupting state | LOW | Signal handling, atomic writes |

### Differentiators (Competitive Advantage)

These features are not standard in existing tools. They define the "self-healing" angle that separates this project from passive monitors like iStat Menus.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Automatic kill of hung/unresponsive processes | Existing tools show you the problem; this one fixes it without user action | HIGH | Must distinguish "hung" from "slow". Use `kill -0` liveness check + CPU-stuck detection; try SIGTERM first, SIGKILL fallback. Skip launchd-managed processes (use `launchctl` instead) |
| Crashed critical app auto-restart | Zero-downtime for user-designated "must-stay-alive" apps | HIGH | Maintain a "watch list" of critical apps; poll PID existence; re-launch via `open -a` or `launchctl kickstart` |
| Orphaned LaunchAgent/Daemon detection | Uninstalled apps leave stale plist entries that slow boot; no existing tool auto-cleans these | MEDIUM | Scan `~/Library/LaunchAgents/` for plists whose `ProgramArguments[0]` binary no longer exists |
| Broken plist validation | Corrupt plists silently break services; nobody checks these proactively | MEDIUM | `plutil -lint` against all user-space plists |
| DNS health check and auto-flush | DNS failures are invisible but crippling; flushing is the fix in 90% of cases | MEDIUM | Probe known-good hosts; on failure: `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder` |
| Swap spike detection with context | Alert when swap exceeds threshold AND record which process caused it | MEDIUM | Correlate `vm_stat` swap deltas with top-RAM processes at spike time |
| Homebrew outdated package tracking | Stale packages = security exposure; no passive monitor tracks this | MEDIUM | `brew outdated --json` on schedule; auto-upgrade optional (risky for breaking changes — flag only by default) |
| macOS software update notification | User should see pending OS updates in the same dashboard | LOW | `softwareupdate -l` parsing |
| Chronological activity feed (web dashboard) | Users want to replay what happened: "why was my CPU at 100% at 3pm?" | HIGH | Ring-buffer event store; web UI renders timeline |
| Self-healing audit trail with before/after | Log the exact state before and after each automated intervention | MEDIUM | Capture snapshot, execute fix, capture snapshot again, write diff to log |
| Configurable thresholds and watch list | Power users want to tune CPU/RAM kill thresholds and specify apps to watch | MEDIUM | TOML/YAML config file; hot-reload on change |
| Disk permission repair scheduling | OnyX and CleanMyMac do this manually; this tool can run it on a schedule | MEDIUM | `diskutil repairPermissions` (limited scope in modern macOS due to SIP) |
| Cache and temp file cleanup on schedule | Proactive disk space recovery; existing tools require manual trigger | MEDIUM | Target `~/Library/Caches`, `/tmp`, crash reports, `.log` files older than N days |

### Anti-Features (Commonly Requested, Often Problematic)

These features seem useful but create more problems than they solve. Explicitly avoid them.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Aggressive memory compression forcing | "Free RAM" tools promise instant performance boost | macOS manages memory compression automatically; forcing it wastes CPU (4-9% overhead per research) and rarely helps | Monitor memory pressure metric; alert when swap consistently exceeds 1GB |
| Auto-upgrade Homebrew packages unattended | "Always up to date" sounds good | Breaking changes in upgrades will silently break tools the user depends on; a `brew upgrade` run at 3am can destroy a working dev environment | Track outdated packages, surface them in dashboard, let user trigger upgrade manually or via explicit config opt-in |
| Automatic disk repair (`fsck -fy`) | Failing disk health signals → user wants auto-fix | Running fsck on a critically failing disk risks data corruption; software-level repair cannot fix hardware failure | Alert on S.M.A.R.T. degradation; recommend safe backup before any repair; only offer `First Aid` via Disk Utility for minor issues |
| Kill any process exceeding CPU threshold | Sounds like "stop runaway processes" | Legitimate work (video encoding, compilation, ML training) legitimately uses 100% CPU; killing it destroys user's work | Require sustained CPU usage (>90% for >5 minutes) AND process name not on a safelist; default safelist: Terminal, Xcode, ffmpeg, python |
| Cloud sync / remote monitoring | "Access my system from anywhere" | Violates the explicit out-of-scope constraint; adds security surface area and complexity for negligible value in this personal tool context | Web dashboard on localhost only; no exposure beyond loopback |
| Real-time 1-second polling for all metrics | "Always current data" | Continuous polling at 1s intervals for all subsystems keeps daemon CPU above 1% constantly; degrades the benefit of running it | Tiered polling: critical metrics every 5s, secondary every 30s, health checks every 5 minutes |
| Native macOS App (SwiftUI) | Feels more "professional" | Significantly increases development time and complexity; requires code signing, notarization, App Store review cycle | Web dashboard on localhost is immediately usable and easier to iterate on; aligns with project scope |
| Antivirus / malware scanning | Natural extension of "system health" | Entirely different threat model, requires signature databases, constant updates, high false positive rate; explicitly out of scope | Keep monitoring focused on performance/stability, not security |
| Spotlight re-indexing on schedule | Seen in CleanMyMac and OnyX as a "fix" | Re-indexing disables Spotlight search for 30-60 minutes; frequent re-indexing on a schedule has no benefit | Only trigger on detected Spotlight failure (search returns no results for known files) |

---

## Feature Dependencies

```
[LaunchAgent persistence]
    └──required by──> [Background monitoring daemon]
                          └──required by──> [CPU monitoring]
                          └──required by──> [RAM monitoring]
                          └──required by──> [Disk monitoring]
                          └──required by──> [Process list]
                                └──required by──> [Auto-kill hung processes]
                                └──required by──> [Crash detection]
                                                      └──required by──> [Auto-restart critical apps]

[Structured activity log]
    └──required by──> [Web dashboard activity feed]
    └──required by──> [Self-healing audit trail]

[Web server (local)]
    └──required by──> [Dashboard live view]
    └──required by──> [Activity feed UI]

[Configurable thresholds / watch list]
    └──enhances──> [Auto-kill hung processes]  (respects safelists)
    └──enhances──> [Auto-restart critical apps] (defines watch list)

[DNS health check]
    └──independent──> (standalone probe, no dependency on process monitoring)

[Orphaned LaunchAgent detection]
    └──independent──> (filesystem scan, no dependency on process monitoring)

[Homebrew tracking]
    └──independent──> (CLI invocation, no dependency on process monitoring)

[S.M.A.R.T. disk health]
    └──enhances──> [Disk monitoring] (adds failure prediction on top of space monitoring)
```

### Dependency Notes

- **Process monitoring requires LaunchAgent persistence:** The daemon must be running to collect process data; without launchd integration the tool stops on logout.
- **Activity log is a gateway dependency:** The web dashboard, audit trail, and replay features all require a persistent log store. Build the log format carefully before building any UI on top of it.
- **Auto-kill requires a safelist:** Killing processes without a safelist will kill the user's own terminal sessions, compilers, or media encoders. This dependency must be respected at implementation time.
- **DNS flush and Homebrew tracking are independent:** These health checks run on their own schedules and do not require the core process monitor. They can be built and tested separately.

---

## MVP Definition

### Launch With (v1)

Minimum viable product — what's needed to validate the self-healing concept.

- [ ] LaunchAgent persistence — without this, nothing else matters
- [ ] CPU + RAM + Disk monitoring (5s polling) — core observability
- [ ] Process list with top consumers — required for kill decisions
- [ ] Auto-kill hung processes (sustained high CPU >5min, not on safelist) — the primary "self-healing" value
- [ ] Structured JSON activity log — audit trail for every action taken
- [ ] Basic web dashboard (localhost) — live metrics + activity feed; validates the "see what happened" use case

### Add After Validation (v1.x)

Features to add once the daemon is stable and the core loop is trusted.

- [ ] Crash detection + auto-restart for user-defined critical apps — extends self-healing to app stability
- [ ] Orphaned LaunchAgent detection and alerting — low-risk health check with high value
- [ ] Broken plist validation — similarly low-risk, high signal
- [ ] DNS health check + auto-flush — common pain point, well-understood fix
- [ ] Swap spike detection with context — improves diagnostic quality
- [ ] Configurable thresholds via config file — power user unlock

### Future Consideration (v2+)

Features to defer until the core daemon is proven reliable.

- [ ] Homebrew outdated package tracking — valuable but not self-healing; surfacing is enough
- [ ] macOS software update notification — same; informational only
- [ ] S.M.A.R.T. disk health monitoring — requires `smartmontools` or IOKit deep dive
- [ ] Cache and temp file cleanup on schedule — risky without careful directory targeting
- [ ] Dashboard historical charts (beyond activity feed) — nice to have, complex to implement

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| LaunchAgent persistence | HIGH | LOW | P1 |
| CPU + RAM + Disk monitoring | HIGH | LOW | P1 |
| Process list with top consumers | HIGH | LOW | P1 |
| Structured activity log | HIGH | MEDIUM | P1 |
| Auto-kill hung processes | HIGH | HIGH | P1 |
| Web dashboard (live metrics) | HIGH | MEDIUM | P1 |
| Activity feed in dashboard | HIGH | MEDIUM | P1 |
| Crash detection + auto-restart | HIGH | HIGH | P2 |
| Orphaned LaunchAgent detection | MEDIUM | MEDIUM | P2 |
| DNS health check + auto-flush | MEDIUM | LOW | P2 |
| Broken plist validation | MEDIUM | LOW | P2 |
| Swap spike detection | MEDIUM | MEDIUM | P2 |
| Configurable thresholds / watch list | MEDIUM | MEDIUM | P2 |
| Homebrew outdated tracking | LOW | MEDIUM | P3 |
| macOS update notification | LOW | LOW | P3 |
| S.M.A.R.T. disk health | MEDIUM | HIGH | P3 |
| Cache cleanup on schedule | LOW | HIGH | P3 |
| Historical charts in dashboard | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for launch (v1)
- P2: Should have, add when core is stable (v1.x)
- P3: Nice to have, future consideration (v2+)

---

## Competitor Feature Analysis

| Feature | iStat Menus | CleanMyMac | OnyX | htop | macOS Guardian (this project) |
|---------|-------------|------------|------|------|-------------------------------|
| CPU/RAM/Disk monitoring | Yes | Partial | No | Yes (terminal) | Yes — daemon + dashboard |
| Process list | Partial (top apps) | Partial | No | Yes | Yes — full list |
| Auto-kill hung processes | No | No | No | Manual only | Yes — automated |
| Crash detection + restart | No | No | No | No | Yes (v1.x) |
| Disk health (S.M.A.R.T.) | Yes | Yes | Yes | No | v2+ |
| Plist / LaunchAgent cleanup | No | Yes (manual) | Yes (manual) | No | Yes (automated detection) |
| DNS flush | No | Partial | Yes (manual) | No | Yes (automated on failure) |
| Homebrew tracking | No | No | No | No | v1.x |
| Activity feed / audit trail | No | No | No | No | Yes — core differentiator |
| Web dashboard | No | No | No | No | Yes — local only |
| Runs as daemon (always on) | Yes (menu bar) | No (on-demand) | No (on-demand) | No | Yes — LaunchAgent |
| Auto-fix without user action | No | No | No | No | Yes — core value prop |
| Configurable watch list | Limited | No | No | No | Yes (v1.x) |

The key competitive gap: every existing tool requires the user to notice a problem and manually trigger a fix. macOS Guardian closes this gap by making the fix automatic.

---

## Sources

- iStat Menus official feature page: https://bjango.com/mac/istatmenus/ (MEDIUM confidence — official product page)
- CleanMyMac features: https://macpaw.com/cleanmymac and https://cleanmymac.com/ (MEDIUM confidence — official)
- OnyX capabilities: https://en.wikipedia.org/wiki/OnyX and community documentation (LOW confidence — secondary sources)
- Lingon X features: https://www.peterborgapps.com/lingon/ (MEDIUM confidence — official)
- Stats open-source monitor: https://github.com/exelban/stats (MEDIUM confidence — GitHub)
- macOS cleanup script with launchd: https://gist.github.com/austinsonger/5c80fc16a2548c9b485653c9ff187ac1 (LOW confidence — community script)
- Memory management risks: TheSweetBits and MacRumors discussion (LOW confidence — community)
- Homebrew update automation: https://nopnithi.medium.com/effortlessly-automate-homebrew-updates-on-macos-24941d0213d1 (LOW confidence — blog)
- Orphaned process cleanup: https://github.com/jhlee0409/proc-janitor (LOW confidence — GitHub community)
- General macOS process management: https://osxhub.com/macos-process-management-ps-kill-launchctl-guide/ (LOW confidence — secondary)

---

*Feature research for: macOS System Monitoring and Self-Healing Daemon (macOS Guardian)*
*Researched: 2026-03-03*
