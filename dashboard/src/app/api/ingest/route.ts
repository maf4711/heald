import { NextResponse } from "next/server";
import { validateApiKey } from "@/lib/auth";
import { upsertMachine, addEvent, addHeals, addFindings, flush } from "@/lib/store";
import { ingestBody } from "@/lib/heal-report";
import { validEvents } from "@/lib/store-snapshot";

// POST /api/ingest — receives metric push from daemon (CLOUD-02)
// plus heal reports (heald.heal_report/v1) and findings (heald.findings/v1).
//
// 200 only once everything is durably in the blob snapshot (issue #19): the
// daemon advances its heal cursor on 200. A storage failure answers 503 so
// the daemon keeps the batch and resends it (merge is idempotent by heal id).
// Never 4xx for server-side failures: the daemon treats 4xx as a poison batch.
export async function POST(request: Request) {
  if (!(await validateApiKey(request))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid payload" }, { status: 400 });
  }

  // Validate heals/findings shape before any write so a 400 stores nothing
  const result = ingestBody(body);
  if (result.status === 400) {
    return NextResponse.json(result.json, { status: 400 });
  }

  try {
    // Buffer every write, then persist once (one blob read-merge-write per request)
    const deferred = { persist: false };
    const metrics = body.metrics;
    if (typeof metrics === "object" && metrics !== null && !Array.isArray(metrics)) {
      await upsertMachine(metrics as Parameters<typeof upsertMachine>[0], deferred);
    }

    // Drop malformed events: one poisoned entry must never reach the shared snapshot
    for (const event of validEvents(body.events)) {
      await addEvent(event, deferred);
    }

    if (result.heals.length) await addHeals(result.heals, deferred);
    if (result.findings.length) await addFindings(result.findings, deferred);
    await flush();
  } catch (err) {
    console.error("ingest: snapshot not persisted", err);
    return NextResponse.json(
      { error: "Storage unavailable, retry later" },
      { status: 503, headers: { "Retry-After": "5" } },
    );
  }

  return NextResponse.json(result.json);
}
