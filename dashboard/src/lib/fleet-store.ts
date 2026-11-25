// Fleet store core: in-memory state + /tmp cache + optional remote snapshot
// (Vercel Blob in prod, a fake in tests). store.ts binds one instance per
// isolate; tests create several to simulate Fluid instances.
// Only `.ts` imports so node --test can load it directly.

import {
  applyFindings,
  applyHeals,
  machineErrorPicture,
  type Finding,
  type HealReport,
  type MachineErrorPicture,
} from "./heal-report.ts";
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
  type SnapshotIO,
  type StoreSnapshot,
  type StoreState,
} from "./store-snapshot.ts";
import type { CasOptions } from "./blob-cas.ts";

const MAX_HISTORY_PER_MACHINE = 720;
const MAX_BENCHMARK_HISTORY = 90;

export interface TmpCache {
  read(): StoreSnapshot | null;
  write(snap: StoreSnapshot): void;
}

export interface FleetStoreOptions extends CasOptions {
  /** Remote snapshot (Vercel Blob); null when no BLOB_READ_WRITE_TOKEN. */
  io: SnapshotIO | null;
  tmp?: TmpCache;
  state?: StoreState;
}

/** Write options: `persist: false` defers the write to a later flush(). */
export type WriteOptions = { persist?: boolean };

function forMachine<T extends { machineId: string }>(all: T[], machineId: string | undefined, limit: number): T[] {
  return (machineId ? all.filter((x) => x.machineId === machineId) : all).slice(0, limit);
}

export function createFleetStore({ io, tmp, state, ...cas }: FleetStoreOptions) {
  const s = state ?? createState();
  // Backfill buckets on a state object created before GOAL 4 (warm isolate / dev HMR)
  s.heals ??= [];
  s.findings ??= [];
  /** ETag of the remote snapshot last merged into `s` (conditional re-reads). */
  let lastEtag: string | undefined;
  /** Serialises flushes on this instance so concurrent requests don't race each other. */
  let flushChain: Promise<unknown> = Promise.resolve();

  function hydrateLocal() {
    if (s.hydrated) return;
    const cached = tmp?.read();
    if (cached) applySnapshot(s, cached);
    s.hydrated = true;
  }

  /**
   * Merge whatever other instances persisted since our last look. Uses
   * If-None-Match, so an unchanged blob costs a 304. Read errors are
   * tolerated: the caller then serves this instance's memory.
   */
  async function refresh() {
    hydrateLocal();
    if (!io) return;
    try {
      const remote = await io.read(lastEtag);
      if (!remote || remote.notModified) return;
      applySnapshot(s, remote.snapshot);
      lastEtag = remote.etag;
    } catch {
      /* degraded read: serve memory */
    }
  }

  async function persist() {
    if (io) lastEtag = await mergeAndWrite(s, io, cas); // throws PersistError → caller answers 5xx
    tmp?.write(snapshotFromState(s));
  }

  /**
   * Persist once after a batch of `{ persist: false }` writes (one blob
   * read-merge-write per ingest). Resolves only when the snapshot is durably
   * in the blob; rejects with PersistError otherwise.
   */
  function flush(): Promise<void> {
    const run = flushChain.then(persist);
    flushChain = run.catch(() => {});
    return run;
  }

  /** Hydrate, apply `change`, then persist unless the caller defers to flush(). */
  async function write(opts: WriteOptions, change: (s: StoreState) => void) {
    hydrateLocal(); // remote state is merged by mergeAndWrite at flush time
    change(s);
    if (opts.persist !== false) await flush();
  }

  /** Reads always merge the latest blob first (read-after-write across instances). */
  async function read<T>(get: (s: StoreState) => T): Promise<T> {
    await refresh();
    return get(s);
  }

  return {
    state: s,
    flush,

    upsertMachine(data: MachineMetrics, opts: WriteOptions = {}) {
      return write(opts, (st) => {
        const machineId = data.machineId || data.hostname || "unknown";
        const payload: MachineMetrics = { ...data, machineId, lastSeen: new Date().toISOString() };
        st.machines.set(machineId, payload);

        const history = st.metricsHistory.get(machineId) ?? [];
        history.push({ timestamp: payload.lastSeen, cpu: data.cpu?.overall ?? 0, ramUsedGB: data.ram?.usedGB ?? 0 });
        if (history.length > MAX_HISTORY_PER_MACHINE) history.splice(0, history.length - MAX_HISTORY_PER_MACHINE);
        st.metricsHistory.set(machineId, history);

        if (data.benchmark) {
          const benchHistory = st.benchmarkHistory.get(machineId) ?? [];
          const lastBench = benchHistory[benchHistory.length - 1];
          if (!lastBench || lastBench.timestamp !== data.benchmark.timestamp) {
            benchHistory.push(data.benchmark);
            if (benchHistory.length > MAX_BENCHMARK_HISTORY) {
              benchHistory.splice(0, benchHistory.length - MAX_BENCHMARK_HISTORY);
            }
            st.benchmarkHistory.set(machineId, benchHistory);
          }
        }
      });
    },

    addEvent(entry: ActivityEntry, opts: WriteOptions = {}) {
      return write(opts, (st) => pushEvent(st, entry));
    },

    /** Store validated heal reports (caller validates); dedupe by id, cap 5000. */
    addHeals(heals: HealReport[], opts: WriteOptions = {}) {
      return write(opts, (st) => {
        st.heals = applyHeals(st.heals, heals);
      });
    },

    /** Upsert validated findings by (machineId, fingerprint), cap 500 per machine. */
    addFindings(findings: Finding[], opts: WriteOptions = {}) {
      return write(opts, (st) => {
        st.findings = applyFindings(st.findings, findings);
      });
    },

    getHeals(machineId?: string, limit = 50): Promise<HealReport[]> {
      return read((st) => forMachine(st.heals, machineId, limit));
    },

    getFindings(machineId?: string, limit = 50): Promise<Finding[]> {
      return read((st) => forMachine(st.findings, machineId, limit));
    },

    /** Fleet "Fehlerbild" computed over the full heal + finding buckets. */
    getErrorPicture(): Promise<MachineErrorPicture[]> {
      return read((st) => machineErrorPicture(st.findings, st.heals));
    },

    getMachines(): Promise<MachineMetrics[]> {
      return read((st) => Array.from(st.machines.values()));
    },

    getEvents(machineId?: string, limit = 50): Promise<ActivityEntry[]> {
      return read((st) => forMachine(st.events, machineId, limit));
    },

    getHistory(machineId: string): Promise<HistoryPoint[]> {
      return read((st) => st.metricsHistory.get(machineId) ?? []);
    },

    getBenchmarkHistory(machineId: string): Promise<BenchmarkResult[]> {
      return read((st) => st.benchmarkHistory.get(machineId) ?? []);
    },
  };
}

export type FleetStore = ReturnType<typeof createFleetStore>;
