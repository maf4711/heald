"use client";

import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer } from "recharts";

/* ── heald tokens ── */
const t = {
  bg: "#050508",
  surface: "#0a0a0f",
  surfaceRaised: "#111118",
  border: "rgba(255, 255, 255, 0.04)",
  text1: "rgba(255, 255, 255, 0.88)",
  text2: "rgba(255, 255, 255, 0.45)",
  text3: "rgba(255, 255, 255, 0.2)",
  brand300: "#7dd3fc",
  brand400: "#38bdf8",
  brand500: "#0ea5e9",
  success: "#34d399",
  warning: "#f5a623",
  error: "#ef4444",
  info: "#3b82f6",
};

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
    isEnabled: boolean; optimizeStorage: boolean; localFiles: number; cloudFiles: number;
    syncPercent: number; directories: number; evictedDirs: string[]; conflicts: number;
    docsSizeGB: number; diskFreeGB: number; birdRunning: boolean;
  };
  battery?: { cycleCount: number; maxCapacityPercent: number; currentCharge: number; isCharging: boolean; condition: string; temperature: number | null };
  uptime?: { systemSeconds: number; daemonSeconds: number; systemFormatted: string };
  thermal?: string;
  history: { timestamp: string; cpu: number; ramUsedGB: number }[];
}

function healthColor(m: Machine): string {
  const ic = m.icloud;
  const pr = m.ram?.pressureLevel ?? 0;
  if (Date.now() - new Date(m.lastSeen).getTime() > 600_000) return t.text3;
  if (m.disk?.smart?.some((s) => s.status === "Failing")) return t.error;
  if (pr >= 4) return t.error;
  if (ic?.isEnabled && !ic.birdRunning) return t.error;
  if (ic?.isEnabled && ic.syncPercent < 50) return t.error;
  if (pr >= 2) return t.warning;
  if (ic?.syncPercent !== undefined && ic.syncPercent < 90) return t.warning;
  if (ic && ic.conflicts > 0) return t.warning;
  if (ic && ic.evictedDirs.length > 0) return t.warning;
  return t.success;
}

function ago(iso: string): string {
  const d = Date.now() - new Date(iso).getTime();
  if (d < 60_000) return "now";
  if (d < 3600_000) return `${Math.floor(d / 60_000)}m`;
  if (d < 86400_000) return `${Math.floor(d / 3600_000)}h`;
  return `${Math.floor(d / 86400_000)}d`;
}

function syncGradient(pct: number): string {
  if (pct >= 99.9) return `linear-gradient(90deg, ${t.success}88, ${t.success})`;
  if (pct >= 90) return `linear-gradient(90deg, ${t.warning}88, ${t.warning})`;
  return `linear-gradient(90deg, ${t.error}88, ${t.error})`;
}

export function MachineCard({ machine: m }: { machine: Machine }) {
  const color = healthColor(m);
  const rootVol = m.disk?.volumes?.find((v) => v.mountPoint === "/");
  const isStale = Date.now() - new Date(m.lastSeen).getTime() > 600_000;
  const ic = m.icloud;

  const chartData = (m.history ?? []).slice(-60).map((h) => ({
    t: new Date(h.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
    cpu: Math.round(h.cpu * 1000) / 10,
    ram: Math.round(h.ramUsedGB * 10) / 10,
  }));

  return (
    <div style={{
      background: t.surface, borderRadius: 12, padding: 20,
      border: `1px solid ${color}22`,
      opacity: isStale ? 0.5 : 1,
      position: "relative",
      transition: "border-color 300ms cubic-bezier(0.25, 1, 0.5, 1)",
    }}>
      {isStale && (
        <div style={{
          position: "absolute", top: 10, right: 10, background: t.text3,
          color: t.bg, fontSize: 10, fontWeight: 600, padding: "1px 6px", borderRadius: 4,
          letterSpacing: "0.08em",
        }}>STALE</div>
      )}

      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 14 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ width: 8, height: 8, borderRadius: "50%", background: color }} />
          <strong style={{ fontSize: 15, fontWeight: 500, letterSpacing: "-0.01em" }}>{m.hostname}</strong>
        </div>
        <span style={{ fontSize: 11, color: t.text3 }}>
          {ago(m.lastSeen)}
          {m.uptime?.systemFormatted ? ` \u00B7 up ${m.uptime.systemFormatted}` : ""}
        </span>
      </div>

      {/* Gauges */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8, marginBottom: 12 }}>
        <Gauge label="CPU" value={`${((m.cpu?.overall ?? 0) * 100).toFixed(0)}%`}
          accent={(m.cpu?.overall ?? 0) > 0.8 ? t.error : undefined} />
        <Gauge label="RAM" value={`${(m.ram?.usedGB ?? 0).toFixed(1)}G`}
          sub={m.ram?.swapUsedMB && m.ram.swapUsedMB > 0 ? `swap ${m.ram.swapUsedMB.toFixed(0)}M` : undefined}
          accent={(m.ram?.pressureLevel ?? 0) >= 2 ? t.warning : undefined} />
        <Gauge label="Disk"
          value={rootVol ? `${(rootVol.totalGB - rootVol.freeGB).toFixed(0)}/${rootVol.totalGB.toFixed(0)}G` : "\u2014"} />
      </div>

      {/* iCloud */}
      {ic && (
        <div style={{
          background: t.surfaceRaised, borderRadius: 8, padding: 10, marginBottom: 12,
          border: `1px solid ${!ic.birdRunning || ic.cloudFiles > 0 ? t.error + "22" : ic.conflicts > 0 ? t.warning + "22" : t.border}`,
        }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 6 }}>
            <span style={{ fontSize: 11, fontWeight: 500, color: t.text2, letterSpacing: "0.02em" }}>iCloud Drive</span>
            <div style={{ display: "flex", gap: 4 }}>
              {!ic.birdRunning && <Tag text="bird down" color={t.error} />}
              {ic.conflicts > 0 && <Tag text={`${ic.conflicts} conflicts`} color={t.warning} />}
              {ic.evictedDirs.length > 0 && <Tag text={`${ic.evictedDirs.length} evicted`} color={t.warning} />}
              {ic.optimizeStorage && <Tag text="optimize" color={t.text3} />}
              {!ic.isEnabled && <Tag text="disabled" color={t.error} />}
            </div>
          </div>

          {/* Sync bar */}
          <div style={{ height: 14, background: "#1a1a24", borderRadius: 7, overflow: "hidden", marginBottom: 6 }}>
            <div style={{
              width: `${Math.max(ic.syncPercent, 2)}%`, height: "100%", borderRadius: 7,
              background: syncGradient(ic.syncPercent),
              display: "flex", alignItems: "center", justifyContent: "center",
              fontSize: 9, fontWeight: 600, color: "#fff", minWidth: 28,
              transition: "width 500ms cubic-bezier(0.25, 1, 0.5, 1)",
            }}>
              {ic.syncPercent.toFixed(0)}%
            </div>
          </div>

          <div style={{ display: "flex", justifyContent: "space-between", fontSize: 10, color: t.text3 }}>
            <span>{ic.localFiles.toLocaleString()} local</span>
            {ic.cloudFiles > 0 ? <span style={{ color: t.error }}>{ic.cloudFiles} cloud</span> : <span>0 cloud</span>}
            <span>{ic.directories} dirs</span>
            <span>{ic.docsSizeGB.toFixed(0)}G docs</span>
            <span>{ic.diskFreeGB.toFixed(0)}G free</span>
          </div>
        </div>
      )}

      {/* Chart */}
      {chartData.length > 2 && (
        <div style={{ height: 80, marginBottom: 10 }}>
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={chartData}>
              <XAxis dataKey="t" tick={{ fontSize: 9, fill: t.text3 }} interval="preserveStartEnd" />
              <YAxis tick={false} domain={[0, 100]} hide />
              <Tooltip contentStyle={{ background: t.surfaceRaised, border: `1px solid ${t.border}`, fontSize: 11, borderRadius: 8 }} />
              <Line type="monotone" dataKey="cpu" stroke={t.brand400} strokeWidth={1.5} dot={false} name="CPU %" />
              <Line type="monotone" dataKey="ram" stroke={t.brand300} strokeWidth={1} dot={false} name="RAM GB" />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Footer */}
      <div style={{ fontSize: 10, color: t.text3, display: "flex", justifyContent: "space-between" }}>
        <span>
          {(m.processes?.topCPU ?? []).slice(0, 3).map((p) => `${p.name} ${(p.cpuPercent ?? 0).toFixed(0)}%`).join(", ") || "\u2014"}
        </span>
        <span>
          {m.thermal && m.thermal !== "nominal" && <span style={{ color: t.error }}>{m.thermal}</span>}
          {m.battery && <span>{m.battery.currentCharge}% {m.battery.isCharging ? "\u26A1" : "\u{1F50B}"}</span>}
        </span>
      </div>
    </div>
  );
}

function Gauge({ label, value, sub, accent }: { label: string; value: string; sub?: string; accent?: string }) {
  return (
    <div style={{ background: "#111118", borderRadius: 8, padding: "7px 10px", textAlign: "center" }}>
      <div style={{ fontSize: 10, color: t.text3, marginBottom: 2, fontWeight: 500, letterSpacing: "0.02em" }}>{label}</div>
      <div style={{ fontSize: 17, fontWeight: 500, color: accent ?? t.text1, letterSpacing: "-0.02em" }}>{value}</div>
      {sub && <div style={{ fontSize: 9, color: t.text3, marginTop: 1 }}>{sub}</div>}
    </div>
  );
}

function Tag({ text, color }: { text: string; color: string }) {
  return (
    <span style={{
      fontSize: 9, fontWeight: 600, padding: "1px 5px", borderRadius: 4,
      background: `${color}12`, color, border: `1px solid ${color}28`,
      letterSpacing: "0.02em",
    }}>
      {text}
    </span>
  );
}
