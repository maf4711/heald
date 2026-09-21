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
  version: "3.5.0",
  url: "https://github.com/maf4711/heald/releases/latest/download/heald",
  sha256: "4382e718380e390909d3ed1b0953d40087da34989d9a4bf0c42ff7528c05a13a",
  minMacOS: "26.0",
  notes: "heald 3.5.0 — auto-distribution enabled (poll /api/update)",
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
