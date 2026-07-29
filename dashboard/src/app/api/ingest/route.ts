import { NextResponse } from "next/server";
import { validateApiKey } from "@/lib/auth";
import { upsertMachine, addEvent } from "@/lib/store";

// POST /api/ingest — receives metric push from daemon (CLOUD-02)
export async function POST(request: Request) {
  if (!validateApiKey(request)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();

    if (body.metrics) {
      await upsertMachine(body.metrics);
    }

    if (body.events && Array.isArray(body.events)) {
      for (const event of body.events) {
        await addEvent(event);
      }
    }

    return NextResponse.json({ ok: true });
  } catch {
    return NextResponse.json({ error: "Invalid payload" }, { status: 400 });
  }
}
