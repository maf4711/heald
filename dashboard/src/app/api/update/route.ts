import { NextResponse } from "next/server";
import { getClientRelease } from "@/lib/client-release";

/**
 * GET /api/update — public manifest for daemon self-update.
 * Clients compare `version` to their own and download `url` when newer.
 */
export async function GET() {
  const release = getClientRelease();

  return NextResponse.json(
    {
      version: release.version,
      url: release.url,
      sha256: release.sha256 || null,
      minMacOS: release.minMacOS ?? null,
      notes: release.notes ?? null,
      publishedAt: new Date().toISOString(),
    },
    {
      headers: {
        "Cache-Control": "public, s-maxage=60, stale-while-revalidate=300",
      },
    }
  );
}
