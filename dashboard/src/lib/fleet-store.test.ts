// Issue #19: ingest answered 2xx but heal reports never showed up in
// /api/heals. Several simulated Fluid instances (separate in-memory state)
// share one fake blob with ETag semantics.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createFleetStore, type FleetStore } from "./fleet-store.ts";
import { mergeAndWrite, createState, type SnapshotIO, type StoreSnapshot } from "./store-snapshot.ts";
import type { HealReport } from "./heal-report.ts";
import type { MachineMetrics } from "./store-snapshot.ts";

const healOf = (id: string, machineId: string): HealReport => ({
  schema: "heald.heal_report/v1",
  id,
  machineId,
  ts: new Date(Date.now() - 3600_000).toISOString(),
  healdVersion: "3.6.0",
  action: "disk_cleanup",
  trigger: "t",
  consent: "auto",
  outcome: "executed_ok",
  durationMs: 1,
  findingFingerprint: null,
  advisor: { source: "rules", recommendation: "proceed", confidence: 1, rationale: "r", latencyMs: 1 },
});

const metricsOf = (machineId: string) => ({ machineId, hostname: machineId }) as MachineMetrics;

class Conflict extends Error {}
class Unavailable extends Error {}

const tick = () => new Promise((r) => setImmediate(r));

/** Fake Vercel Blob: one JSON doc, ETag bumps on every write, ifMatch enforced. */
class FakeBlob {
  doc: string | null = null;
  version = 0;
  /** Writes that fail with a non-conflict error before succeeding again. */
  failWrites = 0;
  /** Writes that lose to a concurrent writer (precondition failed). */
  conflictWrites = 0;

  io(): SnapshotIO {
    return {
      read: async () => {
        await tick();
        if (this.doc === null) return null;
        return { snapshot: JSON.parse(this.doc) as StoreSnapshot, etag: `e${this.version}` };
      },
      write: async (snap, etag) => {
        await tick();
        if (this.failWrites > 0) {
          this.failWrites--;
          throw new Unavailable("blob 503");
        }
        if (this.conflictWrites > 0) {
          this.conflictWrites--;
          this.version++; // someone else won the race
          throw new Conflict();
        }
        const exists = this.doc !== null;
        if (etag ? etag !== `e${this.version}` : exists) throw new Conflict();
        this.doc = JSON.stringify(snap);
        this.version++;
        return `e${this.version}`;
      },
      isConflict: (e) => e instanceof Conflict,
    };
  }

  healIds(): string[] {
    if (!this.doc) return [];
    return (JSON.parse(this.doc) as StoreSnapshot).heals.map((h) => h.id).sort();
  }
}

const noSleep = { sleep: async () => {} };

function instance(blob: FakeBlob): FleetStore {
  // Interval 0: these tests assert cross-instance read-after-write itself;
  // the 3 s coalescing window is covered in ingest-hardening.test.ts.
  return createFleetStore({ io: blob.io(), refreshMinIntervalMs: 0, ...noSleep });
}

/** What POST /api/ingest does: buffer, then one flush. Resolves = 2xx. */
async function ingest(store: FleetStore, machineId: string, heals: HealReport[]) {
  const deferred = { persist: false };
  await store.upsertMachine(metricsOf(machineId), deferred);
  await store.addHeals(heals, deferred);
  await store.flush();
}

const ids = (hs: HealReport[]) => hs.map((h) => h.id).sort();

test("#19 heals ingested on instance A are visible via GET on warm instance B", async () => {
  const blob = new FakeBlob();
  const a = instance(blob);
  const b = instance(blob);
  await ingest(a, "node-a", []);
  await ingest(b, "node-b", []); // both instances warm (hydrated, machines > 0)

  await ingest(a, "node-a", [healOf("a1", "node-a"), healOf("a2", "node-a")]);

  assert.deepEqual(blob.healIds(), ["a1", "a2"]);
  assert.deepEqual(ids(await b.getHeals("node-a")), ["a1", "a2"], "GET on B must see A's write");
});

test("#19 concurrent ingest on two instances: both survive in the blob and on both GET paths", async () => {
  const blob = new FakeBlob();
  const a = instance(blob);
  const b = instance(blob);
  await ingest(a, "node-a", []);
  await ingest(b, "node-b", []);

  await Promise.all([
    ingest(a, "node-a", [healOf("a1", "node-a"), healOf("a2", "node-a")]),
    ingest(b, "node-b", [healOf("b1", "node-b"), healOf("b2", "node-b")]),
  ]);

  const all = ["a1", "a2", "b1", "b2"];
  assert.deepEqual(blob.healIds(), all);
  assert.deepEqual(ids(await a.getHeals()), all, "GET via instance A");
  assert.deepEqual(ids(await b.getHeals()), all, "GET via instance B");
});

test("#19 flush rejects (no 2xx) when the blob write fails", async () => {
  const blob = new FakeBlob();
  const a = instance(blob);
  await ingest(a, "node-a", []);
  blob.failWrites = 1;
  await assert.rejects(ingest(a, "node-a", [healOf("a1", "node-a")]));
});

test("#19 flush rejects (no 2xx) when every attempt loses the ETag race", async () => {
  const blob = new FakeBlob();
  const a = instance(blob);
  await ingest(a, "node-a", []);
  blob.conflictWrites = 1000;
  await assert.rejects(ingest(a, "node-a", [healOf("a1", "node-a")]));
});

test("#19 two concurrent requests on ONE instance both land", async () => {
  const blob = new FakeBlob();
  const a = instance(blob);
  await Promise.all([
    ingest(a, "node-a", [healOf("a1", "node-a")]),
    ingest(a, "node-b", [healOf("b1", "node-b")]),
  ]);
  assert.deepEqual(blob.healIds(), ["a1", "b1"]);
});

test("#19 every heal whose ingest resolved survives a redeploy (6 instances, daemon retries non-2xx)", async () => {
  const blob = new FakeBlob();
  const fleet = Array.from({ length: 6 }, () => instance(blob));
  for (const [i, s] of fleet.entries()) await ingest(s, `node-${i}`, []);

  // Daemon contract: cursor advances only on 2xx; on 5xx the same batch is resent.
  const daemon = async (s: FleetStore, i: number) => {
    for (let attempt = 0; attempt < 20; attempt++) {
      try {
        await ingest(s, `node-${i}`, [healOf(`h${i}`, `node-${i}`)]);
        return;
      } catch {
        /* 503 → retry */
      }
    }
    throw new Error(`node-${i} never got a 2xx`);
  };
  await Promise.all(fleet.map(daemon));

  const expected = fleet.map((_, i) => `h${i}`).sort();
  const fresh = instance(blob); // cold instance after a redeploy: only the blob survives
  assert.deepEqual(ids(await fresh.getHeals(undefined, 500)), expected);
  for (const s of fleet) assert.deepEqual(ids(await s.getHeals(undefined, 500)), expected);
});

test("#19 mergeAndWrite never overwrites an existing blob unconditionally (missing ETag)", async () => {
  let writes = 0;
  await assert.rejects(
    mergeAndWrite(createState(), {
      read: async () => ({ snapshot: { heals: [] } as unknown as StoreSnapshot, etag: "" }),
      write: async () => {
        writes++;
      },
      isConflict: () => false,
    }),
  );
  assert.equal(writes, 0);
});
