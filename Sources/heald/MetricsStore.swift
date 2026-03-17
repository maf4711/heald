import OSLog

actor MetricsStore {
    private(set) var cpu: CPUSnapshot = .zero
    private(set) var ram: RAMSnapshot = .zero
    private(set) var disk: DiskSnapshot = .empty
    private(set) var processes: ProcessSnapshot = .empty
    private(set) var network: NetworkSnapshot = .empty
    private(set) var battery: BatterySnapshot = .empty
    private(set) var uptime: UptimeSnapshot = .empty
    private(set) var thermal: ThermalSnapshot = .empty
    private(set) var benchmark: BenchmarkSnapshot = .empty
    private(set) var icloud: ICloudSnapshot = .empty

    func updateCPU(_ snapshot: CPUSnapshot) { cpu = snapshot }
    func updateRAM(_ snapshot: RAMSnapshot) { ram = snapshot }
    func updateDisk(_ snapshot: DiskSnapshot) { disk = snapshot }
    func updateProcesses(_ snapshot: ProcessSnapshot) { processes = snapshot }
    func updateNetwork(_ snapshot: NetworkSnapshot) { network = snapshot }
    func updateBattery(_ snapshot: BatterySnapshot) { battery = snapshot }
    func updateUptime(_ snapshot: UptimeSnapshot) { uptime = snapshot }
    func updateThermal(_ snapshot: ThermalSnapshot) { thermal = snapshot }
    func updateBenchmark(_ snapshot: BenchmarkSnapshot) { benchmark = snapshot }
    func updateICloud(_ snapshot: ICloudSnapshot) { icloud = snapshot }

    // --- Swap Spike Detection (MON-07) ---
    // Rate-of-change detection: fires when BOTH conditions met:
    //   1. Swap used increased by > 50MB in one interval
    //   2. Memory pressure level >= 2 (warning or critical)
    // This prevents false positives on Apple Silicon's normal aggressive swap behavior.

    private var prevSwapUsed: Double = 0

    func detectSwapSpike(current: RAMSnapshot) -> SwapSpike? {
        let delta = current.swapUsed - prevSwapUsed
        prevSwapUsed = current.swapUsed

        // Both conditions required to avoid Apple Silicon false positives
        let threshold: Double = 50 * 1024 * 1024  // 50MB
        guard delta > threshold, current.pressureLevel >= 2 else { return nil }

        // Attribute to highest-RAM non-system process
        let suspect = processes.byRAM.first(where: { !$0.isSystem })
        return SwapSpike(
            deltaBytes: delta,
            pressureLevel: current.pressureLevel,
            suspectProcess: suspect,
            timestamp: current.timestamp
        )
    }
}

struct SwapSpike: Sendable {
    let deltaBytes: Double
    let pressureLevel: Int
    let suspectProcess: ProcessEntry?
    let timestamp: Date
}
