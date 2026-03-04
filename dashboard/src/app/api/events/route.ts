import { NextResponse } from "next/server";
import { getEvents } from "@/lib/store";

// GET /api/events — returns activity feed (DASH-02)
export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const machineId = searchParams.get("machineId") ?? undefined;
  const limit = parseInt(searchParams.get("limit") ?? "50", 10);

  return NextResponse.json({ events: getEvents(machineId, limit) });
}
