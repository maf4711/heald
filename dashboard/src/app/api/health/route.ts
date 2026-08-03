import { NextResponse } from "next/server";

/**
 * GET /api/health — public liveness for uptime monitors and ops.
 */
export async function GET() {
  return NextResponse.json(
    {
      ok: true,
      service: "heald",
      time: new Date().toISOString(),
    },
    {
      headers: {
        "Cache-Control": "no-store",
      },
    }
  );
}
