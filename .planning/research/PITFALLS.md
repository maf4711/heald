# Pitfalls Research

**Domain:** macOS system monitoring / self-healing daemon (macOS Guardian)
**Researched:** 2026-03-03
**Confidence:** HIGH (core SIP/TCC/launchd pitfalls verified via official Apple docs and multiple credible sources)

---

## Critical Pitfalls

### Pitfall 1: Killing Critical System Processes

**What goes wrong:**
A "kill high-CPU processes" rule fires on a process that is essential to macOS — for example `kernel_task`, `WindowServer`, `launchd`, `distnoted`, `cfprefsd`, `opendirectoryd`, `notifyd`, `syslogd`, or user-session framework processes. The system freezes, the login session drops, or the machine becomes unresponsive and requires a hard reboot. This is the single most catastrophic failure mode for an auto-repair daemon.

**Why it happens:**
Developers write rules like "if CPU > 90% for 30s, kill the process." They test against obvious offenders (Chrome renderer, a runaway script) and never test against processes that legitimately spike — `kernel_task` throttles the CPU under thermal load and will always appear as the top CPU consumer. `sysmond` spikes when Activity Monitor is open. `mds`/`mdworker` spikes during Spotlight indexing. The daemon has no way to know whether a spike is "legitimate system work" vs. "runaway user process."

**How to avoid:**
Maintain an explicit allowlist (never-kill list) that is checked before every SIGKILL/SIGTERM. The allowlist must cover at minimum:

- `kernel_task`, `launchd`, `WindowServer`, `loginwindow`
- `cfprefsd`, `distnoted`, `notifyd`, `opendirectoryd`
- `syslogd`, `logd`, `mds`, `mdworker`, `mds_stores`
- `coreaudiod`, `bluetoothd`, `airportd`
- Any process with UID 0 whose parent is `launchd` (system daemons)
- The Guardian daemon's own PID (never self-kill)

Additionally, require multiple consecutive threshold breaches over a configurable window (e.g., 5 consecutive 10-second samples) before acting. A single spike is not a runaway process.

**Warning signs:**
- Rule fires within seconds of threshold breach (no sustained check)
- No allowlist exists — any PID is eligible for termination
- Testing only done on user applications, never on system daemons
- Threshold set at absolute percentage rather than sustained duration

**Phase to address:**
Foundation / Core Monitoring phase. The allowlist and sustained-threshold logic must be in place before any auto-kill capability is wired up. Test against `kernel_task` explicitly.

---

### Pitfall 2: SIP-Protected Paths — Attempting Repairs That Cannot Succeed

**What goes wrong:**
The daemon attempts to repair, modify, or write to SIP-protected paths: `/System`, `/usr` (except `/usr/local`), `/bin`, `/sbin`, `/var` (except `/var/folders`), and pre-installed Apple applications. All writes silently fail or throw `Operation not permitted` errors even when running as root. The daemon logs a "repair attempted" event, the user sees the activity feed as successful, but nothing was actually changed.

**Why it happens:**
Developers assume root privilege means full system access. On macOS since El Capitan (2015), root cannot modify SIP-protected paths without a special Apple-signed entitlement. The `diskutil permissionsrepair` command was removed in the same era. Many tutorials and Stack Overflow answers still show pre-SIP approaches.

**How to avoid:**
- Never attempt to write to `/System`, `/usr` (excluding `/usr/local`), `/bin`, `/sbin`
- Understand that "Disk Permissions Repair" as a maintenance action is completely deprecated — macOS handles system permissions automatically on installs/updates
- For user-space permission problems, use `diskutil resetUserPermissions / $(id -u)` or `repairHomePermissions` in Recovery mode
- Validate every planned repair action against the SIP boundary before implementing it
- Document which "health checks" are read-only observations vs. repair actions — and confirm repair actions are actually achievable

**Warning signs:**
- Planning repairs to `/System` or `/usr/bin` contents
- Referencing `diskutil permissionsrepair` in code or documentation
- No test run as non-root user to verify repair operations actually succeed
- Repair logging says "success" without verifying the post-repair state

**Phase to address:**
Architecture phase. Map every planned health check to its required permission level. Any action that requires SIP-bypass is out of scope — accept it and document it clearly.

---

### Pitfall 3: TCC Permission Prompts Breaking Daemon Behavior

**What goes wrong:**
The daemon silently fails to access files or perform operations because it lacks TCC permissions (Transparency, Consent, and Control). Most commonly: the daemon process itself (not Terminal, not the parent app) needs Full Disk Access to read certain locations, and without it, reads return empty results or permission errors with no user-visible prompt because daemons running as root do not trigger TCC consent dialogs.

**Why it happens:**
TCC is scoped to the specific executable binary. Granting Terminal FDA does not grant it to a daemon binary installed at `/usr/local/bin/guardian`. LaunchDaemons running as root bypass some TCC checks but not all — Full Disk Access (`kTCCServiceSystemPolicyAllFiles`) is still required for certain protected paths (Mail, Messages, iCloud, Safari data). In macOS Sequoia 15, local network access now also requires TCC consent, which can block a local web dashboard from being accessible if implemented incorrectly.

**How to avoid:**
- Identify every path the daemon reads and check whether it requires FDA — test with a non-FDA process
- Install instructions must guide users to grant FDA to the exact daemon binary in System Settings > Privacy & Security > Full Disk Access
- For the local web dashboard: understand that macOS Sequoia's local network TCC applies to apps, not system daemons/root processes — verify this on the target OS version
- Use `tccutil` and test on a fresh user account to confirm all needed permissions are in place
- Log explicit TCC errors, not generic "permission denied," so the user can take corrective action

**Warning signs:**
- Testing done only as the developer's user account (which may have accumulated FDA over time)
- Daemon reads log files and they appear empty rather than erroring
- No install-time check that required TCC permissions are granted

**Phase to address:**
LaunchAgent/Daemon setup phase. The installation procedure must include TCC permission verification. Build a "doctor" command that checks all required permissions before the daemon starts.

---

### Pitfall 4: The Daemon Consumes More Resources Than It Saves

**What goes wrong:**
The monitoring daemon itself becomes a top CPU or RAM consumer, defeating its own purpose. Real-world examples: Apple's own `sysmond` regularly appears at 100% CPU when Activity Monitor samples processes. Microsoft's `wdavdaemon` (Defender) is notorious for consuming 80-300% CPU. A polling loop that samples all processes every second and also writes to disk every second will create measurable system load.

**Why it happens:**
Developers optimize for correctness (detect everything quickly) without measuring the overhead of detection. Process enumeration (`ps`, `proc_pidinfo`, `/proc` equivalent on macOS) is expensive when done at high frequency across all running processes. Disk writes for logging on every check compound the problem. The monitor that "fixes" 1% CPU usage from a misbehaving process while itself consuming 5% CPU is net-negative.

**How to avoid:**
- Default polling interval: 30-60 seconds for resource checks, not 1-5 seconds
- Use `kqueue`/`FSEvents` for event-driven detection instead of polling where possible
- Separate check frequencies: fast checks (30s) for critical metrics, slow checks (5-10 min) for disk health and Homebrew status
- Cap the daemon's own resource usage with `setpriority()` (nice +10) and/or launchd `LowPriorityIO`/`ProcessType: Background`
- Measure: the daemon should consume < 0.5% CPU averaged and < 50MB RAM
- Use macOS `os_log` for structured logging rather than synchronous file I/O

**Warning signs:**
- Polling interval under 10 seconds for all checks
- No `nice` or background priority set in launchd plist
- Synchronous disk writes on every monitoring cycle
- No baseline CPU/RAM measurement of the daemon itself in testing

**Phase to address:**
Core Monitoring phase. Establish resource consumption budgets before feature implementation and measure against them continuously.

---

### Pitfall 5: LaunchDaemon Security Becomes a Privilege Escalation Vector

**What goes wrong:**
The Guardian daemon runs as root and is installed as a LaunchDaemon. If the daemon binary path, the plist file, or the directory containing the binary is world-writable or group-writable, an unprivileged local user can replace the binary with a malicious payload that executes as root on next boot. This is a documented macOS privilege escalation technique (LaunchDaemon hijacking).

**Why it happens:**
Homebrew installs binaries to `/usr/local/bin` (Intel) or `/opt/homebrew/bin` (Apple Silicon), and on many systems `/usr/local/bin` is writable by the current user. If the daemon plist references a binary in a Homebrew-managed path and the daemon runs as root, a local user can replace that binary.

**How to avoid:**
- Install the daemon binary to `/usr/local/sbin/` or `/Library/Application Support/Guardian/` with permissions `755` and owned by `root:wheel`
- The plist in `/Library/LaunchDaemons/` must be owned by `root:wheel` with permissions `644` — launchd rejects plists with incorrect ownership
- The directory containing the binary must not be writable by non-root users
- Never reference Homebrew-managed paths in a root LaunchDaemon plist
- Run `ls -la` on all referenced paths as part of install verification

**Warning signs:**
- Daemon binary installed in `/usr/local/bin/` (Homebrew territory, user-writable)
- Plist file owned by the user account, not root
- Directory permissions allow group or world write

**Phase to address:**
Packaging and Installation phase. Security hardening of file permissions must be a gate before the daemon is considered production-ready.

---

### Pitfall 6: Auto-Homebrew-Update Breaks Developer Toolchains

**What goes wrong:**
The daemon automatically runs `brew upgrade` to "keep the system current." Homebrew upgrades cascade — upgrading one formula forces upgrades of all its dependencies and reverse-dependencies. A `brew upgrade python` silently upgrades Python 3.11 to 3.13, breaking virtual environments, pip-installed tools, and any script pinned to the old Python. Similarly, `brew upgrade openssl` breaks many formulae that were compiled against the old version. The user wakes up to a broken development environment.

**Why it happens:**
Homebrew is designed for developer toolchain management, not system package management. It does not pin to major versions by default. The unattended upgrade scenario is not what Homebrew is optimized for — its own FAQ notes it doesn't support mixing formula versions and all upgrades must be taken to the latest.

**How to avoid:**
- Never run `brew upgrade` unattended without explicit per-package allowlisting
- If Homebrew monitoring is desired, limit to: `brew outdated --quiet` (report only) and `brew update` (update the index only)
- For security-sensitive packages, notify the user rather than auto-upgrading
- If auto-upgrade is desired, scope it to casks (GUI apps) only, not formulae (CLI tools/libraries)
- Provide a dry-run report in the dashboard before executing any Homebrew actions

**Warning signs:**
- `brew upgrade` called with no package argument (upgrades everything)
- No allowlist of which formulae/casks are safe to auto-upgrade
- Testing done only on a machine where nothing depends on the upgraded packages

**Phase to address:**
Homebrew Monitoring phase. Auto-upgrade must be opt-in per package, not default behavior.

---

### Pitfall 7: LaunchAgent Not Loading After Reboot (Plist Reliability Failures)

**What goes wrong:**
The daemon works perfectly during development (loaded manually with `launchctl load`) but fails silently after reboot. Common failure modes: the daemon binary path does not exist at load time (filesystem not mounted yet), the plist has subtle XML errors that `plutil` doesn't catch, the `Disabled` key is set to `true` in the override database, or the plist file permissions are wrong so launchd skips it with "Dubious ownership on file."

**Why it happens:**
Developers test by manually loading the plist and never test a cold reboot. launchd applies different rules at boot (strict path requirements, ownership validation, timing of filesystem availability) vs. manual loading.

**How to avoid:**
- Always validate the plist with `plutil -lint /Library/LaunchDaemons/com.guardian.plist` before installation
- Use `WaitForDependency` or `RunAtLoad: false` + `KeepAlive: true` to handle boot timing
- Set plist ownership: `chown root:wheel` and permissions `644`
- Test against a full cold reboot, not just `launchctl load`
- Check `/var/log/com.apple.xpc.launchd/` and Console.app for load errors
- Set `ThrottleInterval` (e.g., 10 seconds) to prevent crash loops on startup failures
- Configure `StandardOutPath` and `StandardErrorPath` for debugging
- Never use relative paths anywhere in the plist — everything must be absolute

**Warning signs:**
- Only tested with `launchctl load` / `launchctl start`, never with reboot
- No `ThrottleInterval` set (crash-loop risk)
- No stdout/stderr log paths configured (can't debug failures)
- `Disabled` key present in plist (may be overridden in `/var/db/com.apple.xpc.launchd/disabled.plist`)

**Phase to address:**
LaunchDaemon Packaging phase. Add a post-install reboot test to the acceptance criteria.

---

### Pitfall 8: Aggressive Cleanup Deleting Data That Looks Like Garbage

**What goes wrong:**
The daemon identifies "orphaned" or "large" files in `~/Library/Caches/`, `/private/var/folders/`, or `/tmp/` and deletes them as part of routine cleanup. In practice, these locations contain active browser caches, in-progress download fragments, application state files, and temporary work files. Deleting them causes application slowdowns, broken downloads, and data loss. CleanMyMac has documented reports of users losing important data this way.

**Why it happens:**
Cache and temp directories look like obvious cleanup targets. The heuristics (file age, size, extension) are blunt instruments — a 2GB file that is 30 days old might be a video project working file, not a cache. Automated tools cannot reliably distinguish "safe to delete" from "user's important data."

**How to avoid:**
- Never delete files in user-controlled directories (`~/Documents`, `~/Desktop`, `~/Downloads`, `~/Movies`, `~/Music`, `~/Pictures`)
- For system caches (`~/Library/Caches/`): limit to per-application subdirectories that are known-safe (e.g., `com.apple.bird`, not application caches generally)
- `rm` operations should always move to Trash first (use `osascript` with Finder's `delete` command), never bypass Trash
- Require explicit user confirmation for any delete action, regardless of "auto-fix" mode
- Log every deletion with full path, file size, and modification date before executing
- Default behavior: flag for review, not delete

**Warning signs:**
- Cleanup rules based on file age/size without application-specific knowledge
- Using `rm -rf` directly rather than moving to Trash
- No undo mechanism for cleanup actions
- Testing on directories that don't contain personal data

**Phase to address:**
Self-Healing Actions phase. Any cleanup action must pass a safety review: can the user recover this? If not, require explicit confirmation.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Polling every 5 seconds for all checks | Faster detection | Daemon itself consumes 3-10% CPU continuously | Never — split into fast/slow check tiers |
| Hardcoded process names in kill-logic | Simple to implement | Breaks on macOS updates that rename processes | Never — use PID + UID + parent-PID validation |
| Single log file with append-only writes | Simple logging | Log grows unbounded, fills disk over months | Never without rotation (use `os_log` or logrotate) |
| Running the dashboard web server as root | Avoids permission issues | Web server running as root is a severe security risk | Never — drop privileges after binding to port |
| `brew upgrade` without a package list | "Everything stays current" | Breaks developer toolchains without warning | Never unattended — report-only or per-package opt-in |
| Skipping plist permission hardening during dev | Faster iteration | LaunchDaemon is a privilege escalation vector | Acceptable in dev only — must fix before shipping |
| Generic "file age > 30 days = delete" cleanup | Simple rule | Deletes user's actively-used data | Never — require application-specific safe-delete lists |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `launchctl` | Using deprecated `launchctl load/unload` syntax | Use `launchctl bootstrap`/`launchctl bootout` on macOS 10.11+ |
| `diskutil` | Calling `diskutil permissionsRepair` (removed since El Capitan) | Use `diskutil resetUserPermissions` for user-space issues only |
| `/etc/periodic` | Relying on `periodic daily/weekly/monthly` for scheduling | `periodic` binary removed in macOS Sequoia 15 — use launchd plist |
| `ps` / process enumeration | Calling `ps aux` in a tight loop | Use `proc_pidinfo()` via libproc or `sysctl()` for lower overhead |
| `osascript` for GUI automation | Running AppleScript from a root daemon | GUI automation requires a user session — use user-context LaunchAgent not root LaunchDaemon |
| Homebrew | Running `brew` as root | Homebrew explicitly blocks root execution — must run as the user who owns Homebrew |
| `kill`/`SIGKILL` | Sending SIGKILL to launchd-managed processes | launchd will immediately restart them — use `launchctl stop` to honor service lifecycle |
| Log reading via `log show` | Reading all logs in a loop | Use `log stream --predicate` for real-time filtering to avoid loading entire unified log |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Polling all processes every 1-5 seconds | Daemon appears in top 10 CPU consumers | Use 30-60s intervals; event-driven where possible | Immediately on any system with 100+ processes |
| Synchronous disk writes on every check | I/O wait spikes, battery drain on laptops | Buffer log writes, use `os_log`, async I/O | From day one on battery-powered machines |
| Loading entire unified log at each cycle | `log show` takes 5-30 seconds per run | Use `log stream` with predicates for real-time | From day one — `log show` without `--last` reads gigabytes |
| Running `brew outdated` on every cycle | `brew` takes 2-10 seconds per run (updates index) | Run Homebrew checks at most once per hour | When monitoring interval is under 1 hour |
| Web dashboard polling server every second | Dashboard page causes CPU spikes | Use SSE (Server-Sent Events) or WebSocket with server-push | When user keeps dashboard tab open |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Daemon binary in Homebrew-managed path (`/usr/local/bin`, `/opt/homebrew/bin`) | Local privilege escalation — any user can replace binary | Install to `/usr/local/sbin/` or `/Library/Application Support/` with `root:wheel 755` |
| Web dashboard running as root (binding port 80/443 as root) | Web server code executed as root; RCE = instant root compromise | Bind as root, then `setuid()` to a dedicated low-privilege user |
| Plist file writable by non-root | LaunchDaemon hijacking — attacker replaces plist | `chown root:wheel`, `chmod 644` — enforced by launchd |
| Using `AuthorizationExecuteWithPrivileges` for privilege escalation | Deprecated API, phishable password prompt | Use a dedicated LaunchDaemon for privileged operations via XPC |
| Storing credentials or tokens in plist EnvironmentVariables | Credentials readable by any process via `launchctl environ` | Use Keychain for secrets — never plist environment variables |
| Orphaned LaunchDaemon plist after uninstall | Binary path becomes hijackable — any user can create the binary at that path | Uninstall must remove plist and verify binary is gone |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| "Fixed: Killed process X" with no context | User doesn't know if X was important; anxiety about system | Log what the process was, why it was killed, and whether it restarted |
| Auto-fixing without any notification | User discovers changes via broken workflow, not dashboard | Activity feed must show every action in real time, even if no dashboard is open (system notification) |
| Dashboard not showing "all clear" state | User assumes monitoring stopped working | Explicitly show last-check timestamp and "system healthy" when nothing is wrong |
| Aggressive thresholds causing constant churn | Process killed → restarts → killed in a loop | Require sustained threshold breach AND exponential backoff between repeated kills of same process |
| No way to whitelist processes | User's legitimate high-CPU app (video encode, compilation) gets killed | Per-process allowlist in config file that user can edit |

---

## "Looks Done But Isn't" Checklist

- [ ] **Process kill logic:** Verify the allowlist covers all critical system processes — test by checking `ps aux` output against the allowlist, not just known-bad processes
- [ ] **LaunchDaemon loading:** Verify with a cold reboot, not just `launchctl load` — check Console.app for load errors
- [ ] **TCC permissions:** Verify the daemon binary (not Terminal) has FDA — test by revoking FDA and confirming graceful degradation, not silent failure
- [ ] **SIP compliance:** Verify every planned "repair" action succeeds as root — test each action explicitly before claiming it works
- [ ] **Homebrew operations:** Verify `brew` commands run as the Homebrew-owning user, not root — Homebrew will refuse to run as root
- [ ] **Log rotation:** Verify log files have a size limit and rotation policy — check disk usage after 30 days of simulated operation
- [ ] **Resource consumption:** Measure daemon CPU/RAM after 24 hours of continuous operation, not just during testing
- [ ] **Cleanup safety:** Verify every file deletion goes to Trash (recoverable), not permanent `rm`
- [ ] **Crash recovery:** Verify `ThrottleInterval` is set so a crashing daemon doesn't spin at 100% CPU in a restart loop
- [ ] **`/etc/periodic` removal:** Verify no code depends on `periodic` binary (removed in macOS Sequoia 15)

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Killed wrong process (recoverable — process restarts) | LOW | Process restarts automatically via launchd; user may need to reopen app |
| Killed `WindowServer` or `loginwindow` | HIGH | Session drops, user must log back in; all unsaved work lost |
| Homebrew broken by auto-upgrade | MEDIUM | `brew doctor`; may require `brew bundle` from saved Brewfile; worst case: reinstall Homebrew |
| Daemon in crash loop (no ThrottleInterval) | MEDIUM | `launchctl bootout system/com.guardian` to stop loop; fix and reload |
| LaunchDaemon hijacked (security incident) | HIGH | Identify what the malicious binary did; reinstall from clean source; rotate credentials |
| Accidental cleanup of user data | HIGH | Restore from Time Machine (if enabled); no in-tool recovery if Trash was bypassed |
| TCC permission silently blocking reads | LOW | Grant Full Disk Access to daemon binary in System Settings; restart daemon |
| SIP repair action silently failing | LOW | Log shows failure; document as "not achievable by this tool" and remove the feature |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Killing critical system processes | Phase 1: Core Monitoring (before any auto-action) | Integration test: allowlist covers `kernel_task`, `WindowServer`, `launchd`, `loginwindow` |
| SIP-blocked repair actions | Phase 1: Architecture design | Verify each planned action succeeds as root in test environment |
| TCC permission failures | Phase 2: LaunchDaemon Setup | Install-time doctor command verifies FDA granted to daemon binary |
| Daemon resource overconsumption | Phase 2: Core Monitoring implementation | Continuous measurement: < 0.5% CPU avg, < 50MB RAM after 24h |
| LaunchDaemon security / hijacking | Phase 3: Packaging | File permission audit: all paths `root:wheel`, no user-writable directories |
| Homebrew auto-upgrade breaking toolchains | Phase 4: Homebrew Monitoring | Homebrew auto-upgrade is report-only by default; upgrade requires explicit opt-in |
| LaunchAgent not loading after reboot | Phase 2: LaunchDaemon Setup | Cold reboot test as acceptance criterion; Console.app shows no load errors |
| Aggressive cleanup causing data loss | Phase 5: Self-Healing Actions | All deletions go to Trash; no `rm -rf` on user-controlled directories |
| Web dashboard security (running as root) | Phase 6: Dashboard | Dashboard server drops privileges after binding; no root-level HTTP handler |
| `/etc/periodic` deprecation (Sequoia) | Phase 1: Architecture | Verify on Darwin 25.4.0 (Sequoia 15) — use launchd exclusively for scheduling |

---

## Sources

- Apple Support — System Integrity Protection: https://support.apple.com/en-us/102149 (HIGH confidence)
- launchd.info — Comprehensive launchd Reference: https://launchd.info/ (HIGH confidence)
- SentinelOne — macOS Sequoia Privacy and Security Changes: https://www.sentinelone.com/blog/macos-sequoia-whats-new-in-privacy-and-security-for-enterprise/ (MEDIUM confidence)
- bradleyjkemp.dev — LaunchDaemon Hijacking via Insecure Permissions: https://bradleyjkemp.dev/post/launchdaemon-hijacking/ (MEDIUM confidence)
- PT SWARM — Daemon Ex Plist LPE via macOS Daemons: https://swarm.ptsecurity.com/daemon-ex-plist-lpe-via-macos-daemons/ (MEDIUM confidence)
- Heise Online — macOS 15 removes `periodic`: https://www.heise.de/en/news/Cleanup-scripts-macOS-15-removes-periodic-but-no-longer-needs-it-10007870.html (MEDIUM confidence)
- macpaw.com — Why you can't repair disk permissions: https://macpaw.com/how-to/repair-disk-permissions (MEDIUM confidence)
- osxdaily.com — sysmond High CPU (self-monitoring paradox): https://osxdaily.com/2024/06/01/sysmond-high-cpu-use-mac-reason-fix/ (MEDIUM confidence)
- SentinelOne Labs — Bypassing TCC by accident and design: https://www.sentinelone.com/labs/bypassing-macos-tcc-user-privacy-protections-by-accident-and-design/ (MEDIUM confidence)
- Sebastian De Deyne — How Homebrew auto-update breaks environments: https://sebastiandedeyne.com/how-not-to-update-every-package-in-existence-break-your-local-environment-and-spend-the-afternoon-dealing-with-things-you-did-not-want-to-deal-with-when-installing-a-package-with-brew (MEDIUM confidence)
- Microsoft Security Blog — CVE-2024-44243 SIP bypass via kernel extensions: https://www.microsoft.com/en-us/security/blog/2025/01/13/analyzing-cve-2024-44243-a-macos-system-integrity-protection-bypass-through-kernel-extensions/ (HIGH confidence)

---
*Pitfalls research for: macOS system monitoring / self-healing daemon*
*Researched: 2026-03-03*
