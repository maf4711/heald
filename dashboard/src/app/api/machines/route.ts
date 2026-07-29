import { NextResponse } from "next/server";
import { getMachines, getHistory, getBenchmarkHistory } from "@/lib/store";

// GET /api/machines — returns all connected machines with metrics (CLOUD-05)
export async function GET() {
  const list = await getMachines();
  const machines = await Promise.all(
    list.map(async (m) => ({
      ...m,
      history: await getHistory(m.machineId),
      benchmarkHistory: await getBenchmarkHistory(m.machineId),
    }))
  );

  return NextResponse.json(
    { machines },
    { headers: { "Cache-Control": "no-store" } }
  );
}
