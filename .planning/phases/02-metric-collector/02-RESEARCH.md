# Phase 2: Metric Collector - Research

**Researched:** 2026-03-03
**Domain:** macOS system metrics via Mach kernel APIs, Darwin syscalls, IOKit, and Darwin libproc
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **CPU metrics**: Track overall CPU usage AND per-core breakdown. Polling interval: 5 seconds.
- **RAM metrics**: Track Used, Wired, Compressed, Swap as specified in MON-02. Polling interval: 5 seconds.
- **Process snapshots**: Top 25 by CPU and top 25 by RAM as two separate ranked lists. Include all processes (system + user) and tag system daemons with a `system` flag.
- The `system` flag feeds Phase 5 safelist logic — system-tagged processes are never killed.

### Claude's Discretion
- **Polling intervals for disk/S.M.A.R.T.**: Choose appropriate intervals based on how fast each metric changes. Disk space changes slowly; S.M.A.R.T. even slower. CPU/RAM at 5s is fixed.
- **Process metadata fields**: Pick fields that feed well into downstream phases. PID + name + CPU% + RAM are minimum; consider parent PID, user, start time if useful.
- **Swap spike detection**: Choose detection strategy (absolute threshold, rate-of-change, or both) that catches real problems without false positives on normal macOS memory behavior.
- **Swap spike attribution**: Choose between delta tracking or highest-RAM heuristic. Accuracy matters for Phase 5 kill decisions.
- **Memory pressure tracking**: Decide whether to include macOS memory pressure level (nominal/warn/critical) as a first-class metric alongside raw RAM numbers.
- **Spike severity signaling**: Decide how to signal swap spikes within Phase 2's scope (OSLog levels, etc.). Full notifications come in Phase 7.
- **Debug access**: Decide whether to expose current metrics via OSLog only, a JSON status file, or another pragmatic method before the cloud dashboard arrives in Phase 4.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

## Summary

Phase 2 replaces the idle skeleton in `HealdService.run()` with active polling loops that collect CPU, RAM, disk, and process metrics using macOS kernel APIs. All required APIs are Darwin/Mach system calls and IOKit — no third-party Swift packages are needed. The core APIs are stable, well-proven, and used by production apps like Stats and Activity Monitor.

The dominant pattern is **tick-delta sampling**: capture absolute counters (CPU ticks, disk I/O byte totals, swap page counts), store them, and compute rates on the next interval. This is how `top`, `iostat`, and Activity Monitor work. CPU per-core requires `host_processor_info` with state arrays; RAM requires `host_statistics64` (via `vm_statistics64`); disk I/O requires IOKit registry traversal; process metrics are best collected via `ps -Aceo pid,pcpu,rss,uid,comm -r` which is fast (≈44ms), cross-user, and returns both CPU and RSS memory in one call.

For SMART disk health, the cleanest approach is `diskutil info -plist <BSDName>` parsed via `PropertyListSerialization` — the key `SMARTStatus` contains `"Verified"` or `"Failing"`. This avoids IOKit SMART plugin complexity entirely and reflects exactly what `diskutil info` reports. SMART polling is appropriate at a long interval (5–10 minutes) since drive health changes on timescales of days/weeks.

**Primary recommendation:** Implement one `actor MetricsStore` for safe concurrent state, and one `Service`-conforming struct per metric domain (CPU, RAM, Disk, Process). Each service runs its own `withGracefulShutdownHandler` loop with `Task.sleep` delays matching the required polling interval. No new SPM packages are needed.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MON-01 | CPU-Auslastung überwachen (gesamt + pro Core, 5s Polling) | `host_processor_info` with `PROCESSOR_CPU_LOAD_INFO` + tick-delta pattern; verified via Stats source |
| MON-02 | RAM/Memory Pressure überwachen (Used, Wired, Compressed, Swap) | `host_statistics64` with `HOST_VM_INFO64` returns `vm_statistics64_data_t` with all required fields; swap via `sysctlbyname("vm.swapusage")`; pressure via `sysctlbyname("kern.memorystatus_vm_pressure_level")` |
| MON-03 | Disk Space pro Volume überwachen | `statfs()` per mounted volume via `FileManager.mountedVolumeURLs`; `f_bfree * f_bsize` = correct free bytes; verified vs `df` output |
| MON-04 | Disk I/O Activity überwachen | IOKit `IOBSDNameMatching` → parent traversal → `"Statistics"` dict with `"Bytes (Read)"` / `"Bytes (Write)"` cumulative counters; delta-per-interval = throughput |
| MON-05 | Prozessliste mit CPU/RAM pro Prozess erfassen | `ps -Aceo pid,pcpu,rss,uid,comm -r` (44ms, cross-user, sorted by CPU); UID < 500 → `system` flag |
| MON-06 | Top-Ressourcenverbraucher identifizieren und ranken | CPU ranking: `-r` flag on `ps` (sorted by %CPU descending); RAM ranking: second `ps` sort by `rss` in Swift after parsing |
| MON-07 | Swap-Spikes erkennen und verursachenden Prozess loggen | Rate-of-change on `xsw_usage.xsu_used` between 5s samples; attribution via highest-RSS process in the ranked list at spike time |
| MON-08 | S.M.A.R.T. Disk Health überwachen | `diskutil info -plist <BSDName>` → `PropertyListSerialization` → `SMARTStatus` key (`"Verified"` / `"Failing"`) + `SMARTDeviceSpecificKeysMayVaryNotGuaranteed` dict for wear/temperature |
</phase_requirements>

---

## Standard Stack

### Core
| Library/API | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| Mach kernel API (`host_processor_info`, `host_statistics64`, `host_info`) | Darwin (macOS 15) | CPU and RAM metrics from kernel | The canonical source; same APIs used by Activity Monitor and top |
| Darwin syscalls (`sysctlbyname`, `statfs`) | POSIX + Darwin | Swap usage, disk space, memory pressure | Single-call access; stable across macOS versions |
| IOKit framework (`import IOKit`) | macOS 15 (system framework) | Disk I/O byte counters via IOBlockStorageDriver statistics | Only API that provides cumulative read/write byte counts from hardware |
| Foundation (`FileManager`, `Process`, `PropertyListSerialization`) | Swift stdlib | Volume enumeration, subprocess execution, plist parsing | System-native; no external deps |
| ServiceLifecycle (`swift-server/swift-service-lifecycle` v2.x) | Already in Package.swift | Polling loop lifecycle, graceful shutdown | Already used in Phase 1 |

### Supporting
| Library/API | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| OSLog (`.collector` category) | macOS 15 | Structured metric event logging | Every collection cycle result and anomaly |
| `NSRunningApplication` | macOS | Resolve user-visible app name from PID | Supplement `ps` `comm` field for GUI apps |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `ps` subprocess | `proc_pidinfo` + `PROC_PIDTASKINFO` directly | `proc_pidinfo` cannot read metrics for processes owned by other users without special entitlements; `ps` handles cross-user correctly at 44ms cost |
| `top` subprocess | `ps` subprocess | `top -l 1` takes ≈600ms; `ps` takes ≈44ms — 14x faster. Use `ps`. |
| IOKit NVMe SMART plugin (`IONVMeSMARTInterface`) | `diskutil info -plist` | IOKit plugin is complex and Apple Silicon support is inconsistent; `diskutil info -plist` gives `SMARTStatus` directly, is simpler, and matches Activity Monitor behavior |
| `statvfs` | `statfs` | `statvfs` returns incorrect block counts on macOS (f_bsize 256× too large); use `statfs` with `f_bfree * f_bsize` |

**Installation:** No new packages required. IOKit is a system framework, importable with `import IOKit`. `Foundation` is already available. No `Package.swift` changes needed for this phase.

---

## Architecture Patterns

### Recommended Project Structure
```
Sources/heald/
├── HealdApp.swift         # Existing — no changes
├── HealdService.swift     # MODIFIED — wires collector services into ServiceGroup
├── Logging.swift          # MODIFIED — activate .collector category
├── main.swift             # Existing — no changes
├── MetricsStore.swift     # NEW — actor storing current snapshot, exposed to downstream phases
├── Collectors/
│   ├── CPUCollector.swift        # NEW — Service; host_processor_info tick-delta
│   ├── RAMCollector.swift        # NEW — Service; host_statistics64 + sysctlbyname swap
│   ├── DiskCollector.swift       # NEW — Service; statfs space + IOKit I/O + diskutil SMART
│   └── ProcessCollector.swift    # NEW — Service; ps subprocess + ranking
└── Models/
    ├── CPUSnapshot.swift          # NEW — Sendable value type
    ├── RAMSnapshot.swift          # NEW — Sendable value type
    ├── DiskSnapshot.swift         # NEW — Sendable value type
    └── ProcessSnapshot.swift      # NEW — Sendable value type
```

### Pattern 1: Polling Service with Graceful Shutdown
**What:** Each collector conforms to `Service` and runs a `repeat { ... } while !shutdown` loop with `withGracefulShutdownHandler`.
**When to use:** Every metric domain (CPU, RAM, Disk, Process).
**Example:**
```swift
// Source: https://swiftonserver.com/introduction-to-swift-service-lifecycle/
// Verified pattern from Swift Service Lifecycle documentation
struct CPUCollector: Service {
    let store: MetricsStore

    func run() async throws {
        var shutdown = false
        try await withGracefulShutdownHandler {
            repeat {
                let snapshot = try readCPU()
                await store.updateCPU(snapshot)
                try await Task.sleep(for: .seconds(5))
            } while !shutdown
        } onGracefulShutdown: {
            shutdown = true
        }
    }
}
```

### Pattern 2: Tick-Delta CPU Sampling
**What:** Store the previous `processor_info_array_t` snapshot; compute per-core usage as `(inUse_now - inUse_prev) / (total_now - total_prev)`.
**When to use:** Overall CPU and per-core CPU (MON-01).
**Example:**
```swift
// Source: https://github.com/exelban/stats/blob/master/Modules/CPU/readers.swift
// HIGH confidence — read from source, cross-checked against Mach API docs

var cpuInfo: processor_info_array_t?
var prevCpuInfo: processor_info_array_t?
var numCPUsU: natural_t = 0
var numCpuInfo: mach_msg_type_number_t = 0
var numPrevCpuInfo: mach_msg_type_number_t = 0

func readCPU() -> CPUSnapshot {
    let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                     &numCPUsU, &cpuInfo, &numCpuInfo)
    guard result == KERN_SUCCESS, let info = cpuInfo else { return .zero }

    var coreUsages: [Double] = []
    for i in 0..<Int(numCPUsU) {
        let base = Int(CPU_STATE_MAX) * i
        let inUse: Int32
        let total: Int32
        if let prev = prevCpuInfo {
            inUse = (info[base + Int(CPU_STATE_USER)]   - prev[base + Int(CPU_STATE_USER)])
                  + (info[base + Int(CPU_STATE_SYSTEM)] - prev[base + Int(CPU_STATE_SYSTEM)])
                  + (info[base + Int(CPU_STATE_NICE)]   - prev[base + Int(CPU_STATE_NICE)])
            let idle = info[base + Int(CPU_STATE_IDLE)] - prev[base + Int(CPU_STATE_IDLE)]
            total = inUse + idle
        } else {
            inUse = info[base + Int(CPU_STATE_USER)] + info[base + Int(CPU_STATE_SYSTEM)] + info[base + Int(CPU_STATE_NICE)]
            let idle = info[base + Int(CPU_STATE_IDLE)]
            total = inUse + idle
        }
        coreUsages.append(total > 0 ? Double(inUse) / Double(total) : 0.0)
    }

    if let prev = prevCpuInfo {
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), vm_size_t(numPrevCpuInfo))
    }
    prevCpuInfo = cpuInfo
    numPrevCpuInfo = numCpuInfo

    let overall = coreUsages.isEmpty ? 0.0 : coreUsages.reduce(0, +) / Double(coreUsages.count)
    return CPUSnapshot(overall: overall, perCore: coreUsages)
}
```

### Pattern 3: RAM via vm_statistics64
**What:** Single `host_statistics64` call returns all RAM breakdown fields. Multiply page counts by `vm_page_size`.
**When to use:** RAM metrics (MON-02).
**Example:**
```swift
// Source: https://github.com/exelban/stats/blob/master/Modules/RAM/readers.swift
// HIGH confidence — verified against source and vm_stat(1) man page

func readRAM() -> RAMSnapshot {
    var stats = vm_statistics64()
    var count = UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return .zero }

    let pageSize = Double(vm_page_size)
    let wired      = Double(stats.wire_count)           * pageSize
    let active     = Double(stats.active_count)         * pageSize
    let inactive   = Double(stats.inactive_count)       * pageSize
    let compressed = Double(stats.compressor_page_count) * pageSize
    let speculative = Double(stats.speculative_count)   * pageSize
    let purgeable  = Double(stats.purgeable_count)      * pageSize
    let external   = Double(stats.external_page_count)  * pageSize
    let used       = active + inactive + speculative + wired + compressed - purgeable - external

    // Swap
    var swap = xsw_usage()
    var swapSize = MemoryLayout<xsw_usage>.size
    sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

    // Memory pressure: 1=normal, 2=warning, 4=critical
    var pressure: Int = 0
    var pressureSize = MemoryLayout<Int>.size
    sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0)

    return RAMSnapshot(
        wired: wired, active: active, compressed: compressed,
        used: used, swapUsed: Double(swap.xsu_used), swapTotal: Double(swap.xsu_total),
        pressureLevel: pressure  // 1=normal, 2=warn, 4=critical
    )
}
```

### Pattern 4: Disk Space via statfs
**What:** Enumerate volumes with `FileManager.mountedVolumeURLs`, call `statfs()` per volume, compute `Int64(f_bfree) * Int64(f_bsize)`.
**When to use:** Disk space per volume (MON-03). Poll every 60 seconds — disk space changes slowly.
**Example:**
```swift
// Source: Verified via local statfs() test vs df(1) output — matched to byte.
// f_bfree * f_bsize is correct on macOS. Do NOT use statvfs (incorrect f_bsize on macOS).
func readDiskSpace() -> [VolumeSpaceInfo] {
    guard let urls = FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: [.volumeNameKey, .volumeIsInternalKey],
        options: .skipHiddenVolumes
    ) else { return [] }

    return urls.compactMap { url in
        var stat = statfs()
        guard statfs(url.path, &stat) == 0 else { return nil }
        let totalBytes = Int64(stat.f_blocks) * Int64(stat.f_bsize)
        let freeBytes  = Int64(stat.f_bfree)  * Int64(stat.f_bsize)
        return VolumeSpaceInfo(url: url, totalBytes: totalBytes, freeBytes: freeBytes)
    }
}
```

### Pattern 5: Disk I/O via IOKit Statistics
**What:** For each physical disk (BSD name like `disk0`), traverse IOKit to parent IOBlockStorageDriver, read `"Statistics"` dictionary with cumulative `"Bytes (Read)"` / `"Bytes (Write)"` counters, compute deltas.
**When to use:** Disk I/O throughput (MON-04). Poll every 5 seconds.
**Example:**
```swift
// Source: https://github.com/exelban/stats/blob/master/Modules/Disk/readers.swift
// HIGH confidence — read directly from production source

func readDiskIO(bsdName: String, prev: DiskIOCounters?) -> DiskIODelta? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault,
                  IOBSDNameMatching(kIOMainPortDefault, 0, bsdName))
    guard service != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(service) }

    // Traverse to parent (IOBlockStorageDriver level)
    var parent = io_registry_entry_t(IO_OBJECT_NULL)
    var current = service
    IOObjectRetain(current)
    while IOObjectConformsTo(current, "IOBlockStorageDriver") == 0 {
        guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS,
              parent != IO_OBJECT_NULL else { IOObjectRelease(current); return nil }
        IOObjectRelease(current)
        current = parent
    }
    defer { IOObjectRelease(current) }

    guard let props = IORegistryEntryCreateCFProperties(current, nil, kCFAllocatorDefault, 0)
                      .takeRetainedValue() as? NSDictionary,
          let stats = props["Statistics"] as? NSDictionary,
          let readBytes  = stats["Bytes (Read)"]  as? Int64,
          let writeBytes = stats["Bytes (Write)"] as? Int64
    else { return nil }

    if let p = prev {
        return DiskIODelta(readBytes: readBytes - p.readBytes, writeBytes: writeBytes - p.writeBytes)
    }
    return nil
}
```

### Pattern 6: Process List via ps subprocess
**What:** Run `ps -Aceo pid,pcpu,rss,uid,comm -r`, parse output; flag processes with UID < 500 as `system`.
**When to use:** Process metrics (MON-05, MON-06). Poll every 5 seconds.
**Example:**
```swift
// Source: https://github.com/exelban/stats/blob/master/Modules/CPU/readers.swift
// Pattern verified locally: ps -Aceo pid,pcpu,rss,uid,comm -r takes ~44ms vs top -l 1 ~600ms

func readProcesses() -> ProcessSnapshot {
    let task = Process()
    task.launchPath = "/bin/ps"
    task.arguments = ["-Aceo", "pid,pcpu,rss,uid,comm", "-r"]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    task.waitUntilExit()

    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    var entries: [ProcessEntry] = []
    for line in output.components(separatedBy: "\n").dropFirst() {  // skip header
        let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard parts.count >= 5,
              let pid  = Int32(parts[0]),
              let cpu  = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
              let rss  = Int64(parts[2]),
              let uid  = Int(parts[3])
        else { continue }
        let name    = String(parts[4])
        let isSystem = uid < 500
        entries.append(ProcessEntry(pid: pid, name: name, cpuPercent: cpu,
                                    ramBytes: rss * 1024, uid: uid, isSystem: isSystem))
    }

    let topByCPU = Array(entries.prefix(25))   // already sorted by CPU via -r
    let topByRAM = Array(entries.sorted { $0.ramBytes > $1.ramBytes }.prefix(25))
    return ProcessSnapshot(byCPU: topByCPU, byRAM: topByRAM)
}
```

### Pattern 7: SMART Status via diskutil
**What:** Run `diskutil info -plist <BSDName>` on each physical disk, parse plist, extract `SMARTStatus` and `SMARTDeviceSpecificKeysMayVaryNotGuaranteed`. Poll every 5 minutes.
**When to use:** SMART health (MON-08).
**Example:**
```swift
// Source: Verified locally — diskutil info -plist disk0 | grep SMARTStatus returns "Verified"
// Key SMARTDeviceSpecificKeysMayVaryNotGuaranteed contains AVAILABLE_SPARE, PERCENTAGE_USED, TEMPERATURE

func readSMART(bsdName: String) -> SMARTInfo? {
    let task = Process()
    task.launchPath = "/usr/sbin/diskutil"
    task.arguments = ["info", "-plist", bsdName]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let status = plist["SMARTStatus"] as? String
    else { return nil }

    let specific = plist["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any]
    return SMARTInfo(
        status: status,                                           // "Verified" or "Failing"
        availableSpare: specific?["AVAILABLE_SPARE"] as? Int,
        percentageUsed: specific?["PERCENTAGE_USED"] as? Int,
        temperature: specific?["TEMPERATURE"] as? Int,
        powerOnHours: specific?["POWER_ON_HOURS_0"] as? Int
    )
}
```

### Pattern 8: MetricsStore as Actor
**What:** Central actor holding the latest snapshot of all metric types. Collectors write; downstream phases (Phase 3 storage, Phase 4 cloud push) read.
**When to use:** Shared state between concurrent collectors and consumers.
**Example:**
```swift
// Source: Swift 6 actor pattern; Sendable conformance required for all snapshot types
actor MetricsStore {
    private(set) var cpu:      CPUSnapshot     = .zero
    private(set) var ram:      RAMSnapshot     = .zero
    private(set) var disk:     DiskSnapshot    = .zero
    private(set) var processes: ProcessSnapshot = .empty

    func updateCPU(_ s: CPUSnapshot)          { cpu = s }
    func updateRAM(_ s: RAMSnapshot)          { ram = s }
    func updateDisk(_ s: DiskSnapshot)        { disk = s }
    func updateProcesses(_ s: ProcessSnapshot) { processes = s }

    // Swap spike detection (MON-07)
    private var prevSwapUsed: Double = 0
    func detectSwapSpike(current: RAMSnapshot) -> SwapSpike? {
        let delta = current.swapUsed - prevSwapUsed
        prevSwapUsed = current.swapUsed
        // Rate-of-change threshold: >50MB increase in one 5s interval = spike
        guard delta > 50 * 1024 * 1024 else { return nil }
        let suspect = processes.byRAM.first(where: { !$0.isSystem })
        return SwapSpike(deltaBytes: delta, suspectProcess: suspect)
    }
}
```

### Anti-Patterns to Avoid

- **Using `top -l 1` for process collection:** `top` takes ≈600ms per call. At 5-second intervals this is 12% blocking time. Use `ps` (44ms).
- **Using `statvfs` for disk space:** `statvfs` on macOS returns `f_bsize = 1048576` (256× too large), causing wildly incorrect results. Use `statfs` only.
- **Leaking `processor_info_array_t`:** After each CPU read, call `vm_deallocate(mach_task_self_, ...)` on the previous info array. Not deallocating causes steady memory growth.
- **Blocking Swift actor from IOKit calls:** `host_processor_info` and IOKit calls are synchronous C functions. Call them in a `Task { }` detached or in the `run()` loop, not inside actor methods that would block the actor.
- **Using `proc_pidinfo` for cross-user process CPU:** `proc_pidinfo` requires the target process to have the same UID as the caller. A user-context LaunchAgent (UID 502) cannot read root-owned processes (UID 0) with `proc_pidinfo`. Use `ps -A` instead.
- **Polling SMART at 5-second intervals:** SMART data changes on timescales of hours/days. Reading it every 5 seconds wastes I/O. Use 5-minute intervals.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-core CPU usage | Custom tick accumulator | `host_processor_info` with `PROCESSOR_CPU_LOAD_INFO` | Handles variable core counts, CPU state machine states; already correct |
| Cross-user process visibility | Custom proc walker | `ps -Aceo ...` subprocess | `proc_pidinfo` authorization boundary; `ps` is a setuid binary that crosses the boundary correctly |
| Disk I/O cumulative counters | Custom kernel extension | IOKit `"Statistics"` dict on `IOBlockStorageDriver` | Only stable API for hardware-level byte counts without kernel ext |
| Memory pressure level | Custom vm_stat parser | `sysctlbyname("kern.memorystatus_vm_pressure_level")` | Returns 1/2/4 for normal/warn/critical; no parsing needed |
| SMART status | IOKit NVMe plugin | `diskutil info -plist` + `PropertyListSerialization` | Apple Silicon SMART via IONVMeSMARTInterface is fragile; diskutil is stable and matches Disk Utility output |

**Key insight:** Every metric in this phase has a battle-tested OS-provided API. The complexity is in knowing which one to call and avoiding the several known-bad alternatives (statvfs, top, proc_pidinfo for cross-user).

---

## Common Pitfalls

### Pitfall 1: processor_info_array_t Memory Leak
**What goes wrong:** Each call to `host_processor_info` allocates a new `processor_info_array_t` via `vm_allocate`. If the previous array is not freed, the daemon grows by ~1KB per second.
**Why it happens:** The array is a Mach vm_allocate region, not Swift-managed memory. ARC does not free it.
**How to avoid:** After using the previous snapshot for delta calculation, call `vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevCpuInfo), vm_size_t(numPrevCpuInfo))` before overwriting the pointer.
**Warning signs:** Daemon RSS growing steadily at each CPU polling interval in `top`/Activity Monitor.

### Pitfall 2: statvfs vs statfs on macOS
**What goes wrong:** `statvfs()` on macOS returns `f_bsize = 1048576` instead of `4096`, making `f_bsize * f_bavail` report 256× too much free space.
**Why it happens:** macOS statvfs is non-standard; the "preferred block size" semantics differ from the "fundamental block size."
**How to avoid:** Use `statfs()` (not `statvfs`). Use `f_bfree * f_bsize` for free bytes. Verified: on a 3.6TiB disk, `statfs` with `f_bsize=4096`, `f_bfree * f_bsize` gives 1.63TiB matching `df`.
**Warning signs:** Reported free disk space is 256× too large.

### Pitfall 3: First CPU Sample Is Meaningless
**What goes wrong:** On the first call to `host_processor_info`, there is no `prevCpuInfo` snapshot. The absolute tick counts since boot produce values near 100% or near 0% depending on boot uptime.
**Why it happens:** Delta calculation requires two samples; the first sample establishes the baseline.
**How to avoid:** Set `prevCpuInfo` on the first call and publish a zero/nil snapshot. Only publish real utilization starting from the second interval.
**Warning signs:** CPU metric shows 100% or 0% for the first 5 seconds, then normalizes.

### Pitfall 4: IOKit Parent Traversal Stopping Condition
**What goes wrong:** The loop `while IOObjectConformsTo(current, "IOBlockStorageDriver") == 0` never terminates for virtual disks (RAM disks, disk images, synthetic APFS containers).
**Why it happens:** Virtual block devices do not have an `IOBlockStorageDriver` parent in the registry.
**How to avoid:** Add a depth limit (e.g., max 10 traversal steps) and return `nil` if exceeded. Only query physical disks (BSD names like `disk0`, not `disk1s2`).
**Warning signs:** Daemon hangs in the IOKit traversal loop when a disk image is mounted.

### Pitfall 5: Swap Spike False Positives on Apple Silicon
**What goes wrong:** On Apple Silicon with unified memory, macOS aggressively uses swap even when 50%+ of RAM is free. Swap usage oscillates normally. A simple absolute threshold fires constantly.
**Why it happens:** Apple Silicon memory architecture: the OS compresses and pages aggressively to maximize performance headroom.
**How to avoid:** Use rate-of-change detection (delta > threshold per interval), not absolute threshold. Recommended: flag only if swap increases by >50MB in a single 5-second interval AND pressure level is ≥ warning (≥2). Both conditions required to avoid false positives.
**Warning signs:** MON-07 fires multiple times per minute during normal operation.

### Pitfall 6: ps Output Locale Sensitivity
**What goes wrong:** `ps -Aceo pid,pcpu,rss,uid,comm` outputs CPU percentages with `,` instead of `.` on non-English locales (e.g., German locale). `Double("43,5")` returns `nil`.
**Why it happens:** The system locale affects number formatting in `ps` output.
**How to avoid:** Replace `,` with `.` before parsing: `parts[1].replacingOccurrences(of: ",", with: ".")`. Confirmed needed on this system (locale has `,` decimal separator in test output).
**Warning signs:** All CPU percentages parse as `nil` / zero on non-US systems.

### Pitfall 7: Swift 6 Strict Concurrency with Mach C Types
**What goes wrong:** Mach types like `processor_info_array_t` are `UnsafeMutablePointer<integer_t>?` — not `Sendable`. Storing them in a Swift 6 actor triggers data-race warnings.
**Why it happens:** Swift 6 strict concurrency mode (this project targets Swift 6) rejects non-Sendable types crossing isolation boundaries.
**How to avoid:** Keep all raw Mach pointers in non-isolated structs that are entirely owned by the collector's `run()` task. Never pass them across actor boundaries. Convert to `[Double]` (Sendable) before storing in `MetricsStore`.
**Warning signs:** Swift 6 concurrency errors: `'processor_info_array_t' cannot be sent to global actor 'MetricsStore'`.

---

## Code Examples

Verified patterns from official sources and direct system verification:

### Overall CPU Usage (Single Number from Tick Delta)
```swift
// Source: SystemKit (github.com/beltex/SystemKit) pattern, cross-verified with Stats source
// Use the average of per-core values as the "overall" number — matches Activity Monitor behavior
let overall = perCoreUsages.reduce(0.0, +) / Double(perCoreUsages.count)
```

### Memory Pressure Level Mapping
```swift
// Source: Verified via sysctl on macOS 15 Sequoia (this machine: value=1 = normal)
// kern.memorystatus_vm_pressure_level: 1=normal, 2=warning, 4=critical
enum MemoryPressure: Int {
    case normal   = 1
    case warning  = 2
    case critical = 4
}
```

### Swap Usage Reading
```swift
// Source: Verified via sysctl vm.swapusage on this machine
// Returns: total=1024MB, used=0.12MB, free=1023.88MB (encrypted)
var swap = xsw_usage()
var size = MemoryLayout<xsw_usage>.size
sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
// Fields: swap.xsu_total, swap.xsu_used, swap.xsu_avail (all in bytes)
```

### Disk Volume Enumeration (recommended approach)
```swift
// Source: Apple Developer Documentation — FileManager.mountedVolumeURLs
// .skipHiddenVolumes excludes devfs, autofs, etc.
let urls = FileManager.default.mountedVolumeURLs(
    includingResourceValuesForKeys: [.volumeNameKey, .volumeIsInternalKey],
    options: .skipHiddenVolumes
) ?? []
```

### Physical Disk Enumeration for IOKit and SMART
```swift
// Source: Verified via diskutil list -plist on this machine
// Physical disks are top-level entries (disk0, disk1, etc.) not partitions (disk0s1)
// Use "AllDisksAndPartitions" → filter entries without "Partitions" key (they're partitions)
// Or: use BSD name format — disks with no 's' separator are physical
let allDisks: [String] = ["disk0"]  // enumerate from diskutil list -plist
```

### SMART Key Extraction (Verified on Apple Silicon MacBook)
```swift
// Source: Verified locally on macOS 15, Apple M1 Pro
// disk0 SMART fields confirmed:
//   SMARTStatus: "Verified"
//   SMARTDeviceSpecificKeysMayVaryNotGuaranteed:
//     AVAILABLE_SPARE: 100         (wear indicator, <5 = warning)
//     AVAILABLE_SPARE_THRESHOLD: 99
//     PERCENTAGE_USED: 2           (drive wear %, >90 = warning)
//     TEMPERATURE: 37              (Celsius)
//     POWER_ON_HOURS_0: 3711       (cumulative hours)
//     POWER_CYCLES_0: 1384
```

---

## Discretion Recommendations

### Polling Intervals
| Metric | Interval | Rationale |
|--------|----------|-----------|
| CPU (overall + per-core) | 5s | Fixed — user decision |
| RAM (used/wired/compressed/swap) | 5s | Fixed — user decision |
| Process list (CPU + RAM ranked) | 5s | Same interval as CPU/RAM for consistent snapshots |
| Disk space per volume | 60s | Space changes rarely; 60s is more than fast enough |
| Disk I/O throughput | 5s | I/O spikes happen quickly; 5s matches CPU/RAM rhythm |
| S.M.A.R.T. health | 300s (5 min) | Drive health changes on hours/day timescales |

### Process Metadata Fields (MON-05)
Recommended fields: `pid`, `name`, `cpuPercent`, `ramBytes` (RSS × 1024), `uid`, `isSystem` (uid < 500).
Optional but useful for downstream: `ppid` (parent PID, via `ps -Aceo ppid,...`), resolved `appName` via `NSRunningApplication` for GUI apps. Add `ppid` — it costs nothing in `ps` and enables Phase 5 parent-child kill logic.

### Swap Spike Detection Strategy (MON-07)
Use **combined threshold**: spike fires when BOTH:
1. `swapUsedDelta > 50 * 1024 * 1024` (50MB increase in one 5s interval), AND
2. `pressureLevel >= 2` (memory warning or critical)

This prevents false positives on Apple Silicon's normal swap behavior. For attribution, use the top non-system process by RAM at the time of the spike (highest-RSS heuristic). Delta tracking would require per-process memory history across intervals — too much state for the marginal accuracy gain.

### Memory Pressure Tracking
Include `pressureLevel` as a first-class field in `RAMSnapshot`. It costs one `sysctlbyname` call (<1µs) and is directly needed by the swap spike detector. Phase 5 (kill logic) will also use it to decide urgency.

### Spike Severity Signaling (MON-07)
Use OSLog levels:
- `Logger.collector.warning(...)` for a detected swap spike + suspect process name
- `Logger.collector.error(...)` if pressure reaches critical (level=4)

Full notifications come in Phase 7. Within Phase 2, OSLog `warning` is sufficient and matches the daemon's existing pattern.

### Debug Access Before Phase 4
Write a JSON status file to `/tmp/heald-status.json` after each collection cycle. This is the most pragmatic option: `cat /tmp/heald-status.json | python3 -m json.tool` is immediately useful. No web server needed. Phase 4 replaces this with cloud push. The file is overwritten (not appended) each cycle — no cleanup needed.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| IOKit NVMe SMART plugin for disk health | `diskutil info -plist` for `SMARTStatus` | macOS 12+ | Plugin is fragile on Apple Silicon; diskutil plist is stable |
| `top -l 1` for process list | `ps -Aceo` | Longstanding | 14× faster (44ms vs 600ms); acceptable for 5s polling |
| `vm_statistics_data_t` (32-bit page counts) | `vm_statistics64_data_t` via `HOST_VM_INFO64` | macOS 10.9+ | 64-bit page counts for systems with >4GB RAM |

**Deprecated/outdated:**
- `HOST_VM_INFO` / `vm_statistics_data_t`: 32-bit page counts overflow on >16GB RAM. Always use `HOST_VM_INFO64`.
- `kIOMasterPortDefault`: Deprecated in macOS 12; use `kIOMainPortDefault` instead.

---

## Open Questions

1. **IOKit access from a non-sandboxed LaunchAgent**
   - What we know: IOKit is not App Sandbox compatible. The heald daemon is a non-sandboxed LaunchAgent, so IOKit is accessible. Verified: `import IOKit` compiles without Package.swift changes.
   - What's unclear: Whether specific IOKit operations (disk I/O statistics traversal) require any entitlements beyond non-sandbox.
   - Recommendation: Implement and test on the target machine in Wave 1. The Stats app uses this pattern in production without entitlements.

2. **proc_pidinfo vs ps for CPU accuracy**
   - What we know: `ps -Aceo pid,pcpu,...` uses kernel-computed `%CPU` which is an exponential moving average over a recent window (not a pure delta). This may differ slightly from `proc_pidinfo` delta tracking.
   - What's unclear: Whether this difference matters for Phase 5's "sustained >90% CPU over 5min" detection.
   - Recommendation: Use `ps` now. Phase 5 research should revisit if accuracy is insufficient; `proc_pidinfo` can replace it then since Phase 5 only targets processes owned by the current user.

3. **External USB drive SMART status**
   - What we know: `diskutil info -plist /dev/diskN` returns `SMARTStatus` for internal NVMe drives.
   - What's unclear: External USB drives may return `SMARTStatus: Not Supported` or may not appear in `diskutil list -plist`.
   - Recommendation: Handle `nil` and `"Not Supported"` gracefully in the SMART reader. Log `SMARTStatus` for all physical disks; skip unknown/unsupported.

---

## Sources

### Primary (HIGH confidence)
- `github.com/exelban/stats` (Modules/CPU/readers.swift, Modules/RAM/readers.swift, Modules/Disk/readers.swift) — Direct source inspection of production macOS monitor; all code patterns cross-referenced
- Local system verification — `sysctl kern.memorystatus_vm_pressure_level`, `sysctl vm.swapusage`, `statfs()` vs `df`, `diskutil info -plist disk0` (SMARTStatus key), `ps` timing (44ms)
- Apple Developer Documentation — `FileManager.mountedVolumeURLs`, `URLResourceValues.volumeAvailableCapacity`, `kIOBlockStorageDriverStatisticsKey`
- Swift Service Lifecycle — `swiftonserver.com/introduction-to-swift-service-lifecycle/` — polling service pattern with `withGracefulShutdownHandler`

### Secondary (MEDIUM confidence)
- `github.com/beltex/SystemKit` — SystemKit/System.swift: CPU tick delta pattern, vm_statistics64 field usage
- Apple Developer Forums thread 655349 — per-process CPU via `proc_pidinfo` vs limitations

### Tertiary (LOW confidence)
- General WebSearch results on `host_processor_info`, `vm.memory_pressure`, disk I/O — used as directional pointers only, all verified against primary sources before inclusion

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs verified locally or via direct source inspection of Stats app
- Architecture: HIGH — ServiceLifecycle polling pattern is documented and confirmed
- Pitfalls: HIGH — statvfs bug, memory leak, and locale issue all verified on the target system; false positive swap detection confirmed by macOS Apple Silicon behavior
- SMART approach: HIGH — key name `SMARTStatus` confirmed via `diskutil info -plist disk0` on target machine

**Research date:** 2026-03-03
**Valid until:** 2026-09-03 (stable Darwin/Mach APIs; 6-month window)
