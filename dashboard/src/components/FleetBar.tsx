"use client";

const t = {
  surface: "#0a0a0f",
  border: "rgba(255, 255, 255, 0.04)",
  text1: "rgba(255, 255, 255, 0.88)",
  text2: "rgba(255, 255, 255, 0.45)",
  brand400: "#38bdf8",
  success: "#34d399",
  warning: "#f5a623",
  error: "#ef4444",
};

interface Machine {
  hostname: string;
  lastSeen: string;
  cpu?: { overall: number };
  ram?: { pressureLevel: number };
  icloud?: {
    syncPercent: number;
    cloudFiles: number;
    conflicts: number;
    evictedDirs: string[];
    birdRunning: boolean;
  };
}

export function FleetBar({ machines }: { machines: Machine[] }) {
  if (machines.length === 0) return null;

  const total = machines.length;
  const now = Date.now();
  const staleMs = 10 * 60_000;

  let online = 0, stale = 0, avgCpu = 0;
  let icOk = 0, icBad = 0, cloudTotal = 0, conflictsTotal = 0, birdDown = 0;

  for (const m of machines) {
    const age = now - new Date(m.lastSeen).getTime();
    if (age < staleMs) online++; else stale++;
    avgCpu += m.cpu?.overall ?? 0;
    const ic = m.icloud;
    if (!ic) continue;
    if (ic.syncPercent >= 99.9) icOk++; else icBad++;
    cloudTotal += ic.cloudFiles;
    conflictsTotal += ic.conflicts;
    if (!ic.birdRunning) birdDown++;
  }
  avgCpu = total > 0 ? avgCpu / total * 100 : 0;

  const stats: { label: string; value: string | number; color?: string }[] = [
    { label: "Machines", value: total },
    { label: "Online", value: online, color: online === total ? t.success : t.warning },
    ...(stale > 0 ? [{ label: "Stale", value: stale, color: t.error }] : []),
    { label: "CPU avg", value: `${avgCpu.toFixed(0)}%`, color: avgCpu > 80 ? t.error : avgCpu > 60 ? t.warning : undefined },
    { label: "iCloud OK", value: icOk, color: t.success },
    ...(icBad > 0 ? [{ label: "Sync Issues", value: icBad, color: t.warning }] : []),
    ...(cloudTotal > 0 ? [{ label: "Cloud Files", value: cloudTotal, color: t.error }] : []),
    ...(conflictsTotal > 0 ? [{ label: "Conflicts", value: conflictsTotal, color: t.error }] : []),
    ...(birdDown > 0 ? [{ label: "bird Down", value: birdDown, color: t.error }] : []),
  ];

  return (
    <div style={{ display: "flex", gap: 8, marginBottom: 20, flexWrap: "wrap" }}>
      {stats.map((s) => (
        <div
          key={s.label}
          style={{
            background: t.surface, border: `1px solid ${t.border}`, borderRadius: 12,
            padding: "10px 16px", textAlign: "center", flex: "1 1 90px", minWidth: 80,
            transition: "border-color 200ms cubic-bezier(0.25, 1, 0.5, 1)",
          }}
        >
          <div style={{ fontSize: 20, fontWeight: 500, color: s.color ?? t.text1, lineHeight: 1.2, letterSpacing: "-0.02em" }}>
            {s.value}
          </div>
          <div style={{ fontSize: 11, color: t.text2, marginTop: 2, fontWeight: 500, letterSpacing: "0.02em" }}>{s.label}</div>
        </div>
      ))}
    </div>
  );
}
