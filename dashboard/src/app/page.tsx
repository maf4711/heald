"use client";

import { useEffect, useState, useMemo } from "react";
import { MachineCard } from "@/components/MachineCard";
import { ActivityFeed } from "@/components/ActivityFeed";
import { FleetBar } from "@/components/FleetBar";
import { InstallPanel } from "@/components/InstallPanel";

/* ── meradOS tokens ── */
const t = {
  bg: "#050508",
  surface: "#0a0a0f",
  border: "rgba(255, 255, 255, 0.04)",
  text1: "rgba(255, 255, 255, 0.88)",
  text2: "rgba(255, 255, 255, 0.45)",
  text3: "rgba(255, 255, 255, 0.2)",
  brand400: "#38bdf8",
  brand500: "#0ea5e9",
  success: "#34d399",
  warning: "#f5a623",
  error: "#ef4444",
  radius: "12px",
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

interface Event {
  timestamp: string;
  machineId: string;
  type: string;
  summary: string;
  aiGenerated: boolean;
}

type SortKey = "name" | "cpu" | "sync" | "lastSeen" | "issues";

export default function Dashboard() {
  const [machines, setMachines] = useState<Machine[]>([]);
  const [events, setEvents] = useState<Event[]>([]);
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState<SortKey>("name");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchData = async () => {
      try {
        const [mRes, eRes] = await Promise.all([fetch("/api/machines"), fetch("/api/events")]);
        if (mRes.ok) { setMachines((await mRes.json()).machines); setLoading(false); }
        if (eRes.ok) setEvents((await eRes.json()).events);
      } catch { /* retry next cycle */ }
    };
    fetchData();
    const interval = setInterval(fetchData, 5000);
    return () => clearInterval(interval);
  }, []);

  const filtered = useMemo(() => {
    const q = search.toLowerCase();
    let list = machines;
    if (q) list = list.filter((m) => m.hostname.toLowerCase().includes(q) || m.machineId.toLowerCase().includes(q));
    list = [...list].sort((a, b) => {
      switch (sort) {
        case "cpu": return (b.cpu?.overall ?? 0) - (a.cpu?.overall ?? 0);
        case "sync": return (a.icloud?.syncPercent ?? 100) - (b.icloud?.syncPercent ?? 100);
        case "lastSeen": return new Date(a.lastSeen).getTime() - new Date(b.lastSeen).getTime();
        case "issues": {
          const ai = (a.icloud?.cloudFiles ?? 0) + (a.icloud?.conflicts ?? 0) + (a.icloud?.evictedDirs?.length ?? 0);
          const bi = (b.icloud?.cloudFiles ?? 0) + (b.icloud?.conflicts ?? 0) + (b.icloud?.evictedDirs?.length ?? 0);
          return bi - ai;
        }
        default: return a.hostname.localeCompare(b.hostname);
      }
    });
    return list;
  }, [machines, search, sort]);

  const sortBtns: { key: SortKey; label: string }[] = [
    { key: "name", label: "Name" },
    { key: "cpu", label: "CPU" },
    { key: "sync", label: "iCloud" },
    { key: "lastSeen", label: "Last Seen" },
    { key: "issues", label: "Issues" },
  ];

  return (
    <div style={{ maxWidth: 1400, margin: "0 auto", padding: "24px 16px" }}>
      {/* Header */}
      <header style={{ marginBottom: 24, display: "flex", alignItems: "center", gap: 12 }}>
        <h1 style={{
          fontSize: 28, fontWeight: 200, margin: 0, letterSpacing: "0.02em",
          fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro', Inter, sans-serif",
        }}>
          heald
        </h1>
        <span style={{ fontSize: 13, color: t.text2 }}>
          {machines.length} machine{machines.length !== 1 ? "s" : ""}
        </span>
        <span style={{ marginLeft: "auto", fontSize: 11, color: t.text3 }}>auto-refresh 5s</span>
      </header>

      {/* Install Panel (collapsible) */}
      <InstallPanel />

      <FleetBar machines={machines} />

      {loading ? (
        <div style={{ textAlign: "center", padding: 64, color: t.text2 }}>
          <div style={{ fontSize: 18, fontWeight: 500, letterSpacing: "-0.01em", marginBottom: 8 }}>Connecting to fleet...</div>
          <div style={{ fontSize: 13, color: t.text3 }}>Waiting for daemon metrics</div>
        </div>
      ) : machines.length === 0 ? (
        <div style={{ textAlign: "center", padding: 64, color: t.text2 }}>
          <div style={{ fontSize: 18, fontWeight: 500, marginBottom: 8 }}>No machines connected yet.</div>
          <div style={{ fontSize: 13, color: t.text3 }}>Open the install panel above to get started.</div>
        </div>
      ) : (
        <>
          {/* Search + Sort */}
          <div style={{ display: "flex", gap: 12, marginBottom: 16, flexWrap: "wrap", alignItems: "center" }}>
            <input
              type="text"
              placeholder="Search machines..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{
                padding: "8px 14px", background: t.surface, border: `1px solid ${t.border}`,
                borderRadius: 8, color: t.text1, fontSize: 14, flex: 1, minWidth: 200, outline: "none",
                transition: "border-color 200ms cubic-bezier(0.25, 1, 0.5, 1)",
              }}
              onFocus={(e) => (e.target.style.borderColor = t.brand400 + "44")}
              onBlur={(e) => (e.target.style.borderColor = t.border)}
            />
            <div style={{ display: "flex", gap: 4 }}>
              {sortBtns.map((b) => (
                <button
                  key={b.key}
                  onClick={() => setSort(b.key)}
                  style={{
                    padding: "5px 12px", borderRadius: 16, cursor: "pointer",
                    fontSize: 12, fontWeight: 500, letterSpacing: "0.02em",
                    transition: "all 200ms cubic-bezier(0.25, 1, 0.5, 1)",
                    background: sort === b.key ? t.brand400 + "18" : t.surface,
                    color: sort === b.key ? t.brand400 : t.text2,
                    border: `1px solid ${sort === b.key ? t.brand400 + "33" : t.border}`,
                  }}
                >
                  {b.label}
                </button>
              ))}
            </div>
          </div>

          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(480px, 1fr))", gap: 16 }}>
            {filtered.map((m) => (
              <MachineCard key={m.machineId} machine={m} />
            ))}
          </div>
          {filtered.length === 0 && search && (
            <p style={{ textAlign: "center", color: t.text3, padding: 32 }}>No machines match.</p>
          )}
        </>
      )}

      <section style={{ marginTop: 40 }}>
        <h2 style={{ fontSize: 18, fontWeight: 500, letterSpacing: "-0.01em", marginBottom: 16, color: t.text1 }}>Activity</h2>
        <ActivityFeed events={events} />
      </section>

      {/* Footer */}
      <footer style={{
        marginTop: 48, padding: "20px 0", borderTop: `1px solid ${t.border}`,
        textAlign: "center", color: t.text3, fontSize: 11,
      }}>
        <a href="https://github.com/maf4711/heald" target="_blank" rel="noopener"
          style={{ color: t.brand500, textDecoration: "none" }}>GitHub</a>
        <span style={{ margin: "0 12px", color: t.border }}>|</span>
        <span>heald v1.3.0</span>
        <span style={{ margin: "0 12px", color: t.border }}>|</span>
        <span style={{ color: t.text3 }}>meradOS</span>
      </footer>
    </div>
  );
}
