# Roadmap: heald

## Overview

Seven phases build heald from the ground up along a strict dependency chain: the daemon skeleton must exist before monitoring can run; monitoring must produce data before storage has anything to persist; storage must exist before the cloud dashboard can display history; the cloud API and multi-machine dashboard must be visible before any autonomous healing fires; core kill logic is separated from safer extended health checks; and AI analysis with notifications composes on top of a stable, observable system. The cloud dashboard and multi-machine API are built together in Phase 4 — they are the same delivery boundary because the API is what makes multi-machine possible, and the dashboard is what makes the API valuable. Every automated action heald takes is observable in the cloud dashboard and logged to the audit trail before that action is possible — that is the governing constraint of the build order.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Daemon Foundation** - LaunchAgent skeleton, install/uninstall, TCC verification, graceful shutdown (completed 2026-03-03)
- [x] **Phase 2: Metric Collector** - CPU, RAM, disk, and process data at correct polling intervals (completed 2026-03-03)
- [ ] **Phase 3: Storage Layer** - SQLite ring buffer and NDJSON audit log with retention management
- [ ] **Phase 4: Cloud Dashboard and API** - Next.js on Vercel at heald.meradOS.com, cloud API with auth, multi-machine view, local metric buffer
- [ ] **Phase 5: Self-Healing Core** - Process safelist, sustained-threshold kill logic, SIGTERM/SIGKILL sequence
- [ ] **Phase 6: Extended Health Checks** - Crash detection, DNS flush, orphaned LaunchAgent and plist scanning, Homebrew/update reporting
- [ ] **Phase 7: AI, Notifications, and Polish** - Ollama integration, AI-driven decisions with dashboard marking, daily email report, macOS notifications

## Phase Details

### Phase 1: Daemon Foundation
**Goal**: A persistent daemon process runs reliably under launchd, starts at login, survives reboots, shuts down cleanly, and can be installed and removed without manual steps.
**Depends on**: Nothing (first phase)
**Requirements**: DAEM-01, DAEM-02, DAEM-03, DAEM-04, DAEM-05
**Success Criteria** (what must be TRUE):
  1. Running `launchctl list | grep heald` shows the daemon running after a cold reboot with no manual intervention.
  2. Sending SIGTERM (via `launchctl stop`) causes the daemon to exit cleanly with no corrupted state and a confirmation log entry.
  3. The daemon consumes less than 1% CPU and less than 50MB RAM while idle, measurable via Activity Monitor or `ps`.
  4. Running `./install.sh` on a clean machine sets up all Homebrew dependencies and loads the LaunchAgent in one step.
  5. Running `./uninstall.sh` removes the LaunchAgent, stops the daemon, and leaves no leftover files.
**Plans**: 2 plans

Plans:
- [ ] 01-01-PLAN.md — Swift package skeleton, HealdService with SIGTERM handling, LaunchAgent plist template
- [ ] 01-02-PLAN.md — install.sh (Homebrew + build + deploy) and uninstall.sh (clean removal)

### Phase 2: Metric Collector
**Goal**: The daemon continuously collects accurate system metrics — CPU, RAM, disk, and process data — at appropriate polling intervals, within the resource budget.
**Depends on**: Phase 1
**Requirements**: MON-01, MON-02, MON-03, MON-04, MON-05, MON-06, MON-07, MON-08
**Success Criteria** (what must be TRUE):
  1. CPU usage (overall and per-core) updates every 5 seconds and is visible in the daemon's internal state.
  2. RAM breakdown (used, wired, compressed, swap) is captured every 5 seconds with correct values matching `vm_stat` output.
  3. Disk space per volume and disk I/O activity are captured on each polling cycle.
  4. A ranked list of top CPU/RAM consumers is produced from each process snapshot, matching Activity Monitor rankings.
  5. Swap spikes are detected and the responsible process is identified and logged within one polling cycle of the spike occurring.
  6. S.M.A.R.T. disk health status is read and reflects the actual drive health reported by `diskutil info`.
**Plans**: 4 plans

Plans:
- [ ] 02-01-PLAN.md — Metric snapshot models, MetricsStore actor, Logger.collector
- [ ] 02-02-PLAN.md — CPUCollector (tick-delta) and RAMCollector (host_statistics64 + swap spike)
- [ ] 02-03-PLAN.md — DiskCollector (space/IO/SMART) and ProcessCollector (ps ranking)
- [ ] 02-04-PLAN.md — Wire all collectors into HealdService, debug JSON status file

### Phase 3: Storage Layer
**Goal**: All metrics and system events are persisted to disk in a queryable form that survives daemon restarts, with automatic retention management preventing unbounded disk growth.
**Depends on**: Phase 2
**Requirements**: LOG-01, LOG-02, LOG-03, LOG-04
**Success Criteria** (what must be TRUE):
  1. After restarting the daemon, historical metrics from the previous session are still queryable from the SQLite database.
  2. Every system event (detected problem, triggered action) appears in the NDJSON activity log with a timestamp and before/after state.
  3. After the configured retention window elapses, old metric records are removed and database file size stays bounded.
  4. The activity log can be `grep`-ed by a human without any tooling to find what happened at a given time.
**Plans**: TBD

### Phase 4: Cloud Dashboard and API
**Goal**: A Next.js web app at heald.meradOS.com (hosted on Vercel) shows live metrics, activity feeds, and health status for all connected Macs; a cloud API ingests metrics pushed by each local daemon with authentication; local daemons buffer and retry on connectivity loss.
**Depends on**: Phase 3
**Requirements**: CLOUD-01, CLOUD-02, CLOUD-03, CLOUD-04, CLOUD-05, CLOUD-06, DASH-02, DASH-03, DASH-04, DASH-05
**Success Criteria** (what must be TRUE):
  1. Opening heald.meradOS.com in a browser shows live CPU, RAM, disk, and process data for the local Mac, updating without page refresh.
  2. A second Mac running the heald daemon appears in the dashboard within one push interval alongside the first — both machines visible simultaneously.
  3. A daemon without a valid API key receives a 401 response and its metrics are rejected; a daemon with a valid key pushes successfully.
  4. When the cloud API is unreachable, the daemon logs metrics to a local buffer; when connectivity resumes, buffered metrics are pushed in order without data loss.
  5. The activity feed shows a chronological list of all logged events per machine, with AI-driven fixes visually distinguished from rule-based fixes (e.g. an "AI" badge).
  6. Running a single curl-piped install command on a new Mac installs heald, configures the API key, loads the LaunchAgent, and starts pushing metrics without additional steps.
**Plans**: TBD

### Phase 5: Self-Healing Core
**Goal**: Hung processes are automatically killed using a sustained-threshold check against a comprehensive safelist, with every kill action logged to the audit trail and visible in the cloud dashboard.
**Depends on**: Phase 4
**Requirements**: HEAL-01, HEAL-02, HEAL-03
**Success Criteria** (what must be TRUE):
  1. A process sustaining over 90% CPU for 5 consecutive minutes and not on the safelist is automatically killed; the kill appears in the dashboard activity feed within one polling cycle.
  2. The daemon sends SIGTERM first; if the process does not exit within the configured timeout, SIGKILL is sent; both events are logged separately.
  3. `kernel_task`, `WindowServer`, `loginwindow`, and `launchd` are never killed regardless of their CPU readings — verified by attempting to trigger the rule against them in a test scenario.
  4. Every kill action includes the process name, PID, CPU reading, duration at threshold, and timestamp in the audit log.
**Plans**: TBD

### Phase 6: Extended Health Checks
**Goal**: heald detects and remedies a wider class of system problems: crashed critical apps are restarted, DNS failures are flushed, orphaned LaunchAgents and broken plists are flagged, and pending Homebrew and macOS updates are reported.
**Depends on**: Phase 5
**Requirements**: HEAL-04, HEAL-05, HEAL-06, HEAL-07, HLTH-01, HLTH-02, HLTH-03
**Success Criteria** (what must be TRUE):
  1. When a process in the user-configured watch list is not running, the daemon detects it within one health-check cycle and restarts it; the restart appears in the activity feed.
  2. When DNS resolution fails, the daemon flushes the DNS cache automatically and logs the flush action with a before/after resolution test result.
  3. Any LaunchAgent plist whose referenced binary no longer exists at the expected path is flagged in the dashboard with the plist path and missing binary path.
  4. Any plist failing `plutil -lint` validation is flagged in the dashboard with the specific validation error.
  5. The dashboard shows a list of outdated Homebrew packages and pending macOS updates, updated on the health-check schedule (not every 5-second tick).
**Plans**: TBD

### Phase 7: AI, Notifications, and Polish
**Goal**: Ollama provides intelligent kill decisions and natural-language daily summaries; AI-driven actions are clearly marked in the dashboard; users receive macOS native notifications on critical events and a daily email report at 18:00.
**Depends on**: Phase 6
**Requirements**: AI-01, AI-02, AI-03, AI-04, AI-05, NOTF-01, NOTF-02, NOTF-03, NOTF-04
**Success Criteria** (what must be TRUE):
  1. When a process exceeds thresholds, Ollama is consulted with context about the process and recent system state; its decision and reasoning are logged and visible in the dashboard with a clear "AI" visual marker.
  2. When Ollama is unavailable or returns an error, the rules-based fallback fires automatically; the activity entry is marked as rule-based (not AI) so the distinction is always visible in the dashboard.
  3. A macOS native notification appears when a process is killed, when disk is near capacity, or when a critical app crashes — without any user action required.
  4. At 18:00 each day, an email report arrives at foellmer@mac.com containing the day's events and an AI-generated natural-language summary of what happened.
  5. Ollama is installed automatically by the install script if not already present; the `heald doctor` command reports Ollama availability status.
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Daemon Foundation | 2/2 | Complete   | 2026-03-03 |
| 2. Metric Collector | 4/4 | Complete   | 2026-03-03 |
| 3. Storage Layer | 0/TBD | Not started | - |
| 4. Cloud Dashboard and API | 0/TBD | Not started | - |
| 5. Self-Healing Core | 0/TBD | Not started | - |
| 6. Extended Health Checks | 0/TBD | Not started | - |
| 7. AI, Notifications, and Polish | 0/TBD | Not started | - |
