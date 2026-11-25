// Pure store snapshot logic (no fs / blob): what store.ts keeps in memory,
// writes to /tmp + Vercel Blob, and merges back on hydrate. Tested directly
// by heal-report.test.ts with node --test.

import { mergeHealBuckets, type Finding, type HealReport } from "./heal-report.ts";
import { casUpdate, type CasOptions, type DocIO } from "./blob-cas.ts";

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
  };
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** Identity of an activity event (dedupe across resends and snapshot merges). */
const eventKey = (e: ActivityEntry) => `${e.timestamp}|${e.machineId}|${e.type}|${e.summary}`;

export function isValidEvent(v: unknown): v is ActivityEntry {
  return (
    isRecord(v) &&
    typeof v.timestamp === "string" &&
    typeof v.machineId === "string" &&
    typeof v.type === "string" &&
    typeof v.summary === "string"
  );
}

/** Events from an untrusted body/snapshot: non-arrays → [], invalid entries dropped. */
export function validEvents(v: unknown): ActivityEntry[] {
  return Array.isArray(v) ? v.filter(isValidEvent) : [];
}

/** Newest-first event bucket with the unchanged MAX_EVENTS cap; a resent event is not duplicated. */
export function pushEvent(s: StoreState, entry: ActivityEntry) {
  const key = eventKey(entry);
  if (s.events.some((e) => eventKey(e) === key)) return;
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

/** Entries of an untrusted map whose values pass `ok` (non-objects → none). */
function entries<V>(m: unknown, ok: (v: unknown) => boolean): [string, V][] {
  return isRecord(m) ? (Object.entries(m).filter(([, v]) => ok(v)) as [string, V][]) : [];
}

/**
 * Merge a snapshot (cold-start tmp/blob or a concurrent writer's blob) into
 * live state. Idempotent: machines by lastSeen, events deduped, heals by id,
 * findings by (machineId, fingerprint) with newer lastSeen winning. Malformed
 * entries (untrusted / corrupt blob) are skipped, never thrown on.
 */
export function applySnapshot(s: StoreState, data: Partial<StoreSnapshot> | null | undefined) {
  if (!isRecord(data)) return;
  for (const [k, v] of entries<MachineMetrics>(data.machines, isRecord)) {
    const existing = s.machines.get(k);
    if (!existing || (typeof v.lastSeen === "string" && v.lastSeen >= (existing.lastSeen ?? ""))) {
      s.machines.set(k, v);
    }
  }
  const events = validEvents(data.events);
  if (events.length) {
    const seen = new Set(s.events.map(eventKey));
    for (const e of events) {
      const key = eventKey(e);
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
  for (const [k, v] of entries<HistoryPoint[]>(data.history, Array.isArray)) {
    if ((s.metricsHistory.get(k)?.length ?? -1) < v.length) s.metricsHistory.set(k, v);
  }
  for (const [k, v] of entries<BenchmarkResult[]>(data.benchmarks, Array.isArray)) {
    if ((s.benchmarkHistory.get(k)?.length ?? -1) < v.length) s.benchmarkHistory.set(k, v);
  }
}

export type SnapshotIO<T = StoreSnapshot> = DocIO<T>;

/**
 * Read-merge-write with ETag precondition: merges the remote snapshot into
 * `s` (applySnapshot is idempotent), writes with `ifMatch` (create-only when
 * no blob exists yet) and retries on conflict. Resolves with the new ETag
 * only once the write landed; throws PersistError otherwise.
 */
export function mergeAndWrite(s: StoreState, io: SnapshotIO, opts?: CasOptions): Promise<string | undefined> {
  return casUpdate(
    io,
    // `unchanged` (304 on opts.knownEtag): `s` already holds that version
    (remote, unchanged) => {
      if (remote && !unchanged) applySnapshot(s, remote);
      return snapshotFromState(s);
    },
    opts,
  );
}
