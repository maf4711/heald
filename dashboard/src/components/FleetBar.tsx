"use client";

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
  const staleThreshold = 10 * 60_000; // 10 min
  const now = Date.now();

  let online = 0, stale = 0;
  let icloudOk = 0, icloudDegraded = 0, icloudNoData = 0;
  let totalCloud = 0, totalConflicts = 0, birdDown = 0;
  let avgCpu = 0;

  for (const m of machines) {
    const age = now - new Date(m.lastSeen).getTime();
    if (age < staleThreshold) online++; else stale++;
    avgCpu += m.cpu?.overall ?? 0;

    const ic = m.icloud;
    if (!ic) { icloudNoData++; continue; }
    if (ic.syncPercent >= 99.9) icloudOk++;
    else icloudDegraded++;
    totalCloud += ic.cloudFiles;
    totalConflicts += ic.conflicts;
    if (!ic.birdRunning) birdDown++;
  }
  avgCpu = total > 0 ? avgCpu / total : 0;

  const stats: { label: string; value: string | number; color?: string }[] = [
    { label: "Maschinen", value: total },
    { label: "Online", value: online, color: online === total ? "#22c55e" : "#eab308" },
    { label: "Veraltet", value: stale, color: stale > 0 ? "#ef4444" : "#22c55e" },
    { label: "CPU (avg)", value: `${(avgCpu * 100).toFixed(0)}%` },
    { label: "iCloud OK", value: icloudOk, color: "#22c55e" },
    { label: "iCloud Sync", value: icloudDegraded, color: icloudDegraded > 0 ? "#eab308" : "#22c55e" },
    { label: "Cloud Files", value: totalCloud, color: totalCloud > 0 ? "#ef4444" : "#22c55e" },
    { label: "Konflikte", value: totalConflicts, color: totalConflicts > 0 ? "#ef4444" : "#22c55e" },
    { label: "bird Down", value: birdDown, color: birdDown > 0 ? "#ef4444" : "#22c55e" },
  ];

  return (
    <div style={{ display: "flex", gap: 8, marginBottom: 24, flexWrap: "wrap" }}>
      {stats.map((s) => (
        <div
          key={s.label}
          style={{
            background: "#1a1a1a", border: "1px solid #333", borderRadius: 10,
            padding: "10px 16px", textAlign: "center", flex: "1 1 100px", minWidth: 90,
          }}
        >
          <div style={{ fontSize: 22, fontWeight: 700, color: s.color ?? "#eee", lineHeight: 1.2 }}>
            {s.value}
          </div>
          <div style={{ fontSize: 11, color: "#888", marginTop: 2 }}>{s.label}</div>
        </div>
      ))}
    </div>
  );
}
