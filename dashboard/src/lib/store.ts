// Fleet metrics store for serverless (Vercel).
// Strategy:
// 1. globalThis singleton — survives warm invocations on the same isolate
// 2. Atomic /tmp JSON cache — recovers when the same machine reuses /tmp
// 3. Optional Vercel Blob (BLOB_READ_WRITE_TOKEN) — cross-instance durability
// Logic lives in fleet-store.ts (tested with simulated instances).

import { readFileSync, writeFileSync, renameSync, existsSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { createFleetStore, type FleetStore, type TmpCache } from "./fleet-store";
import { blobJsonIO, blobRequired } from "./blob-json";
import type { StoreSnapshot } from "./store-snapshot";

export type { ActivityEntry, BenchmarkResult, MachineMetrics, ProcessEntry } from "./store-snapshot";
export type { WriteOptions } from "./fleet-store";

const CACHE_FILE = join(tmpdir(), "heald-store.json");
const BLOB_PATHNAME = "heald-fleet-store.json";

const tmpCache: TmpCache = {
  read() {
    try {
      if (!existsSync(CACHE_FILE)) return null;
      return JSON.parse(readFileSync(CACHE_FILE, "utf-8")) as StoreSnapshot;
    } catch {
      return null;
    }
  },
  write(snap) {
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
  },
};

const g = globalThis as typeof globalThis & { __healdFleetStore?: FleetStore };

function store(): FleetStore {
  g.__healdFleetStore ??= createFleetStore({
    io: blobJsonIO<StoreSnapshot>(BLOB_PATHNAME),
    requireRemote: blobRequired(), // prod without token → ingest 503, not memory-only 200
    tmp: tmpCache,
  });
  return g.__healdFleetStore;
}

export const flush: FleetStore["flush"] = () => store().flush();
export const upsertMachine: FleetStore["upsertMachine"] = (...a) => store().upsertMachine(...a);
export const addEvent: FleetStore["addEvent"] = (...a) => store().addEvent(...a);
export const addHeals: FleetStore["addHeals"] = (...a) => store().addHeals(...a);
export const addFindings: FleetStore["addFindings"] = (...a) => store().addFindings(...a);
export const getHeals: FleetStore["getHeals"] = (...a) => store().getHeals(...a);
export const getFindings: FleetStore["getFindings"] = (...a) => store().getFindings(...a);
export const getErrorPicture: FleetStore["getErrorPicture"] = () => store().getErrorPicture();
export const getMachines: FleetStore["getMachines"] = () => store().getMachines();
export const getEvents: FleetStore["getEvents"] = (...a) => store().getEvents(...a);
export const getHistory: FleetStore["getHistory"] = (...a) => store().getHistory(...a);
export const getBenchmarkHistory: FleetStore["getBenchmarkHistory"] = (...a) => store().getBenchmarkHistory(...a);
