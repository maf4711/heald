// POST /api/ingest logic without Next.js types, so node --test can drive it
// with a fake store / fake auth. The route only adapts Request ↔ response.
//
// 200 only once everything is durably in the blob snapshot (issue #19): the
// daemon advances its heal cursor on 200. A storage failure answers 503 so
// the daemon keeps the batch and resends it (merge is idempotent by heal id).
// Never 4xx for server-side failures: the daemon treats 4xx as a poison batch.

import { ingestBody } from "./heal-report.ts";
import { validEvents } from "./store-snapshot.ts";
import type { FleetStore } from "./fleet-store.ts";
import { withDeadline } from "./blob-cas.ts";

export type IngestStore = Pick<FleetStore, "upsertMachine" | "addEvent" | "addHeals" | "addFindings" | "flush">;

export interface IngestDeps {
  authorized: () => Promise<boolean>;
  /** Parsed JSON body; throws on invalid JSON. */
  body: () => Promise<unknown>;
  store: IngestStore;
}

export type IngestResponse = { status: number; json: unknown; headers?: Record<string, string> };

const unavailable = (): IngestResponse => ({
  status: 503,
  json: { error: "Storage unavailable, retry later" },
  headers: { "Retry-After": "5" },
});

/** Whole-request budget: the daemon's URLSession times out at 7 s. */
export const INGEST_DEADLINE_MS = 6000;

/**
 * Auth (may re-read the device registry), body, buffered writes and the
 * durable flush (possibly queued behind another flush on this instance)
 * share one deadline; past it the answer is 503 so the daemon retries.
 * Work still running in the background is idempotent on resend.
 */
export async function processIngest({
  deadlineMs = INGEST_DEADLINE_MS,
  ...deps
}: IngestDeps & { deadlineMs?: number }): Promise<IngestResponse> {
  try {
    return await withDeadline(deadlineMs, () => run(deps));
  } catch (err) {
    console.error("ingest: request deadline exceeded", err);
    return unavailable();
  }
}

async function run({ authorized, body: readBody, store }: IngestDeps): Promise<IngestResponse> {
  if (!(await authorized())) return { status: 401, json: { error: "Unauthorized" } };

  let body: Record<string, unknown>;
  try {
    body = (await readBody()) as Record<string, unknown>;
  } catch {
    return { status: 400, json: { error: "Invalid payload" } };
  }

  // Validate heals/findings shape before any write so a 400 stores nothing
  const result = ingestBody(body);
  if (result.status === 400) return { status: 400, json: result.json };

  try {
    // Buffer every write, then persist once (one blob read-merge-write per request)
    const deferred = { persist: false };
    const metrics = body.metrics;
    if (typeof metrics === "object" && metrics !== null && !Array.isArray(metrics)) {
      await store.upsertMachine(metrics as Parameters<IngestStore["upsertMachine"]>[0], deferred);
    }

    // Drop malformed events: one poisoned entry must never reach the shared snapshot
    for (const event of validEvents(body.events)) {
      await store.addEvent(event, deferred);
    }

    if (result.heals.length) await store.addHeals(result.heals, deferred);
    if (result.findings.length) await store.addFindings(result.findings, deferred);
    await store.flush();
  } catch (err) {
    console.error("ingest: snapshot not persisted", err);
    return unavailable();
  }

  return { status: 200, json: result.json };
}
