// In-memory store for metrics (Vercel serverless — no persistent state).
// For production, swap with Vercel KV / Postgres / Turso.

export interface MachineMetrics {
  machineId: string;
  hostname: string;
  lastSeen: string;
  cpu: { overall: number; perCore: number[] };
  ram: {
    usedGB: number;
    wiredGB: number;
    compressedGB: number;
    swapUsedMB: number;
    pressureLevel: number;
  };
  disk: {
    volumes: { name: string; mountPoint: string; totalGB: number; freeGB: number }[];
    smart: { bsdName: string; status: string }[];
  };
  processes: {
    topCPU: ProcessEntry[];
    topRAM: ProcessEntry[];
  };
  network?: {
    interface: string;
    rxBytesPerSec: number;
    txBytesPerSec: number;
    latencyMs: number | null;
    packetLossPercent: number | null;
  };
  battery?: {
    cycleCount: number;
    maxCapacityPercent: number;
    currentCharge: number;
    isCharging: boolean;
    condition: string;
    temperature: number | null;
  };
  uptime?: {
    systemSeconds: number;
    daemonSeconds: number;
    systemFormatted: string;
  };
  thermal?: string;
  benchmark?: BenchmarkResult;
}

export interface ProcessEntry {
  pid: number;
  name: string;
  cpuPercent: number;
  ramMB: number;
  system: boolean;
}

export interface BenchmarkResult {
  cpuSingleCore: number;
  cpuMultiCore: number;
  diskWriteMBs: number;
  diskReadMBs: number;
  memoryBandwidthGBs: number;
  overallScore: number;
  coreCount: number;
  timestamp: string;
}

export interface ActivityEntry {
  timestamp: string;
  machineId: string;
  type: string;
  summary: string;
  detail?: string;
  aiGenerated: boolean;
}

// In-memory maps — resets on cold start (acceptable for MVP)
const machines = new Map<string, MachineMetrics>();
const events: ActivityEntry[] = [];
const metricsHistory = new Map<string, { timestamp: string; cpu: number; ramUsedGB: number }[]>();
const benchmarkHistory = new Map<string, BenchmarkResult[]>();

const MAX_EVENTS = 1000;
const MAX_HISTORY_PER_MACHINE = 720; // ~1 hour at 5s intervals
const MAX_BENCHMARK_HISTORY = 90; // 90 days of daily benchmarks

export function upsertMachine(data: MachineMetrics) {
  machines.set(data.machineId, { ...data, lastSeen: new Date().toISOString() });

  // Append to metrics history
  const history = metricsHistory.get(data.machineId) ?? [];
  history.push({
    timestamp: new Date().toISOString(),
    cpu: data.cpu.overall,
    ramUsedGB: data.ram.usedGB,
  });
  if (history.length > MAX_HISTORY_PER_MACHINE) {
    history.splice(0, history.length - MAX_HISTORY_PER_MACHINE);
  }
  metricsHistory.set(data.machineId, history);

  // Track benchmark history
  if (data.benchmark) {
    const benchHistory = benchmarkHistory.get(data.machineId) ?? [];
    const lastBench = benchHistory[benchHistory.length - 1];
    // Only add if timestamp changed (new benchmark run)
    if (!lastBench || lastBench.timestamp !== data.benchmark.timestamp) {
      benchHistory.push(data.benchmark);
      if (benchHistory.length > MAX_BENCHMARK_HISTORY) {
        benchHistory.splice(0, benchHistory.length - MAX_BENCHMARK_HISTORY);
      }
      benchmarkHistory.set(data.machineId, benchHistory);
    }
  }
}

export function addEvent(entry: ActivityEntry) {
  events.unshift(entry);
  if (events.length > MAX_EVENTS) events.length = MAX_EVENTS;
}

export function getMachines(): MachineMetrics[] {
  return Array.from(machines.values());
}

export function getEvents(machineId?: string, limit = 50): ActivityEntry[] {
  const filtered = machineId ? events.filter((e) => e.machineId === machineId) : events;
  return filtered.slice(0, limit);
}

export function getHistory(machineId: string) {
  return metricsHistory.get(machineId) ?? [];
}

export function getBenchmarkHistory(machineId: string) {
  return benchmarkHistory.get(machineId) ?? [];
}
