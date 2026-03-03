import Darwin
import ServiceLifecycle
import OSLog

struct RAMCollector: Service {
    let store: MetricsStore

    func run() async throws {
        try await withGracefulShutdownHandler {
            while true {
                let snapshot = collectRAM()
                await store.updateRAM(snapshot)

                // Swap spike detection — must run after updateRAM so detectSwapSpike
                // compares against the just-stored snapshot.
                if let spike = await store.detectSwapSpike(current: snapshot) {
                    Logger.collector.warning(
                        "Swap spike: +\(spike.deltaBytes / 1_048_576, format: .fixed(precision: 1))MB, pressure=\(spike.pressureLevel), suspect=\(spike.suspectProcess?.name ?? "unknown")"
                    )
                }

                Logger.collector.debug(
                    "RAM: used=\(snapshot.used / 1_048_576, format: .fixed(precision: 0))MB swap=\(snapshot.swapUsed / 1_048_576, format: .fixed(precision: 0))MB pressure=\(snapshot.pressureLevel)"
                )

                try await Task.sleep(for: .seconds(5))
            }
        } onGracefulShutdown: {
            // Task.sleep throws CancellationError on shutdown, breaking the while loop cleanly.
        }
    }

    // MARK: - Private collection helpers
    // All helpers are non-isolated functions — raw Mach/sysctl state never crosses actor boundary.

    private func collectRAM() -> RAMSnapshot {
        // Use sysconf to get page size — vm_page_size is mutable shared state (Swift 6 rejects it)
        let pageSize = Double(sysconf(_SC_PAGESIZE))

        // --- 1. VM statistics via host_statistics64 ---
        var stats = vm_statistics64()
        var count = UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let kr: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        var wired:       Double = 0
        var active:      Double = 0
        var inactive:    Double = 0
        var speculative: Double = 0
        var compressed:  Double = 0
        var purgeable:   Double = 0
        var external:    Double = 0

        if kr == KERN_SUCCESS {
            wired       = Double(stats.wire_count)          * pageSize
            active      = Double(stats.active_count)        * pageSize
            inactive    = Double(stats.inactive_count)      * pageSize
            speculative = Double(stats.speculative_count)   * pageSize
            compressed  = Double(stats.compressor_page_count) * pageSize
            purgeable   = Double(stats.purgeable_count)     * pageSize
            external    = Double(stats.external_page_count) * pageSize
        } else {
            Logger.collector.warning("RAMCollector: host_statistics64 failed (kr=\(kr))")
        }

        // "Used" definition matching Activity Monitor:
        // active + inactive + speculative + wired + compressed - purgeable - external
        let used = active + inactive + speculative + wired + compressed - purgeable - external

        // --- 2. Swap usage via sysctlbyname ---
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        let swapUsed  = Double(swap.xsu_used)
        let swapTotal = Double(swap.xsu_total)

        // --- 3. Memory pressure level via sysctlbyname ---
        // Values: 1=normal, 2=warning, 4=critical
        var pressure: Int = 1
        var pressureSize = MemoryLayout<Int>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0)

        return RAMSnapshot(
            used: used,
            wired: wired,
            active: active,
            compressed: compressed,
            swapUsed: swapUsed,
            swapTotal: swapTotal,
            pressureLevel: pressure,
            timestamp: Date()
        )
    }
}
