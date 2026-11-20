import { NextResponse } from "next/server";
import { getFindings } from "@/lib/store";
import { clampLimit, publicFinding } from "@/lib/heal-report";

// GET /api/findings?machineId=&limit= — fleet findings (heald.findings/v1),
// newest lastSeen first; limit clamped to 1..500. Public like GET /api/events,
// so the raw `sample` text is omitted (it stays in the store).
export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const machineId = searchParams.get("machineId") || undefined;
  const limit = clampLimit(searchParams.get("limit"));

  return NextResponse.json(
    { findings: (await getFindings(machineId, limit)).map(publicFinding) },
    { headers: { "Cache-Control": "no-store" } }
  );
}
