"use client";

import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer } from "recharts";

interface Machine {
  machineId: string;
  hostname: string;
  lastSeen: string;
  cpu?: { overall: number; perCore: number[] };
  ram?: { usedGB: number; wiredGB: number; compressedGB: number; swapUsedMB: number; pressureLevel: number };
  disk?: { volumes: { name: string; mountPoint: string; totalGB: number; freeGB: number }[]; smart: { bsdName: string; status: string }[] };
  processes?: {
    topCPU: { pid: number; name: string; cpuPercent: number; ramMB: number; system: boolean }[];
    topRAM: { pid: number; name: string; cpuPercent: number; ramMB: number; system: boolean }[];
  };
  history: { timestamp: string; cpu: number; ramUsedGB: number }[];
}

function healthColor(machine: Machine): string {
  const disk = machine.disk;
  const ram = machine.ram;
  const pressureLevel = ram?.pressureLevel ?? 0;
  const swapUsedMB = ram?.swapUsedMB ?? 0;

  // Red: SMART failing, pressure critical, or disk >90%
  if (disk?.smart?.some((s) => s.status === "Failing")) return "#ef4444";
  if (pressureLevel >= 4) return "#ef4444";
  const rootVol = disk?.volumes?.find((v) => v.mountPoint === "/");
  if (rootVol && (rootVol.totalGB - rootVol.freeGB) / rootVol.totalGB > 0.9) return "#ef4444";

  // Yellow: pressure warning, swap > 2GB, disk >80%
  if (pressureLevel >= 2) return "#eab308";
  if (swapUsedMB > 2048) return "#eab308";
  if (rootVol && (rootVol.totalGB - rootVol.freeGB) / rootVol.totalGB > 0.8) return "#eab308";

  return "#22c55e"; // Green
}

function timeSince(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  if (diff < 60_000) return "just now";
  if (diff < 3600_000) return `${Math.floor(diff / 60_000)}m ago`;
  return `${Math.floor(diff / 3600_000)}h ago`;
}

export function MachineCard({ machine }: { machine: Machine }) {
  const color = healthColor(machine);
  const rootVol = machine.disk?.volumes?.find((v) => v.mountPoint === "/");

  const chartData = (machine.history ?? []).slice(-60).map((h) => ({
    t: new Date(h.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
    cpu: Math.round(h.cpu * 1000) / 10,
    ram: Math.round(h.ramUsedGB * 10) / 10,
  }));

  return (
    <div style={{ background: "#1a1a1a", borderRadius: 12, padding: 20, border: `1px solid ${color}33` }}>
      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ width: 10, height: 10, borderRadius: "50%", background: color, display: "inline-block" }} />
          <strong style={{ fontSize: 16 }}>{machine.hostname}</strong>
        </div>
        <span style={{ fontSize: 12, color: "#888" }}>{timeSince(machine.lastSeen)}</span>
      </div>

      {/* Metric Gauges */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12, marginBottom: 16 }}>
        <MetricBox label="CPU" value={`${((machine.cpu?.overall ?? 0) * 100).toFixed(1)}%`} />
        <MetricBox label="RAM" value={`${(machine.ram?.usedGB ?? 0).toFixed(1)} GB`} sub={`swap: ${(machine.ram?.swapUsedMB ?? 0).toFixed(0)} MB`} />
        <MetricBox label="Disk" value={rootVol ? `${(rootVol.totalGB - rootVol.freeGB).toFixed(0)}/${rootVol.totalGB.toFixed(0)} GB` : "—"} />
      </div>

      {/* Chart (DASH-03) */}
      {chartData.length > 2 && (
        <div style={{ height: 120, marginBottom: 16 }}>
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={chartData}>
              <XAxis dataKey="t" tick={{ fontSize: 10, fill: "#666" }} interval="preserveStartEnd" />
              <YAxis tick={{ fontSize: 10, fill: "#666" }} domain={[0, 100]} hide />
              <Tooltip contentStyle={{ background: "#222", border: "none", fontSize: 12 }} />
              <Line type="monotone" dataKey="cpu" stroke="#3b82f6" strokeWidth={1.5} dot={false} name="CPU %" />
              <Line type="monotone" dataKey="ram" stroke="#a855f7" strokeWidth={1.5} dot={false} name="RAM GB" />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Top Processes */}
      <div style={{ fontSize: 12, color: "#999" }}>
        <strong style={{ color: "#ccc" }}>Top CPU:</strong>{" "}
        {(machine.processes?.topCPU ?? []).slice(0, 3).map((p) => `${p.name} ${(p.cpuPercent ?? 0).toFixed(1)}%`).join(", ") || "—"}
      </div>
    </div>
  );
}

function MetricBox({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div style={{ background: "#111", borderRadius: 8, padding: "10px 12px", textAlign: "center" }}>
      <div style={{ fontSize: 11, color: "#888", marginBottom: 4 }}>{label}</div>
      <div style={{ fontSize: 18, fontWeight: 600 }}>{value}</div>
      {sub && <div style={{ fontSize: 10, color: "#666", marginTop: 2 }}>{sub}</div>}
    </div>
  );
}
