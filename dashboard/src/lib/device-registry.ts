// Device token registry core (issue #17). Durable in a remote JSON document
// (Vercel Blob via blob-json.ts, a fake in tests) using the same ETag CAS as
// the fleet store. Only sha256(token) is stored; lookups compare hashes in
// constant time. devices.ts binds one instance per isolate.

import { createHash, timingSafeEqual } from "node:crypto";
import { casUpdate, PersistError, READ_DEADLINE_MS, withDeadline, type CasOptions, type DocIO } from "./blob-cas.ts";

export type DeviceRecord = {
  deviceId: string;
  /** hex sha256 of the bearer token; the token itself is never stored */
  tokenHash: string;
  hostname?: string;
  serialNumber?: string;
  enrolledAt: string;
  lastSeen?: string;
};

export type RegistryDoc = { version: 1; devices: DeviceRecord[] };

/** Device as listed to admins: no hash, only a short fingerprint of it. */
export type PublicDevice = Omit<DeviceRecord, "tokenHash"> & { tokenFingerprint: string };

export interface DeviceRegistryOptions extends Omit<CasOptions, "knownEtag"> {
  io: DocIO<RegistryDoc> | null;
  /** No remote is a misconfiguration (prod): register throws instead of memory-only. */
  requireRemote?: boolean;
  /** Unknown tokens trigger a registry reload at most this often (default 10 s). */
  missReloadIntervalMs?: number;
  /** Bootstrap tokens (HEALD_DEVICE_TOKENS); read on every call. */
  envTokens?: () => string[];
  now?: () => Date;
  /** Persist lastSeen at most this often per device (default 15 min). */
  touchIntervalMs?: number;
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

const HASH_BYTES = 32;

function sameHash(aHex: string, bHex: string): boolean {
  const a = Buffer.from(aHex, "hex");
  const b = Buffer.from(bHex, "hex");
  return a.length === HASH_BYTES && b.length === HASH_BYTES && timingSafeEqual(a, b);
}

/** Index of `hash` in `hashes`; scans every entry (no early exit on match). */
function findHash(hash: string, hashes: readonly string[]): number {
  let found = -1;
  for (let i = 0; i < hashes.length; i++) {
    const eq = sameHash(hash, hashes[i]);
    if (eq && found === -1) found = i;
  }
  return found;
}

function validDoc(doc: unknown): DeviceRecord[] {
  const devices = (doc as Partial<RegistryDoc> | null)?.devices;
  if (!Array.isArray(devices)) return [];
  return devices.filter(
    (d): d is DeviceRecord =>
      !!d && typeof d.deviceId === "string" && typeof d.tokenHash === "string" && /^[0-9a-f]{64}$/.test(d.tokenHash),
  );
}

export function createDeviceRegistry({
  io,
  requireRemote = false,
  envTokens = () => [],
  now = () => new Date(),
  touchIntervalMs = 15 * 60_000,
  missReloadIntervalMs = 10_000,
  ...cas
}: DeviceRegistryOptions) {
  let devices: DeviceRecord[] = [];
  let lastEtag: string | undefined;
  let lastMissReload = -Infinity;
  const readBudget = cas.deadlineMs ?? READ_DEADLINE_MS;

  function load(list: DeviceRecord[]) {
    // Keep a newer in-memory lastSeen (touches are persisted lazily)
    const seen = new Map(devices.map((d) => [d.deviceId, d.lastSeen ?? ""]));
    devices = list.map((d) => {
      const mine = seen.get(d.deviceId) ?? "";
      return mine > (d.lastSeen ?? "") ? { ...d, lastSeen: mine } : { ...d };
    });
  }

  /** Re-read the remote registry (304 when unchanged). Read errors keep memory. */
  async function refresh() {
    if (!io) return;
    const remoteIO = io;
    try {
      const remote = await withDeadline(readBudget, (signal) => remoteIO.read(lastEtag, signal));
      if (!remote || remote.notModified) return;
      load(validDoc(remote.snapshot));
      lastEtag = remote.etag;
    } catch {
      /* serve memory */
    }
  }

  /** CAS-update the remote registry with `change` applied to the remote list. */
  async function update(change: (list: DeviceRecord[]) => DeviceRecord[]) {
    if (!io) {
      if (requireRemote) throw new PersistError("blob storage not configured (BLOB_READ_WRITE_TOKEN missing)");
      devices = change(devices);
      return;
    }
    let written: DeviceRecord[] = [];
    lastEtag = await casUpdate(
      io,
      // unchanged (304 on lastEtag): memory is that version (plus lazy lastSeen)
      (remote, unchanged): RegistryDoc => {
        written = change(unchanged ? devices : validDoc(remote));
        return { version: 1, devices: written };
      },
      { ...cas, knownEtag: lastEtag },
    );
    load(written);
  }

  const lookup = (hash: string) => {
    const i = findHash(hash, devices.map((d) => d.tokenHash));
    return i === -1 ? undefined : devices[i];
  };

  /** Persist lastSeen at most once per touchIntervalMs; failures are ignored. */
  async function touch(d: DeviceRecord) {
    const ts = now();
    if (d.lastSeen && ts.getTime() - Date.parse(d.lastSeen) < touchIntervalMs) return;
    d.lastSeen = ts.toISOString();
    try {
      await update((list) => list.map((x) => (x.deviceId === d.deviceId ? { ...x, lastSeen: d.lastSeen } : x)));
    } catch {
      /* lastSeen is informational */
    }
  }

  return {
    /**
     * True when `token` is a bootstrap env token or an enrolled device's
     * token (memory first, then a fresh registry read on a miss).
     */
    async authenticate(token: string): Promise<boolean> {
      if (!token) return false;
      const hash = hashToken(token);
      if (findHash(hash, envTokens().map(hashToken)) !== -1) return true;
      let d = lookup(hash);
      const t = now().getTime();
      // Unknown tokens (bad clients) must not turn into one blob read per request
      if (!d && t - lastMissReload >= missReloadIntervalMs) {
        lastMissReload = t;
        await refresh();
        d = lookup(hash);
      }
      if (!d) return false;
      await touch(d);
      return true;
    },

    /**
     * Enroll (or re-enroll, replacing the old token) a device. Resolves only
     * once the registry is durably written; throws PersistError otherwise.
     */
    async register(input: { deviceId: string; token: string; hostname?: string; serialNumber?: string }) {
      const ts = now().toISOString();
      const record: DeviceRecord = {
        deviceId: input.deviceId,
        tokenHash: hashToken(input.token),
        hostname: input.hostname,
        serialNumber: input.serialNumber,
        enrolledAt: ts,
        lastSeen: ts,
      };
      await update((list) => [...list.filter((d) => d.deviceId !== input.deviceId), record]);
      return { deviceId: record.deviceId, enrolledAt: record.enrolledAt };
    },

    async list(): Promise<PublicDevice[]> {
      await refresh();
      return devices.map(({ tokenHash, ...rest }) => ({ ...rest, tokenFingerprint: tokenHash.slice(0, 12) }));
    },
  };
}

export type DeviceRegistry = ReturnType<typeof createDeviceRegistry>;
