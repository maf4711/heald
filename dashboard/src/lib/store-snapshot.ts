// Pure store snapshot logic (no fs / blob): what store.ts keeps in memory,
// writes to /tmp + Vercel Blob, and merges back on hydrate. Tested directly
// by heal-report.test.ts with node --test.

import { mergeHealBuckets, type Finding, type HealReport } from "./heal-report.ts";

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
  [key: string]: unknown;
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

export type HistoryPoint = { timestamp: string; cpu: number; ramUsedGB: number };

export type StoreSnapshot = {
  machines: Record<string, MachineMetrics>;
  events: ActivityEntry[];
  history: Record<string, HistoryPoint[]>;
  benchmarks: Record<string, BenchmarkResult[]>;
  // Own buckets so machine-status events can never evict heal history (GOAL 4)
  heals: HealReport[];
  findings: Finding[];
  savedAt: string;
};

export type StoreState = {
  machines: Map<string, MachineMetrics>;
  events: ActivityEntry[];
  metricsHistory: Map<string, HistoryPoint[]>;
  benchmarkHistory: Map<string, BenchmarkResult[]>;
  heals: HealReport[];
  findings: Finding[];
  hydrated: boolean;
  lastPersistMs: number;
};

export const MAX_EVENTS = 1000;

export function createState(): StoreState {
  return {
    machines: new Map(),
    events: [],
    metricsHistory: new Map(),
    benchmarkHistory: new Map(),
    heals: [],
    findings: [],
    hydrated: false,
    lastPersistMs: 0,
  };
}

/** Newest-first event bucket with the unchanged MAX_EVENTS cap. */
export function pushEvent(s: StoreState, entry: ActivityEntry) {
  s.events.unshift(entry);
  if (s.events.length > MAX_EVENTS) s.events.length = MAX_EVENTS;
}

export function snapshotFromState(s: StoreState): StoreSnapshot {
  return {
    machines: Object.fromEntries(s.machines),
    events: s.events.slice(0, 200),
    history: Object.fromEntries(s.metricsHistory),
    benchmarks: Object.fromEntries(s.benchmarkHistory),
    heals: s.heals,
    findings: s.findings,
    savedAt: new Date().toISOString(),
  };
}

/**
 * Merge a snapshot (cold-start tmp/blob or a concurrent writer's blob) into
 * live state. Idempotent: machines by lastSeen, events deduped, heals by id,
 * findings by (machineId, fingerprint); invalid heal/finding records dropped.
 */
export function applySnapshot(s: StoreState, data: Partial<StoreSnapshot>) {
  if (data.machines) {
    for (const [k, v] of Object.entries(data.machines)) {
      const existing = s.machines.get(k);
      if (!existing || (v.lastSeen && v.lastSeen >= (existing.lastSeen ?? ""))) {
        s.machines.set(k, v);
      }
    }
  }
  if (data.events?.length) {
    const seen = new Set(s.events.map((e) => `${e.timestamp}|${e.machineId}|${e.type}|${e.summary}`));
    for (const e of data.events) {
      const key = `${e.timestamp}|${e.machineId}|${e.type}|${e.summary}`;
      if (!seen.has(key)) {
        s.events.push(e);
        seen.add(key);
      }
    }
    s.events.sort((a, b) => (a.timestamp < b.timestamp ? 1 : -1));
    if (s.events.length > MAX_EVENTS) s.events.length = MAX_EVENTS;
  }
  const buckets = mergeHealBuckets({ heals: s.heals, findings: s.findings }, data);
  s.heals = buckets.heals;
  s.findings = buckets.findings;
  if (data.history) {
    for (const [k, v] of Object.entries(data.history)) {
      if (!s.metricsHistory.has(k) || (s.metricsHistory.get(k)?.length ?? 0) < v.length) {
        s.metricsHistory.set(k, v);
      }
    }
  }
  if (data.benchmarks) {
    for (const [k, v] of Object.entries(data.benchmarks)) {
      if (!s.benchmarkHistory.has(k) || (s.benchmarkHistory.get(k)?.length ?? 0) < v.length) {
        s.benchmarkHistory.set(k, v);
      }
    }
  }
}

export const MAX_PERSIST_ATTEMPTS = 3;

export interface SnapshotIO {
  /** Current remote snapshot + its ETag, or null when none exists yet. */
  read(): Promise<{ snapshot: Partial<StoreSnapshot>; etag?: string } | null>;
  /** Write; must throw when `etag` no longer matches (optimistic concurrency). */
  write(snapshot: StoreSnapshot, etag: string | undefined): Promise<void>;
  isConflict(err: unknown): boolean;
}

/**
 * Read-merge-write with ETag precondition: merges a concurrent writer's
 * snapshot into `s` (applySnapshot is idempotent), writes with `ifMatch`,
 * and retries up to MAX_PERSIST_ATTEMPTS on conflict. Returns true on success.
 */
export async function mergeAndWrite(s: StoreState, io: SnapshotIO): Promise<boolean> {
  for (let attempt = 0; attempt < MAX_PERSIST_ATTEMPTS; attempt++) {
    const remote = await io.read();
    if (remote) applySnapshot(s, remote.snapshot);
    try {
      await io.write(snapshotFromState(s), remote?.etag);
      return true;
    } catch (err) {
      if (!io.isConflict(err)) return false;
    }
  }
  return false;
}
