import Darwin
import ServiceLifecycle
import OSLog

struct CPUCollector: Service {
    let store: MetricsStore

    func run() async throws {
        var prevCpuInfo: processor_info_array_t? = nil
        var numPrevCpuInfo: mach_msg_type_number_t = 0

        try await withGracefulShutdownHandler {
            while true {
                var numCPUsU: natural_t = 0
                var cpuInfo: processor_info_array_t? = nil
                var numCpuInfo: mach_msg_type_number_t = 0

                let kr = host_processor_info(
                    mach_host_self(),
                    PROCESSOR_CPU_LOAD_INFO,
                    &numCPUsU,
                    &cpuInfo,
                    &numCpuInfo
                )

                if kr == KERN_SUCCESS, let cpuInfo = cpuInfo {
                    let numCPUs = Int(numCPUsU)
                    var snapshot: CPUSnapshot

                    if let prev = prevCpuInfo {
                        // Compute tick-delta for each core
                        var perCore = [Double](repeating: 0.0, count: numCPUs)

                        for i in 0 ..< numCPUs {
                            let base = Int(CPU_STATE_MAX) * i

                            let userDelta   = cpuInfo[base + Int(CPU_STATE_USER)]   - prev[base + Int(CPU_STATE_USER)]
                            let systemDelta = cpuInfo[base + Int(CPU_STATE_SYSTEM)] - prev[base + Int(CPU_STATE_SYSTEM)]
                            let niceDelta   = cpuInfo[base + Int(CPU_STATE_NICE)]   - prev[base + Int(CPU_STATE_NICE)]
                            let idleDelta   = cpuInfo[base + Int(CPU_STATE_IDLE)]   - prev[base + Int(CPU_STATE_IDLE)]

                            let inUse = userDelta + systemDelta + niceDelta
                            let total = inUse + idleDelta

                            perCore[i] = total > 0 ? Double(inUse) / Double(total) : 0.0
                        }

                        let overall = perCore.isEmpty ? 0.0 : perCore.reduce(0.0, +) / Double(perCore.count)
                        snapshot = CPUSnapshot(overall: overall, perCore: perCore, timestamp: Date())

                        // Free the previous buffer to prevent memory leak
                        vm_deallocate(
                            mach_task_self_,
                            vm_address_t(bitPattern: prev),
                            vm_size_t(numPrevCpuInfo * UInt32(MemoryLayout<integer_t>.size))
                        )
                    } else {
                        // First sample: store as baseline only — do not compute deltas.
                        // Publishing .zero prevents a misleading 100% or 0% startup spike.
                        snapshot = .zero
                    }

                    prevCpuInfo = cpuInfo
                    numPrevCpuInfo = numCpuInfo

                    await store.updateCPU(snapshot)
                    Logger.collector.debug("CPU: overall \(snapshot.overall * 100, format: .fixed(precision: 1))% cores=\(snapshot.perCore.count)")
                } else {
                    Logger.collector.warning("CPUCollector: host_processor_info failed (kr=\(kr))")
                }

                try await Task.sleep(for: .seconds(5))
            }
        } onGracefulShutdown: {
            // Task.sleep throws CancellationError on shutdown, breaking the while loop cleanly.
            // The final prevCpuInfo buffer is a minor leak on process exit — acceptable since
            // the OS reclaims all process memory on exit anyway.
        }

        // Free final buffer if loop exits cleanly (not via cancellation)
        if let prev = prevCpuInfo {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: prev),
                vm_size_t(numPrevCpuInfo * UInt32(MemoryLayout<integer_t>.size))
            )
        }
    }
}
