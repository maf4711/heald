/**
 * Latest heald client (daemon binary) release — source of truth for /api/update.
 *
 * On every release:
 * 1. Bump `version` to match HealdApp.version
 * 2. Point `url` at the GitHub release asset (or CDN)
 * 3. Set `sha256` from: shasum -a 256 .build/release/heald
 *
 * Env overrides (Vercel): HEALD_CLIENT_VERSION, HEALD_CLIENT_URL, HEALD_CLIENT_SHA256
 */
export type ClientRelease = {
  version: string;
  url: string;
  sha256: string;
  minMacOS?: string;
  notes?: string;
};

const defaults: ClientRelease = {
  version: "3.2.0",
  url: "https://github.com/maf4711/heald/releases/latest/download/heald",
  // Fill after release: shasum -a 256 .build/release/heald
  sha256: "",
  minMacOS: "26.0",
  notes: "Phase A bank pilot: bank preset, enroll, PII redaction, compliance v2, SIEM",
};

export function getClientRelease(): ClientRelease {
  return {
    version: process.env.HEALD_CLIENT_VERSION?.trim() || defaults.version,
    url: process.env.HEALD_CLIENT_URL?.trim() || defaults.url,
    sha256: process.env.HEALD_CLIENT_SHA256?.trim() || defaults.sha256,
    minMacOS: defaults.minMacOS,
    notes: defaults.notes,
  };
}
