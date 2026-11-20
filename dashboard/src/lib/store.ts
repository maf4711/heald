// Fleet metrics store for serverless (Vercel).
// Strategy:
// 1. globalThis singleton — survives warm invocations on the same isolate
// 2. Atomic /tmp JSON cache — recovers when the same machine reuses /tmp
// 3. Optional Vercel Blob (BLOB_READ_WRITE_TOKEN) — cross-instance durability

import { readFileSync, writeFileSync, renameSync, existsSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { applyFindings, applyHeals, type Finding, type HealReport } from "./heal-report";
import {
  applySnapshot,
  createState,
  mergeAndWrite,
  pushEvent,
  snapshotFromState,
  type ActivityEntry,
  type BenchmarkResult,
  type HistoryPoint,
  type MachineMetrics,
  type StoreSnapshot,
  type StoreState,
} from "./store-snapshot";

export type { ActivityEntry, BenchmarkResult, MachineMetrics, ProcessEntry } from "./store-snapshot";

const MAX_HISTORY_PER_MACHINE = 720;
const MAX_BENCHMARK_HISTORY = 90;
const PERSIST_MIN_INTERVAL_MS = 2000;
const CACHE_FILE = join(tmpdir(), "heald-store.json");
const BLOB_PATHNAME = "heald-fleet-store.json";

const g = globalThis as typeof globalThis & { __healdStore?: StoreState };

function state(): StoreState {
  g.__healdStore ??= createState();
  // Backfill buckets on a state object created before GOAL 4 (warm isolate / dev HMR)
  g.__healdStore.heals ??= [];
  g.__healdStore.findings ??= [];
  return g.__healdStore;
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

/** Remote snapshot + ETag; null when the blob does not exist. Throws on read errors. */
async function readBlobRemote(token: string): Promise<{ snapshot: StoreSnapshot; etag: string } | null> {
  const { get } = await import("@vercel/blob");
  const result = await get(BLOB_PATHNAME, { access: "private", token, useCache: false });
  if (!result) return null; // not found
  if (result.statusCode !== 200 || !result.stream) throw new Error("blob read failed");
  const text = await new Response(result.stream).text();
  return { snapshot: (text ? JSON.parse(text) : {}) as StoreSnapshot, etag: result.blob.etag };
}

async function readBlobCache(): Promise<StoreSnapshot | null> {
  const token = process.env.BLOB_READ_WRITE_TOKEN;
  if (!token) return null;
  try {
    return (await readBlobRemote(token))?.snapshot ?? null;
  } catch {
    return null;
  }
}

/**
 * Read-merge-write: merge whatever another instance persisted since our
 * hydrate, then write with ifMatch so a concurrent write is never clobbered
 * (retried up to 3x on BlobPreconditionFailedError).
 */
async function writeBlobCache(s: StoreState) {
  const token = process.env.BLOB_READ_WRITE_TOKEN;
  if (!token) return;
  try {
    const { put, BlobPreconditionFailedError } = await import("@vercel/blob");
    await mergeAndWrite(s, {
      read: () => readBlobRemote(token),
      write: async (snap, etag) => {
        // Private store (heald-fleet) + overwrite same pathname
        await put(BLOB_PATHNAME, JSON.stringify(snap), {
          access: "private",
          addRandomSuffix: false,
          allowOverwrite: true,
          token,
          contentType: "application/json",
          ...(etag ? { ifMatch: etag } : {}),
        });
      },
      isConflict: (err) => err instanceof BlobPreconditionFailedError,
    });
  } catch {
    /* optional durability path */
  }
}

async function hydrate() {
  const s = state();
  if (s.hydrated && s.machines.size > 0) return;

  const tmp = readTmpCache();
  if (tmp) applySnapshot(s, tmp);

  // Always try blob when machines empty (cross-instance recovery)
  if (s.machines.size === 0) {
    const blob = await readBlobCache();
    if (blob) {
      applySnapshot(s, blob);
      writeTmpCache(snapshotFromState(s));
    }
  }

  s.hydrated = true;
}

async function persist(force = false) {
  const s = state();
  const now = Date.now();
  if (!force && now - s.lastPersistMs < PERSIST_MIN_INTERVAL_MS) {
    // Still flush tmp so same-isolate reads are fresh
    writeTmpCache(snapshotFromState(s));
    return;
  }
  s.lastPersistMs = now;
  // Await blob so serverless does not freeze mid-write (merges remote state into s)
  await writeBlobCache(s);
  writeTmpCache(snapshotFromState(s));
}

/** Write options: `persist: false` defers the write to a later flush(). */
export type WriteOptions = { persist?: boolean };

/** Persist once after a batch of `{ persist: false }` writes (one blob write per ingest). */
export async function flush() {
  await persist(true);
}

export async function upsertMachine(data: MachineMetrics, opts: WriteOptions = {}) {
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

  if (opts.persist !== false) await persist(true);
}

export async function addEvent(entry: ActivityEntry, opts: WriteOptions = {}) {
  await hydrate();
  const s = state();
  pushEvent(s, entry);
  if (opts.persist !== false) await persist(true);
}

/** Store validated heal reports (caller validates); dedupe by id, cap 5000. */
export async function addHeals(heals: HealReport[], opts: WriteOptions = {}) {
  await hydrate();
  const s = state();
  s.heals = applyHeals(s.heals, heals);
  if (opts.persist !== false) await persist(true);
}

/** Upsert validated findings by (machineId, fingerprint), cap 500 per machine. */
export async function addFindings(findings: Finding[], opts: WriteOptions = {}) {
  await hydrate();
  const s = state();
  s.findings = applyFindings(s.findings, findings);
  if (opts.persist !== false) await persist(true);
}

export async function getHeals(machineId?: string, limit = 50): Promise<HealReport[]> {
  await hydrate();
  const all = state().heals;
  return (machineId ? all.filter((h) => h.machineId === machineId) : all).slice(0, limit);
}

export async function getFindings(machineId?: string, limit = 50): Promise<Finding[]> {
  await hydrate();
  const all = state().findings;
  return (machineId ? all.filter((f) => f.machineId === machineId) : all).slice(0, limit);
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
