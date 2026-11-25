// PR #22 review: findings merge direction, event dedupe, poison payloads,
// bounded persist time, GET amplification, prod without blob token.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createFleetStore, type FleetStore } from "./fleet-store.ts";
import { applySnapshot, createState, validEvents, type ActivityEntry, type StoreSnapshot } from "./store-snapshot.ts";
import { casUpdate, parseDoc, PersistError } from "./blob-cas.ts";
import { createDeviceRegistry, type RegistryDoc } from "./device-registry.ts";
import { FakeBlob } from "./fake-blob.ts";
import type { Finding } from "./heal-report.ts";

const noSleep = { sleep: async () => {} };
const store = (blob: FakeBlob<StoreSnapshot>, extra = {}): FleetStore =>
  createFleetStore({ io: blob.io(), ...noSleep, ...extra });

const findingOf = (count: number, lastSeen: string, status: Finding["status"] = "open"): Finding => ({
  schema: "heald.findings/v1",
  machineId: "node-a",
  fingerprint: "fp1",
  category: "disk",
  component: "c",
  severity: "warning",
  count,
  status,
  recurrenceCount: 0,
  linkedAction: null,
  firstSeen: "2026-11-20T10:00:00.000Z",
  lastSeen,
});
const T1 = "2026-11-21T10:00:00.000Z";
const T2 = "2026-11-21T11:00:00.000Z";

const eventOf = (summary: string): ActivityEntry => ({
  timestamp: T1,
  machineId: "node-a",
  type: "heal",
  summary,
  aiGenerated: false,
});

const blobFinding = (blob: FakeBlob<StoreSnapshot>) => blob.json().findings[0];

// ---- BLOCKER 1: updated findings must not be reverted by the stale blob ----

test("B1 an updated finding (newer lastSeen) reaches the blob on the same instance", async () => {
  const blob = new FakeBlob<StoreSnapshot>();
  const a = store(blob);
  await a.addFindings([findingOf(1, T1)]);
  await a.addFindings([findingOf(9, T2, "fixed")]);
  assert.equal(blobFinding(blob).count, 9);
  assert.equal(blobFinding(blob).status, "fixed");
  assert.equal((await a.getFindings())[0].count, 9, "refresh must not revert memory");
});

test("B1 a stale instance neither reverts the blob nor its own GET", async () => {
  const blob = new FakeBlob<StoreSnapshot>();
  const a = store(blob, { refreshMinIntervalMs: 0 });
  const b = store(blob, { refreshMinIntervalMs: 0 });
  await a.addFindings([findingOf(1, T1)]);
  await b.addFindings([findingOf(9, T2, "fixed")]);
  await a.addEvent(eventOf("unrelated")); // A flushes with its stale count=1 in memory
  assert.equal(blobFinding(blob).count, 9);
  assert.equal((await a.getFindings())[0].count, 9);
});

test("B1 an older finding arriving later does not replace a newer one", async () => {
  const s = createState();
  applySnapshot(s, { findings: [findingOf(9, T2)] });
  applySnapshot(s, { findings: [findingOf(1, T1)] });
  assert.equal(s.findings[0].count, 9);
});

// ---- FIX 2: a resent batch must not duplicate events ----

test("F2 resending the same events (503 → retry) does not duplicate them", async () => {
  const blob = new FakeBlob<StoreSnapshot>();
  const a = store(blob);
  await a.addEvent(eventOf("x"), { persist: false });
  await a.addEvent(eventOf("x"), { persist: false });
  await a.flush();
  assert.equal((await a.getEvents()).length, 1);
  assert.equal(blob.json().events.length, 1);
});

// ---- FIX 3: poison payloads / corrupt blob must not wedge the fleet ----

test("F3 validEvents drops non-object and incomplete events", () => {
  const ok = eventOf("ok");
  assert.deepEqual(validEvents([null, 5, "x", {}, { ...ok, summary: 3 }, ok]), [ok]);
  assert.deepEqual(validEvents("nope"), []);
});

test("F3 applySnapshot skips bad entries instead of throwing", () => {
  const s = createState();
  const bad = {
    machines: { x: null, y: 5, ok: { machineId: "ok", hostname: "ok", lastSeen: T1 } },
    events: [null, 7, eventOf("ok")],
    history: { x: "nope", ok: [{ timestamp: T1, cpu: 1, ramUsedGB: 1 }] },
    benchmarks: { x: null },
    heals: "nope",
    findings: [null],
  } as unknown as StoreSnapshot;
  assert.doesNotThrow(() => applySnapshot(s, bad));
  assert.deepEqual([...s.machines.keys()], ["ok"]);
  assert.equal(s.events.length, 1);
  assert.deepEqual([...s.metricsHistory.keys()], ["ok"]);
  assert.doesNotThrow(() => applySnapshot(s, null as unknown as StoreSnapshot));
});

test("F3 a blob with poisoned events does not wedge ingest or GET", async () => {
  const blob = new FakeBlob<StoreSnapshot>();
  blob.doc = JSON.stringify({ events: [null, { timestamp: null }], machines: { x: null } });
  const a = store(blob);
  await a.addEvent(eventOf("after"));
  assert.equal((await a.getEvents()).length, 1);
});

test("F3 corrupt blob JSON is tolerated (logged), not a permanent 503", async () => {
  assert.deepEqual(parseDoc("{not json"), {});
  assert.deepEqual(parseDoc("null"), {});
  assert.deepEqual(parseDoc("[1]"), {});
  const blob = new FakeBlob<StoreSnapshot>();
  blob.doc = "{not json";
  const a = store(blob);
  await a.addEvent(eventOf("after")); // must not throw
  assert.equal(blob.json().events.length, 1);
});

test("F3 a corrupt device registry blob does not wedge enroll/auth", async () => {
  const blob = new FakeBlob<RegistryDoc>();
  blob.doc = JSON.stringify({ devices: [null, 5, { deviceId: 1 }] });
  const reg = createDeviceRegistry({ io: blob.io(), ...noSleep });
  assert.equal(await reg.authenticate("unknown-token-0123456789"), false);
  await reg.register({ deviceId: "dev-a", token: "token-a-0123456789abcdef" });
  blob.doc = "{corrupt";
  await reg.register({ deviceId: "dev-b", token: "token-b-0123456789abcdef" });
});

// ---- FIX 4: bounded persist time ----

test("F4 casUpdate gives up at the deadline when the blob hangs", async () => {
  const blob = new FakeBlob<StoreSnapshot>();
  blob.hangWrites = 1;
  const t0 = Date.now();
  await assert.rejects(casUpdate(blob.io(), () => ({}) as StoreSnapshot, { deadlineMs: 50, ...noSleep }), PersistError);
  assert.ok(Date.now() - t0 < 1000);
});

test("F4 a hung flush rejects within budget and does not block later requests", async () => {
  const blob = new FakeBlob<StoreSnapshot>();
  const a = store(blob, { deadlineMs: 50 });
  blob.hangWrites = 1;
  await assert.rejects(a.addEvent(eventOf("1")), PersistError);
  await a.addEvent(eventOf("2")); // chain not wedged
  assert.equal(blob.json().events.length, 2);
});

test("F4 a hung blob read does not hang GET", async () => {
  const blob = new FakeBlob<StoreSnapshot>();
  await store(blob).addEvent(eventOf("1"));
  blob.hangReads = 1;
  const b = store(blob, { deadlineMs: 50 });
  assert.deepEqual(await b.getEvents(), []); // degraded: memory
});

// ---- FIX 5: GET amplification ----

test("F5 concurrent reads share one blob read; reads within the interval reuse memory", async () => {
  const blob = new FakeBlob<StoreSnapshot>();
  await store(blob).addEvent(eventOf("1"));
  const b = store(blob, { refreshMinIntervalMs: 60_000 });
  const reads = blob.reads;
  await Promise.all([b.getMachines(), b.getHistory("x"), b.getBenchmarkHistory("x"), b.getEvents()]);
  assert.equal(blob.reads - reads, 1);
  await b.getEvents();
  assert.equal(blob.reads - reads, 1);
});

test("F5 casUpdate's read uses the last known ETag (304 when unchanged)", async () => {
  const blob = new FakeBlob<StoreSnapshot>();
  const a = store(blob);
  await a.addEvent(eventOf("1"));
  await a.addEvent(eventOf("2"));
  assert.equal(blob.notModified, 1);
  assert.equal(blob.json().events.length, 2);
});

// ---- FIX 6: production without BLOB_READ_WRITE_TOKEN ----

test("F6 requireRemote without a blob: flush and enroll reject (→ 503)", async () => {
  const a = createFleetStore({ io: null, requireRemote: true });
  await assert.rejects(a.addEvent(eventOf("1")), PersistError);
  const reg = createDeviceRegistry({ io: null, requireRemote: true, envTokens: () => ["boot-token-0123456789"] });
  await assert.rejects(reg.register({ deviceId: "d", token: "token-a-0123456789abcdef" }), PersistError);
  assert.equal(await reg.authenticate("boot-token-0123456789"), true, "env bootstrap still works");
});

// ---- NIT: unknown tokens must not hammer the registry blob ----

test("N rate-limits miss-triggered registry reloads", async () => {
  const blob = new FakeBlob<RegistryDoc>();
  let now = new Date(T1);
  const reg = createDeviceRegistry({ io: blob.io(), now: () => now, missReloadIntervalMs: 10_000, ...noSleep });
  await reg.authenticate("unknown-token-0123456789");
  const reads = blob.reads;
  await reg.authenticate("unknown-token-0123456789");
  await reg.authenticate("other-unknown-0123456789");
  assert.equal(blob.reads, reads);
  now = new Date(Date.parse(T1) + 11_000);
  await reg.authenticate("unknown-token-0123456789");
  assert.equal(blob.reads, reads + 1);
});
