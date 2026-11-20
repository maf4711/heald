import { NextResponse } from "next/server";
import { getHeals } from "@/lib/store";
import { clampLimit } from "@/lib/heal-report";

// GET /api/heals?machineId=&limit= — central autoheal log (heald.heal_report/v1),
// newest first; limit clamped to 1..500. Public like GET /api/events.
export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const machineId = searchParams.get("machineId") || undefined;
  const limit = clampLimit(searchParams.get("limit"));

  return NextResponse.json(
    { heals: await getHeals(machineId, limit) },
    { headers: { "Cache-Control": "no-store" } }
  );
}
