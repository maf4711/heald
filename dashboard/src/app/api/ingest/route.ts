import { NextResponse } from "next/server";
import { validateApiKey } from "@/lib/auth";
import { upsertMachine, addEvent, addHeals, addFindings, flush } from "@/lib/store";
import { processIngest } from "@/lib/ingest";

// POST /api/ingest — receives metric push from daemon (CLOUD-02)
// plus heal reports (heald.heal_report/v1) and findings (heald.findings/v1).
// Status contract (200 = durable, 503 = retry, 4xx = poison) in lib/ingest.ts.
export async function POST(request: Request) {
  const r = await processIngest({
    authorized: () => validateApiKey(request),
    body: () => request.json(),
    store: { upsertMachine, addEvent, addHeals, addFindings, flush },
  });
  return NextResponse.json(r.json, { status: r.status, headers: r.headers });
}
