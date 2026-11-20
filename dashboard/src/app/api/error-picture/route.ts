import { NextResponse } from "next/server";
import { getErrorPicture } from "@/lib/store";

// GET /api/error-picture — per-machine "Fehlerbild" (open findings by
// severity, fixed count, last successful heal) computed server-side over the
// full heal and finding buckets. Public like GET /api/events.
export async function GET() {
  return NextResponse.json(
    { machines: await getErrorPicture() },
    { headers: { "Cache-Control": "no-store" } }
  );
}
