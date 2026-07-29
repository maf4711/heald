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
  version: "3.1.0",
  url: "https://github.com/maf4711/heald/releases/download/v3.1.0/heald",
  // shasum -a 256 .build/release/heald
  sha256: "fc18939f9cbc429d3c78caaae22e2e1c82b56904ca8166d8e7ba305f5deb23ab",
  minMacOS: "26.0",
  notes: "heald 3.1 enterprise: policy, crash-loop, battery, network, webhooks, compliance, native self-heal",
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
