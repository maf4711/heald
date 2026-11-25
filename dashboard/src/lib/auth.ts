// API key + device token validation (CLOUD-03 + Wave 2 device registry).
// HEALD_API_KEYS — comma-separated lab/admin keys
// HEALD_DEVICE_TOKENS — optional bootstrap device tokens
// Registered devices via POST /api/enroll also validate.

import { authenticateDevice } from "./devices";

export function extractBearer(request: Request): string | null {
  const authHeader = request.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;
  return authHeader.slice(7).trim() || null;
}

export async function validateApiKey(request: Request): Promise<boolean> {
  const key = extractBearer(request);
  if (!key) return false;

  const validKeys = (process.env.HEALD_API_KEYS ?? "")
    .split(",")
    .map((k) => k.trim())
    .filter(Boolean);

  if (validKeys.includes(key)) return true;

  // Per-device tokens (env + durable registry); fail-closed on a miss
  return authenticateDevice(key);
}

/** Admin operations (enroll register, list devices) — HEALD_API_KEYS only. */
export function validateAdminKey(request: Request): boolean {
  const key = extractBearer(request);
  if (!key) return false;
  const validKeys = (process.env.HEALD_API_KEYS ?? "")
    .split(",")
    .map((k) => k.trim())
    .filter(Boolean);
  if (validKeys.length === 0) return false;
  return validKeys.includes(key);
}
