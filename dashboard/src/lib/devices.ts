/**
 * Device token registry (Wave 2 / P3.c, durable since issue #17).
 * Tokens registered via POST /api/enroll are valid Bearer credentials for
 * ingest. The registry lives in Vercel Blob (same ETag CAS as the fleet
 * store) and stores only sha256(token). HEALD_DEVICE_TOKENS env
 * (comma-separated) is still accepted for bootstrap.
 * Without BLOB_READ_WRITE_TOKEN (local dev) it is in-memory only.
 */
import { blobJsonIO, blobRequired } from "./blob-json";
import { createDeviceRegistry, type DeviceRegistry, type PublicDevice, type RegistryDoc } from "./device-registry";

const BLOB_PATHNAME = "heald-device-registry.json";

function envTokens(): string[] {
  return (process.env.HEALD_DEVICE_TOKENS ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

const g = globalThis as typeof globalThis & { __healdDeviceRegistry?: DeviceRegistry };

function registry(): DeviceRegistry {
  g.__healdDeviceRegistry ??= createDeviceRegistry({
    io: blobJsonIO<RegistryDoc>(BLOB_PATHNAME),
    requireRemote: blobRequired(),
    envTokens,
  });
  return g.__healdDeviceRegistry;
}

/** Env or enrolled device token; also refreshes the device's lastSeen (throttled). */
export function authenticateDevice(token: string): Promise<boolean> {
  return registry().authenticate(token);
}

/** Durable enroll; throws PersistError when the registry write did not land. */
export function registerDevice(input: {
  deviceId: string;
  token: string;
  hostname?: string;
  serialNumber?: string;
}): Promise<{ deviceId: string; enrolledAt: string }> {
  return registry().register(input);
}

export function listDevices(): Promise<PublicDevice[]> {
  return registry().list();
}
