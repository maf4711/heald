// Fleet metrics store for serverless (Vercel).
// Strategy:
// 1. globalThis singleton — survives warm invocations on the same isolate
// 2. Atomic /tmp JSON cache — recovers when the same machine reuses /tmp
// 3. Optional Vercel Blob (BLOB_READ_WRITE_TOKEN) — cross-instance durability

import { readFileSync, writeFileSync, renameSync, existsSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

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

type HistoryPoint = { timestamp: string; cpu: number; ramUsedGB: number };

type StoreSnapshot = {
  machines: Record<string, MachineMetrics>;
  events: ActivityEntry[];
  history: Record<string, HistoryPoint[]>;
  benchmarks: Record<string, BenchmarkResult[]>;
  savedAt: string;
};

type StoreState = {
  machines: Map<string, MachineMetrics>;
  events: ActivityEntry[];
  metricsHistory: Map<string, HistoryPoint[]>;
  benchmarkHistory: Map<string, BenchmarkResult[]>;
  hydrated: boolean;
  lastPersistMs: number;
};

const MAX_EVENTS = 1000;
const MAX_HISTORY_PER_MACHINE = 720;
const MAX_BENCHMARK_HISTORY = 90;
const PERSIST_MIN_INTERVAL_MS = 2000;
const CACHE_FILE = join(tmpdir(), "heald-store.json");
const BLOB_PATHNAME = "heald-fleet-store.json";

const g = globalThis as typeof globalThis & { __healdStore?: StoreState };

function state(): StoreState {
  if (!g.__healdStore) {
    g.__healdStore = {
      machines: new Map(),
      events: [],
      metricsHistory: new Map(),
      benchmarkHistory: new Map(),
      hydrated: false,
      lastPersistMs: 0,
    };
  }
  return g.__healdStore;
}

function snapshotFromState(s: StoreState): StoreSnapshot {
  return {
    machines: Object.fromEntries(s.machines),
    events: s.events.slice(0, 200),
    history: Object.fromEntries(s.metricsHistory),
    benchmarks: Object.fromEntries(s.benchmarkHistory),
    savedAt: new Date().toISOString(),
  };
}

function applySnapshot(s: StoreState, data: Partial<StoreSnapshot>) {
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

function readTmpCache(): StoreSnapshot | null {
  try {
    if (!existsSync(CACHE_FILE)) return null;
    return JSON.parse(readFileSync(CACHE_FILE, "utf-8")) as StoreSnapshot;
  } catch {
    return null;
  }
}

function writeTmpCache(snap: StoreSnapshot) {
  try {
    const tmp = `${CACHE_FILE}.${process.pid}.tmp`;
    writeFileSync(tmp, JSON.stringify(snap));
    renameSync(tmp, CACHE_FILE);
  } catch {
    try {
      writeFileSync(CACHE_FILE, JSON.stringify(snap));
    } catch {
      /* best effort */
    }
  }
}

async function readBlobCache(): Promise<StoreSnapshot | null> {
  const token = process.env.BLOB_READ_WRITE_TOKEN;
  if (!token) return null;
  try {
    const { list } = await import("@vercel/blob");
    const { blobs } = await list({ prefix: BLOB_PATHNAME, limit: 5, token });
    const hit = blobs.find((b) => b.pathname === BLOB_PATHNAME) ?? blobs[0];
    if (!hit?.url) return null;
    const res = await fetch(hit.url, { cache: "no-store" });
    if (!res.ok) return null;
    return (await res.json()) as StoreSnapshot;
  } catch {
    return null;
  }
}

async function writeBlobCache(snap: StoreSnapshot) {
  const token = process.env.BLOB_READ_WRITE_TOKEN;
  if (!token) return;
  try {
    const { put } = await import("@vercel/blob");
    await put(BLOB_PATHNAME, JSON.stringify(snap), {
      access: "public",
      addRandomSuffix: false,
      token,
      contentType: "application/json",
    });
  } catch {
    /* optional */
  }
}

async function hydrate() {
  const s = state();
  if (s.hydrated && s.machines.size > 0) return;

  const tmp = readTmpCache();
  if (tmp) applySnapshot(s, tmp);

  if (s.machines.size === 0) {
    const blob = await readBlobCache();
    if (blob) {
      applySnapshot(s, blob);
      writeTmpCache(snapshotFromState(s));
    }
  }

  s.hydrated = true;
}

function persist(force = false) {
  const s = state();
  const now = Date.now();
  if (!force && now - s.lastPersistMs < PERSIST_MIN_INTERVAL_MS) return;
  s.lastPersistMs = now;
  const snap = snapshotFromState(s);
  writeTmpCache(snap);
  // Fire-and-forget blob write
  void writeBlobCache(snap);
}

export async function upsertMachine(data: MachineMetrics) {
  await hydrate();
  const s = state();
  const machineId = data.machineId || data.hostname || "unknown";
  const payload: MachineMetrics = {
    ...data,
    machineId,
    lastSeen: new Date().toISOString(),
  };
  s.machines.set(machineId, payload);

  const history = s.metricsHistory.get(machineId) ?? [];
  history.push({
    timestamp: payload.lastSeen,
    cpu: data.cpu?.overall ?? 0,
    ramUsedGB: data.ram?.usedGB ?? 0,
  });
  if (history.length > MAX_HISTORY_PER_MACHINE) {
    history.splice(0, history.length - MAX_HISTORY_PER_MACHINE);
  }
  s.metricsHistory.set(machineId, history);

  if (data.benchmark) {
    const benchHistory = s.benchmarkHistory.get(machineId) ?? [];
    const lastBench = benchHistory[benchHistory.length - 1];
    if (!lastBench || lastBench.timestamp !== data.benchmark.timestamp) {
      benchHistory.push(data.benchmark);
      if (benchHistory.length > MAX_BENCHMARK_HISTORY) {
        benchHistory.splice(0, benchHistory.length - MAX_BENCHMARK_HISTORY);
      }
      s.benchmarkHistory.set(machineId, benchHistory);
    }
  }

  persist();
}

export async function addEvent(entry: ActivityEntry) {
  await hydrate();
  const s = state();
  s.events.unshift(entry);
  if (s.events.length > MAX_EVENTS) s.events.length = MAX_EVENTS;
  persist();
}

export async function getMachines(): Promise<MachineMetrics[]> {
  await hydrate();
  return Array.from(state().machines.values());
}

export async function getEvents(machineId?: string, limit = 50): Promise<ActivityEntry[]> {
  await hydrate();
  const filtered = machineId
    ? state().events.filter((e) => e.machineId === machineId)
    : state().events;
  return filtered.slice(0, limit);
}

export async function getHistory(machineId: string): Promise<HistoryPoint[]> {
  await hydrate();
  return state().metricsHistory.get(machineId) ?? [];
}

export async function getBenchmarkHistory(machineId: string): Promise<BenchmarkResult[]> {
  await hydrate();
  return state().benchmarkHistory.get(machineId) ?? [];
}
