import { NextResponse } from "next/server";
import { getMachines, getHistory } from "@/lib/store";

// GET /api/machines — returns all connected machines with metrics (CLOUD-05)
export async function GET() {
  const machines = getMachines().map((m) => ({
    ...m,
    history: getHistory(m.machineId),
  }));

  return NextResponse.json({ machines });
}
