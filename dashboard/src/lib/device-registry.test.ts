// Issue #17: the device registry must survive instance recycling (Vercel
// Fluid), store only token hashes, and never lose a concurrent enroll.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createDeviceRegistry, hashToken, type RegistryDoc } from "./device-registry.ts";
import { PersistError, type DocIO } from "./blob-cas.ts";

class Conflict extends Error {}
const tick = () => new Promise((r) => setImmediate(r));
const noSleep = { sleep: async () => {} };

/** Fake blob doc with ETag semantics + If-None-Match. */
class FakeDoc {
  doc: string | null = null;
  version = 0;
  reads = 0;
  failWrites = 0;
  io(): DocIO<RegistryDoc> {
    return {
      read: async (ifNoneMatch) => {
        await tick();
        this.reads++;
        if (this.doc === null) return null;
        const etag = `e${this.version}`;
        if (ifNoneMatch === etag) return { notModified: true, etag };
        return { snapshot: JSON.parse(this.doc), etag };
      },
      write: async (doc, etag) => {
        await tick();
        if (this.failWrites > 0) {
          this.failWrites--;
          throw new Error("blob 503");
        }
        if (etag ? etag !== `e${this.version}` : this.doc !== null) throw new Conflict();
        this.doc = JSON.stringify(doc);
        return `e${++this.version}`;
      },
      isConflict: (e) => e instanceof Conflict,
    };
  }
}

const TOKEN_A = "token-a-0123456789abcdef";
const TOKEN_B = "token-b-0123456789abcdef";

test("#17 a token enrolled on one instance authenticates on another (and after a cold start)", async () => {
  const blob = new FakeDoc();
  let now = new Date("2026-11-21T10:00:00Z");
  const a = createDeviceRegistry({ io: blob.io(), ...noSleep });
  const b = createDeviceRegistry({ io: blob.io(), now: () => now, ...noSleep });
  assert.equal(await b.authenticate(TOKEN_A), false); // warm B with an empty view
  await a.register({ deviceId: "dev-a", token: TOKEN_A, hostname: "node-a" });
  now = new Date("2026-11-21T10:00:11Z"); // past the 10 s miss-reload limit

  assert.equal(await b.authenticate(TOKEN_A), true, "warm instance re-reads on a miss");
  const cold = createDeviceRegistry({ io: blob.io(), ...noSleep });
  assert.equal(await cold.authenticate(TOKEN_A), true, "cold instance");
  assert.equal(await cold.authenticate("wrong-token-0123456789"), false);
});

test("#17 only sha256(token) is persisted, never the token", async () => {
  const blob = new FakeDoc();
  const reg = createDeviceRegistry({ io: blob.io(), ...noSleep });
  await reg.register({ deviceId: "dev-a", token: TOKEN_A });
  assert.ok(blob.doc);
  assert.ok(!blob.doc.includes(TOKEN_A));
  assert.ok(!blob.doc.includes(TOKEN_A.slice(0, 8)));
  const doc = JSON.parse(blob.doc) as RegistryDoc;
  assert.equal(doc.devices[0].tokenHash, hashToken(TOKEN_A));
  const listed = await reg.list();
  assert.equal(listed.length, 1);
  assert.ok(!("tokenHash" in listed[0]) && !("token" in listed[0]));
  assert.equal(listed[0].tokenFingerprint, hashToken(TOKEN_A).slice(0, 12));
});

test("#17 concurrent enrolls on two instances both survive", async () => {
  const blob = new FakeDoc();
  const a = createDeviceRegistry({ io: blob.io(), ...noSleep });
  const b = createDeviceRegistry({ io: blob.io(), ...noSleep });
  await Promise.all([
    a.register({ deviceId: "dev-a", token: TOKEN_A }),
    b.register({ deviceId: "dev-b", token: TOKEN_B }),
  ]);
  const doc = JSON.parse(blob.doc!) as RegistryDoc;
  assert.deepEqual(doc.devices.map((d) => d.deviceId).sort(), ["dev-a", "dev-b"]);
  const cold = createDeviceRegistry({ io: blob.io(), ...noSleep });
  assert.equal(await cold.authenticate(TOKEN_A), true);
  assert.equal(await cold.authenticate(TOKEN_B), true);
});

test("#17 re-enrolling a device replaces its old token", async () => {
  const blob = new FakeDoc();
  const reg = createDeviceRegistry({ io: blob.io(), ...noSleep });
  await reg.register({ deviceId: "dev-a", token: TOKEN_A });
  await reg.register({ deviceId: "dev-a", token: TOKEN_B });
  const cold = createDeviceRegistry({ io: blob.io(), ...noSleep });
  assert.equal(await cold.authenticate(TOKEN_A), false);
  assert.equal(await cold.authenticate(TOKEN_B), true);
  assert.equal((await cold.list()).length, 1);
});

test("#17 register rejects with PersistError when the blob write fails (enroll → 503)", async () => {
  const blob = new FakeDoc();
  blob.failWrites = 1;
  const reg = createDeviceRegistry({ io: blob.io(), ...noSleep });
  await assert.rejects(reg.register({ deviceId: "dev-a", token: TOKEN_A }), PersistError);
  assert.equal(await reg.authenticate(TOKEN_A), false, "not enrolled when not durable");
});

test("#17 HEALD_DEVICE_TOKENS bootstrap tokens still authenticate (no blob needed)", async () => {
  const reg = createDeviceRegistry({ io: null, envTokens: () => [TOKEN_A] });
  assert.equal(await reg.authenticate(TOKEN_A), true);
  assert.equal(await reg.authenticate(TOKEN_B), false);
  assert.equal(await reg.authenticate(""), false);
});

test("#17 in-memory fallback without a blob token", async () => {
  const reg = createDeviceRegistry({ io: null });
  await reg.register({ deviceId: "dev-a", token: TOKEN_A });
  assert.equal(await reg.authenticate(TOKEN_A), true);
});

test("#17 a known token is served from memory; lastSeen persisted at most once per interval", async () => {
  const blob = new FakeDoc();
  let now = new Date("2026-11-21T10:00:00Z");
  const reg = createDeviceRegistry({ io: blob.io(), now: () => now, touchIntervalMs: 60_000, ...noSleep });
  await reg.register({ deviceId: "dev-a", token: TOKEN_A });
  const v = blob.version;
  const reads = blob.reads;
  now = new Date("2026-11-21T10:00:30Z");
  assert.equal(await reg.authenticate(TOKEN_A), true);
  assert.equal(blob.version, v, "no write inside the interval");
  assert.equal(blob.reads, reads, "hit served from memory");
  now = new Date("2026-11-21T10:02:00Z");
  assert.equal(await reg.authenticate(TOKEN_A), true);
  assert.equal(blob.version, v + 1, "lastSeen persisted after the interval");
  const doc = JSON.parse(blob.doc!) as RegistryDoc;
  assert.equal(doc.devices[0].lastSeen, "2026-11-21T10:02:00.000Z");
});

test("#17 corrupt registry entries are ignored", async () => {
  const blob = new FakeDoc();
  blob.doc = JSON.stringify({ version: 1, devices: [{ deviceId: "x", token: TOKEN_A }, { deviceId: "y", tokenHash: "zz" }] });
  const reg = createDeviceRegistry({ io: blob.io(), ...noSleep });
  assert.equal(await reg.authenticate(TOKEN_A), false);
  assert.deepEqual(await reg.list(), []);
});
