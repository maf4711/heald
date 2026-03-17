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
  icloud?: {
    isEnabled: boolean;
    optimizeStorage: boolean;
    localFiles: number;
    cloudFiles: number;
    syncPercent: number;
    directories: number;
    evictedDirs: string[];
    conflicts: number;
    docsSizeGB: number;
    diskFreeGB: number;
    birdRunning: boolean;
  };
  battery?: { cycleCount: number; maxCapacityPercent: number; currentCharge: number; isCharging: boolean; condition: string; temperature: number | null };
  uptime?: { systemSeconds: number; daemonSeconds: number; systemFormatted: string };
  thermal?: string;
  history: { timestamp: string; cpu: number; ramUsedGB: number }[];
}

function healthColor(machine: Machine): string {
  const disk = machine.disk;
  const ram = machine.ram;
  const ic = machine.icloud;
  const pressureLevel = ram?.pressureLevel ?? 0;
  const swapUsedMB = ram?.swapUsedMB ?? 0;

  // Stale: >10 min since last seen
  if (Date.now() - new Date(machine.lastSeen).getTime() > 600_000) return "#666";

  // Red: SMART failing, pressure critical, disk >90%, iCloud sync < 50%, bird down
  if (disk?.smart?.some((s) => s.status === "Failing")) return "#ef4444";
  if (pressureLevel >= 4) return "#ef4444";
  const rootVol = disk?.volumes?.find((v) => v.mountPoint === "/");
  if (rootVol && (rootVol.totalGB - rootVol.freeGB) / rootVol.totalGB > 0.9) return "#ef4444";
  if (ic && ic.isEnabled && ic.syncPercent < 50) return "#ef4444";
  if (ic && ic.isEnabled && !ic.birdRunning) return "#ef4444";

  // Yellow: pressure warning, swap > 2GB, disk >80%, iCloud sync < 90%, conflicts
  if (pressureLevel >= 2) return "#eab308";
  if (swapUsedMB > 2048) return "#eab308";
  if (rootVol && (rootVol.totalGB - rootVol.freeGB) / rootVol.totalGB > 0.8) return "#eab308";
  if (ic && ic.isEnabled && ic.syncPercent < 90) return "#eab308";
  if (ic && ic.conflicts > 0) return "#eab308";
  if (ic && ic.evictedDirs.length > 0) return "#eab308";

  return "#22c55e";
}

function timeSince(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  if (diff < 60_000) return "just now";
  if (diff < 3600_000) return `${Math.floor(diff / 60_000)}m ago`;
  if (diff < 86400_000) return `${Math.floor(diff / 3600_000)}h ago`;
  return `${Math.floor(diff / 86400_000)}d ago`;
}

function syncColor(pct: number): string {
  if (pct >= 99.9) return "#22c55e";
  if (pct >= 90) return "#eab308";
  return "#ef4444";
}

export function MachineCard({ machine }: { machine: Machine }) {
  const color = healthColor(machine);
  const rootVol = machine.disk?.volumes?.find((v) => v.mountPoint === "/");
  const isStale = Date.now() - new Date(machine.lastSeen).getTime() > 600_000;
  const ic = machine.icloud;

  const chartData = (machine.history ?? []).slice(-60).map((h) => ({
    t: new Date(h.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
    cpu: Math.round(h.cpu * 1000) / 10,
    ram: Math.round(h.ramUsedGB * 10) / 10,
  }));

  return (
    <div style={{
      background: "#1a1a1a", borderRadius: 12, padding: 20,
      border: `1px solid ${color}33`,
      opacity: isStale ? 0.6 : 1,
      position: "relative",
    }}>
      {/* Stale Badge */}
      {isStale && (
        <div style={{
          position: "absolute", top: 10, right: 10, background: "#666",
          color: "#fff", fontSize: 10, fontWeight: 700, padding: "2px 8px", borderRadius: 4,
        }}>
          STALE
        </div>
      )}

      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ width: 10, height: 10, borderRadius: "50%", background: color, display: "inline-block" }} />
          <strong style={{ fontSize: 16 }}>{machine.hostname}</strong>
        </div>
        <span style={{ fontSize: 12, color: "#888" }}>
          {timeSince(machine.lastSeen)}
          {machine.uptime?.systemFormatted ? ` / up ${machine.uptime.systemFormatted}` : ""}
        </span>
      </div>

      {/* System Metrics */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 10, marginBottom: 14 }}>
        <MetricBox
          label="CPU"
          value={`${((machine.cpu?.overall ?? 0) * 100).toFixed(0)}%`}
          color={(machine.cpu?.overall ?? 0) > 0.8 ? "#ef4444" : undefined}
        />
        <MetricBox
          label="RAM"
          value={`${(machine.ram?.usedGB ?? 0).toFixed(1)} GB`}
          sub={`swap: ${(machine.ram?.swapUsedMB ?? 0).toFixed(0)} MB`}
          color={(machine.ram?.pressureLevel ?? 0) >= 2 ? "#eab308" : undefined}
        />
        <MetricBox
          label="Disk"
          value={rootVol ? `${(rootVol.totalGB - rootVol.freeGB).toFixed(0)}/${rootVol.totalGB.toFixed(0)} GB` : "—"}
        />
      </div>

      {/* iCloud Section */}
      {ic && (
        <div style={{
          background: "#111", borderRadius: 8, padding: 12, marginBottom: 14,
          border: ic.cloudFiles > 0 || !ic.birdRunning ? "1px solid #ef444433" : ic.conflicts > 0 ? "1px solid #eab30833" : "1px solid #22c55e22",
        }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
            <span style={{ fontSize: 12, fontWeight: 600, color: "#ccc" }}>iCloud Drive</span>
            <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
              {!ic.birdRunning && <Tag text="bird down" color="#ef4444" />}
              {ic.conflicts > 0 && <Tag text={`${ic.conflicts} conflicts`} color="#eab308" />}
              {ic.evictedDirs.length > 0 && <Tag text={`${ic.evictedDirs.length} evicted`} color="#eab308" />}
              {ic.optimizeStorage && <Tag text="optimize on" color="#888" />}
              {!ic.isEnabled && <Tag text="disabled" color="#ef4444" />}
            </div>
          </div>

          {/* Sync Progress Bar */}
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 6 }}>
            <div style={{ flex: 1, height: 16, background: "#222", borderRadius: 8, overflow: "hidden" }}>
              <div style={{
                width: `${ic.syncPercent}%`, height: "100%", borderRadius: 8,
                background: `linear-gradient(90deg, ${syncColor(ic.syncPercent)}88, ${syncColor(ic.syncPercent)})`,
                display: "flex", alignItems: "center", justifyContent: "center",
                fontSize: 10, fontWeight: 700, color: "#fff", minWidth: 30,
              }}>
                {ic.syncPercent.toFixed(0)}%
              </div>
            </div>
          </div>

          {/* Stats Row */}
          <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, color: "#888" }}>
            <span>{ic.localFiles.toLocaleString()} local</span>
            <span>{ic.cloudFiles > 0 ? <span style={{ color: "#ef4444" }}>{ic.cloudFiles} in cloud</span> : "0 cloud"}</span>
            <span>{ic.directories} dirs</span>
            <span>{ic.docsSizeGB.toFixed(0)} GB docs</span>
            <span>{ic.diskFreeGB.toFixed(0)} GB frei</span>
          </div>
        </div>
      )}

      {/* Chart */}
      {chartData.length > 2 && (
        <div style={{ height: 100, marginBottom: 12 }}>
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={chartData}>
              <XAxis dataKey="t" tick={{ fontSize: 9, fill: "#555" }} interval="preserveStartEnd" />
              <YAxis tick={false} domain={[0, 100]} hide />
              <Tooltip contentStyle={{ background: "#222", border: "none", fontSize: 12, borderRadius: 6 }} />
              <Line type="monotone" dataKey="cpu" stroke="#3b82f6" strokeWidth={1.5} dot={false} name="CPU %" />
              <Line type="monotone" dataKey="ram" stroke="#a855f7" strokeWidth={1.5} dot={false} name="RAM GB" />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Footer: Processes + Thermal */}
      <div style={{ fontSize: 11, color: "#888", display: "flex", justifyContent: "space-between", gap: 8 }}>
        <span>
          <strong style={{ color: "#999" }}>Top:</strong>{" "}
          {(machine.processes?.topCPU ?? []).slice(0, 3).map((p) => `${p.name} ${(p.cpuPercent ?? 0).toFixed(0)}%`).join(", ") || "—"}
        </span>
        {machine.thermal && machine.thermal !== "nominal" && (
          <span style={{ color: "#ef4444" }}>thermal: {machine.thermal}</span>
        )}
        {machine.battery && (
          <span>{machine.battery.currentCharge}% {machine.battery.isCharging ? "charging" : "battery"}</span>
        )}
      </div>
    </div>
  );
}

function MetricBox({ label, value, sub, color }: { label: string; value: string; sub?: string; color?: string }) {
  return (
    <div style={{ background: "#111", borderRadius: 8, padding: "8px 10px", textAlign: "center" }}>
      <div style={{ fontSize: 10, color: "#777", marginBottom: 3 }}>{label}</div>
      <div style={{ fontSize: 18, fontWeight: 600, color: color ?? "#eee" }}>{value}</div>
      {sub && <div style={{ fontSize: 10, color: "#555", marginTop: 1 }}>{sub}</div>}
    </div>
  );
}

function Tag({ text, color }: { text: string; color: string }) {
  return (
    <span style={{
      fontSize: 9, fontWeight: 700, padding: "1px 6px", borderRadius: 4,
      background: `${color}22`, color, border: `1px solid ${color}44`,
    }}>
      {text}
    </span>
  );
}
