import { NextResponse } from "next/server";
import { validateAdminKey, validateApiKey, extractBearer } from "@/lib/auth";
import { listDevices, registerDevice } from "@/lib/devices";

/**
 * POST /api/enroll — register a device token (admin key required)
 * body: { deviceId, token, hostname?, serialNumber? }
 *
 * GET /api/enroll — list devices (admin) or self-check with device token
 */
export async function POST(request: Request) {
  if (!validateAdminKey(request)) {
    return NextResponse.json({ error: "Unauthorized — admin key required" }, { status: 401 });
  }
  try {
    const body = await request.json();
    const deviceId = String(body.deviceId ?? "").trim();
    const token = String(body.token ?? "").trim();
    if (!deviceId || !token || token.length < 16) {
      return NextResponse.json({ error: "deviceId and token (min 16) required" }, { status: 400 });
    }
    const d = registerDevice({
      deviceId,
      token,
      hostname: body.hostname ? String(body.hostname) : undefined,
      serialNumber: body.serialNumber ? String(body.serialNumber) : undefined,
    });
    return NextResponse.json({
      ok: true,
      deviceId: d.deviceId,
      enrolledAt: d.enrolledAt,
    });
  } catch {
    return NextResponse.json({ error: "Invalid payload" }, { status: 400 });
  }
}

export async function GET(request: Request) {
  // Admin lists devices
  if (validateAdminKey(request)) {
    return NextResponse.json({ devices: listDevices() });
  }
  // Device token: confirm valid
  if (validateApiKey(request)) {
    const token = extractBearer(request);
    return NextResponse.json({ ok: true, auth: "device_or_key", tokenPrefix: token?.slice(0, 8) });
  }
  return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
}
