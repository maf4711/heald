/**
 * Device token registry (Wave 2 / P3.c).
 * Tokens registered via POST /api/enroll are valid Bearer credentials for ingest.
 * Also accepts HEALD_DEVICE_TOKENS env (comma-separated) for bootstrap.
 */
import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

type Device = {
  deviceId: string;
  token: string;
  hostname?: string;
  serialNumber?: string;
  enrolledAt: string;
  lastSeen?: string;
};

const FILE = join(tmpdir(), "heald-device-registry.json");

const g = globalThis as typeof globalThis & { __healdDevices?: Map<string, Device> };

function map(): Map<string, Device> {
  if (!g.__healdDevices) {
    g.__healdDevices = new Map();
    load();
  }
  return g.__healdDevices;
}

function load() {
  try {
    if (!existsSync(FILE)) return;
    const raw = JSON.parse(readFileSync(FILE, "utf8")) as Device[];
    for (const d of raw) {
      if (d.deviceId && d.token) g.__healdDevices!.set(d.token, d);
    }
  } catch {
    /* ignore */
  }
}

function persist() {
  try {
    writeFileSync(FILE, JSON.stringify(Array.from(map().values()), null, 2));
  } catch {
    /* ignore */
  }
}

function envTokens(): Set<string> {
  return new Set(
    (process.env.HEALD_DEVICE_TOKENS ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean)
  );
}

export function isDeviceToken(token: string): boolean {
  if (!token) return false;
  if (envTokens().has(token)) return true;
  return map().has(token);
}

export function registerDevice(input: {
  deviceId: string;
  token: string;
  hostname?: string;
  serialNumber?: string;
}): Device {
  const d: Device = {
    deviceId: input.deviceId,
    token: input.token,
    hostname: input.hostname,
    serialNumber: input.serialNumber,
    enrolledAt: new Date().toISOString(),
    lastSeen: new Date().toISOString(),
  };
  map().set(d.token, d);
  persist();
  return d;
}

export function touchDeviceByToken(token: string) {
  const d = map().get(token);
  if (!d) return;
  d.lastSeen = new Date().toISOString();
  map().set(token, d);
  persist();
}

export function listDevices(): Device[] {
  return Array.from(map().values()).map((d) => ({
    ...d,
    token: d.token.slice(0, 8) + "…",
  }));
}
