// Reviewer F4: blob persist must merge a concurrent writer's snapshot and
// retry on ETag precondition failure instead of overwriting it.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  applySnapshot,
  createState,
  mergeAndWrite,
  snapshotFromState,
  type StoreSnapshot,
} from "./store-snapshot.ts";
import type { HealReport } from "./heal-report.ts";

const healOf = (id: string): HealReport => ({
  schema: "heald.heal_report/v1",
  id,
  machineId: "node-a",
  ts: new Date(Date.now() - 3600_000).toISOString(), // relative: never "in the future"
  healdVersion: "3.6.0",
  action: "disk_cleanup",
  trigger: "t",
  consent: "auto",
  outcome: "executed_ok",
  durationMs: 1,
  findingFingerprint: null,
  advisor: { source: "rules", recommendation: "proceed", confidence: 1, rationale: "r", latencyMs: 1 },
});

function remoteWith(ids: string[]): StoreSnapshot {
  const s = createState();
  applySnapshot(s, { heals: ids.map(healOf) });
  return snapshotFromState(s);
}

class Conflict extends Error {}

test("applySnapshot is idempotent for heals/findings/events", () => {
  const s = createState();
  const snap = remoteWith(["a", "b"]);
  applySnapshot(s, snap);
  applySnapshot(s, snap);
  assert.equal(s.heals.length, 2);
});

test("F4 mergeAndWrite merges the remote snapshot before writing with its etag", async () => {
  const s = createState();
  applySnapshot(s, { heals: [healOf("local")] });
  const writes: { ids: string[]; etag?: string }[] = [];
  const ok = await mergeAndWrite(s, {
    read: async () => ({ snapshot: remoteWith(["remote"]), etag: "e1" }),
    write: async (snap, etag) => {
      writes.push({ ids: snap.heals.map((h) => h.id).sort(), etag });
    },
    isConflict: (e) => e instanceof Conflict,
  });
  assert.equal(ok, true);
  assert.deepEqual(writes, [{ ids: ["local", "remote"], etag: "e1" }]);
  assert.deepEqual(s.heals.map((h) => h.id).sort(), ["local", "remote"]);
});

test("F4 mergeAndWrite re-reads and retries on precondition failure", async () => {
  const s = createState();
  applySnapshot(s, { heals: [healOf("local")] });
  let reads = 0;
  const etags: (string | undefined)[] = [];
  const ok = await mergeAndWrite(s, {
    read: async () => {
      reads++;
      return { snapshot: remoteWith(reads === 1 ? ["r1"] : ["r1", "r2"]), etag: `e${reads}` };
    },
    write: async (_snap, etag) => {
      etags.push(etag);
      if (etag === "e1") throw new Conflict();
    },
    isConflict: (e) => e instanceof Conflict,
  });
  assert.equal(ok, true);
  assert.deepEqual(etags, ["e1", "e2"]);
  assert.deepEqual(s.heals.map((h) => h.id).sort(), ["local", "r1", "r2"]);
});

test("F4 mergeAndWrite gives up after 3 conflicting attempts", async () => {
  const s = createState();
  let writes = 0;
  const ok = await mergeAndWrite(s, {
    read: async () => ({ snapshot: remoteWith([]), etag: "e" }),
    write: async () => {
      writes++;
      throw new Conflict();
    },
    isConflict: (e) => e instanceof Conflict,
  });
  assert.equal(ok, false);
  assert.equal(writes, 3);
});

test("F4 mergeAndWrite writes without etag when no blob exists yet", async () => {
  const s = createState();
  const etags: (string | undefined)[] = [];
  await mergeAndWrite(s, {
    read: async () => null,
    write: async (_snap, etag) => {
      etags.push(etag);
    },
    isConflict: () => false,
  });
  assert.deepEqual(etags, [undefined]);
});

test("F4 mergeAndWrite does not retry non-conflict errors", async () => {
  const s = createState();
  let writes = 0;
  const ok = await mergeAndWrite(s, {
    read: async () => null,
    write: async () => {
      writes++;
      throw new Error("network");
    },
    isConflict: (e) => e instanceof Conflict,
  });
  assert.equal(ok, false);
  assert.equal(writes, 1);
});
