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
  icloud?: {
    isEnabled: boolean;
    optimizeStorage: boolean;
    localFiles: number;
    cloudFiles: number;
    syncPercent: number;
    directories: number;
    evictedDirs: string[];
    conflicts: number;
    docsSizeGB: number;
    diskFreeGB: number;
    birdRunning: boolean;
  };
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

// In-memory maps with /tmp file-cache for Vercel cold-start recovery.
// On cold start, the in-memory store is empty but /tmp may still have data
// from the previous invocation on the same serverless instance.

import { readFileSync, writeFileSync } from "fs";

const CACHE_FILE = "/tmp/heald-store.json";

const machines = new Map<string, MachineMetrics>();
const events: ActivityEntry[] = [];
const metricsHistory = new Map<string, { timestamp: string; cpu: number; ramUsedGB: number }[]>();
const benchmarkHistory = new Map<string, BenchmarkResult[]>();

const MAX_EVENTS = 1000;
const MAX_HISTORY_PER_MACHINE = 720;
const MAX_BENCHMARK_HISTORY = 90;

// --- Persistence: /tmp file cache ---
function persistToCache() {
  try {
    const data = {
      machines: Object.fromEntries(machines),
      events: events.slice(0, 100),
      history: Object.fromEntries(metricsHistory),
      benchmarks: Object.fromEntries(benchmarkHistory),
    };
    writeFileSync(CACHE_FILE, JSON.stringify(data));
  } catch { /* best effort */ }
}

function restoreFromCache() {
  if (machines.size > 0) return; // already populated
  try {
    const raw = readFileSync(CACHE_FILE, "utf-8");
    const data = JSON.parse(raw);
    if (data.machines) {
      for (const [k, v] of Object.entries(data.machines)) {
        machines.set(k, v as MachineMetrics);
      }
    }
    if (data.events) {
      events.push(...(data.events as ActivityEntry[]));
    }
    if (data.history) {
      for (const [k, v] of Object.entries(data.history)) {
        metricsHistory.set(k, v as { timestamp: string; cpu: number; ramUsedGB: number }[]);
      }
    }
    if (data.benchmarks) {
      for (const [k, v] of Object.entries(data.benchmarks)) {
        benchmarkHistory.set(k, v as BenchmarkResult[]);
      }
    }
  } catch { /* no cache yet */ }
}

// Restore on module load
restoreFromCache();

export function upsertMachine(data: MachineMetrics) {
  machines.set(data.machineId, { ...data, lastSeen: new Date().toISOString() });

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

  if (data.benchmark) {
    const benchHistory = benchmarkHistory.get(data.machineId) ?? [];
    const lastBench = benchHistory[benchHistory.length - 1];
    if (!lastBench || lastBench.timestamp !== data.benchmark.timestamp) {
      benchHistory.push(data.benchmark);
      if (benchHistory.length > MAX_BENCHMARK_HISTORY) {
        benchHistory.splice(0, benchHistory.length - MAX_BENCHMARK_HISTORY);
      }
      benchmarkHistory.set(data.machineId, benchHistory);
    }
  }

  persistToCache();
}

export function addEvent(entry: ActivityEntry) {
  events.unshift(entry);
  if (events.length > MAX_EVENTS) events.length = MAX_EVENTS;
  persistToCache();
}

export function getMachines(): MachineMetrics[] {
  restoreFromCache();
  return Array.from(machines.values());
}

export function getEvents(machineId?: string, limit = 50): ActivityEntry[] {
  restoreFromCache();
  const filtered = machineId ? events.filter((e) => e.machineId === machineId) : events;
  return filtered.slice(0, limit);
}

export function getHistory(machineId: string) {
  restoreFromCache();
  return metricsHistory.get(machineId) ?? [];
}

export function getBenchmarkHistory(machineId: string) {
  restoreFromCache();
  return benchmarkHistory.get(machineId) ?? [];
}
