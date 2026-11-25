// Re-review of f59a427: the daemon moves a finding open → fixed (and sets
// linkedAction / healedAt) WITHOUT touching lastSeen or count
// (DiagnosisEngine.recordHeal / refresh / markFixed). Merges must rank that
// lifecycle instead of keeping a stale "open" on a tie. Plus: ingest must
// answer within the daemon's 7 s timeout.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createFleetStore } from "./fleet-store.ts";
import { applyFindings, ingestBody, type Finding } from "./heal-report.ts";
import { processIngest, type IngestStore } from "./ingest.ts";
import { createDeviceRegistry, type RegistryDoc } from "./device-registry.ts";
import { FakeBlob } from "./fake-blob.ts";
import type { StoreSnapshot } from "./store-snapshot.ts";

const T = "2026-11-21T10:00:00.000Z";
const T_LATER = "2026-11-21T12:00:00.000Z";
const HEALED = "2026-11-21T10:05:00.000Z";

const F = (over: Partial<Finding> = {}): Finding => ({
  schema: "heald.findings/v1",
  machineId: "node-a",
  fingerprint: "fp1",
  category: "disk",
  component: "c",
  severity: "warning",
  count: 5,
  status: "open",
  recurrenceCount: 0,
  linkedAction: null,
  firstSeen: "2026-11-20T10:00:00.000Z",
  lastSeen: T,
  ...over,
});
const fixed = () => F({ status: "fixed", linkedAction: "disk_cleanup", healedAt: HEALED });
const noSleep = { sleep: async () => {} };

test("B1 a stale warm instance does not regress fixed → open (blob and its own GET)", async () => {
  const blob = new FakeBlob<StoreSnapshot>();
  const a = createFleetStore({ io: blob.io(), refreshMinIntervalMs: 0, ...noSleep });
  const b = createFleetStore({ io: blob.io(), refreshMinIntervalMs: 0, ...noSleep });
  await a.addFindings([F()]);
  assert.equal((await b.getFindings())[0].status, "open"); // B warm with "open"
  await a.addFindings([fixed()]);
  assert.equal(blob.json().findings[0].status, "fixed");

  await b.addEvent({ timestamp: T, machineId: "node-b", type: "x", summary: "unrelated", aiGenerated: false });
  const persisted = blob.json().findings[0];
  assert.equal(persisted.status, "fixed");
  assert.equal(persisted.linkedAction, "disk_cleanup");
  assert.equal(persisted.healedAt, HEALED);
  assert.equal((await b.getFindings())[0].status, "fixed");
});

test("B1 on a lastSeen+count tie, fixed beats open in both merge directions", () => {
  for (const tieKeepsExisting of [false, true]) {
    assert.equal(applyFindings([F()], [fixed()], { tieKeepsExisting })[0].status, "fixed");
    assert.equal(applyFindings([fixed()], [F()], { tieKeepsExisting })[0].status, "fixed");
  }
});

test("B1 on a tie, a recorded heal (healedAt / linkedAction) beats none", () => {
  const healed = F({ linkedAction: "disk_cleanup", healedAt: HEALED });
  assert.equal(applyFindings([F()], [healed], { tieKeepsExisting: true })[0].healedAt, HEALED);
  assert.equal(applyFindings([healed], [F()])[0].healedAt, HEALED);
  const linked = F({ linkedAction: "disk_cleanup" });
  assert.equal(applyFindings([linked], [F()])[0].linkedAction, "disk_cleanup");
});

test("B1 a genuine new observation (count+1, newer lastSeen, recurring) beats an older fixed", () => {
  const recurring = F({ status: "recurring", count: 6, lastSeen: T_LATER, recurrenceCount: 1, linkedAction: "disk_cleanup" });
  for (const tieKeepsExisting of [false, true]) {
    assert.equal(applyFindings([fixed()], [recurring], { tieKeepsExisting })[0].status, "recurring");
    assert.equal(applyFindings([recurring], [fixed()], { tieKeepsExisting })[0].status, "recurring");
  }
});

test("B1 ingest keeps the daemon's healedAt", () => {
  const r = ingestBody({ findings: [fixed()] });
  assert.equal(r.status, 200);
  if (r.status === 200) assert.equal(r.findings[0].healedAt, HEALED);
});

// ---- F1: ingest within the daemon's 7 s timeout ----

const hang = () => new Promise<never>(() => {});
const okStore: IngestStore = {
  upsertMachine: async () => {},
  addEvent: async () => {},
  addHeals: async () => {},
  addFindings: async () => {},
  flush: async () => {},
};

test("F1 a hanging auth or flush answers 503 within the request deadline", async () => {
  for (const deps of [
    { authorized: hang, store: okStore },
    { authorized: async () => true, store: { ...okStore, flush: hang } },
  ]) {
    const t0 = Date.now();
    const r = await processIngest({ ...deps, body: async () => ({}), deadlineMs: 50 });
    assert.equal(r.status, 503);
    assert.ok(Date.now() - t0 < 1000);
  }
});

test("F1 a slow lastSeen touch does not delay authentication", async () => {
  const blob = new FakeBlob<RegistryDoc>();
  let now = new Date(T);
  const deferred: Promise<unknown>[] = [];
  const reg = createDeviceRegistry({
    io: blob.io(),
    now: () => now,
    touchIntervalMs: 60_000,
    defer: (p) => deferred.push(p),
    ...noSleep,
  });
  await reg.register({ deviceId: "dev-a", token: "token-a-0123456789abcdef" });
  now = new Date(T_LATER); // touch due
  blob.hangWrites = 1;
  const t0 = Date.now();
  assert.equal(await reg.authenticate("token-a-0123456789abcdef"), true);
  assert.ok(Date.now() - t0 < 500, "authenticate must not await the touch write");
  assert.equal(deferred.length, 1, "touch handed to waitUntil/after");
});
