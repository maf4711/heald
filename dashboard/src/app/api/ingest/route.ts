import { NextResponse } from "next/server";
import { validateApiKey } from "@/lib/auth";
import { upsertMachine, addEvent, addHeals, addFindings } from "@/lib/store";
import { ingestBody } from "@/lib/heal-report";

// POST /api/ingest — receives metric push from daemon (CLOUD-02)
// plus heal reports (heald.heal_report/v1) and findings (heald.findings/v1).
export async function POST(request: Request) {
  if (!validateApiKey(request)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();

    // Validate heals/findings shape before any write so a 400 stores nothing
    const result = ingestBody(body);
    if (result.status === 400) {
      return NextResponse.json(result.json, { status: 400 });
    }

    if (body.metrics) {
      await upsertMachine(body.metrics);
    }

    if (body.events && Array.isArray(body.events)) {
      for (const event of body.events) {
        await addEvent(event);
      }
    }

    if (result.heals.length) await addHeals(result.heals);
    if (result.findings.length) await addFindings(result.findings);

    return NextResponse.json(result.json);
  } catch {
    return NextResponse.json({ error: "Invalid payload" }, { status: 400 });
  }
}
