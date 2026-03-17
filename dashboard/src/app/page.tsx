"use client";

import { useEffect, useState, useMemo, useCallback } from "react";
import { MachineCard } from "@/components/MachineCard";
import { ActivityFeed } from "@/components/ActivityFeed";
import { FleetBar } from "@/components/FleetBar";
import { InstallHero } from "@/components/InstallHero";

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
    { key: "sync", label: "iCloud Sync" },
    { key: "lastSeen", label: "Zuletzt gesehen" },
    { key: "issues", label: "Probleme" },
  ];

  return (
    <div style={{ maxWidth: 1400, margin: "0 auto", padding: "24px 16px" }}>
      <header style={{ marginBottom: 24, display: "flex", alignItems: "center", gap: 12 }}>
        <h1 style={{ fontSize: 28, fontWeight: 700, margin: 0 }}>heald</h1>
        <span style={{ fontSize: 14, color: "#888" }}>
          {machines.length} machine{machines.length !== 1 ? "s" : ""} connected
        </span>
        <span style={{ marginLeft: "auto", fontSize: 11, color: "#555" }}>auto-refresh 5s</span>
      </header>

      <FleetBar machines={machines} />

      {loading ? (
        <div style={{ textAlign: "center", padding: 64, color: "#666" }}>
          <div style={{ fontSize: 20, marginBottom: 8 }}>Connecting to fleet...</div>
          <div style={{ fontSize: 13 }}>Waiting for daemon metrics (auto-refresh every 5s)</div>
        </div>
      ) : machines.length === 0 ? (
        <InstallHero />
      ) : (
        <>
          {/* Search + Sort */}
          <div style={{ display: "flex", gap: 12, marginBottom: 16, flexWrap: "wrap", alignItems: "center" }}>
            <input
              type="text"
              placeholder="Maschine suchen..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{
                padding: "8px 14px", background: "#1a1a1a", border: "1px solid #333",
                borderRadius: 8, color: "#eee", fontSize: 14, flex: 1, minWidth: 200, outline: "none",
              }}
            />
            <div style={{ display: "flex", gap: 4 }}>
              {sortBtns.map((b) => (
                <button
                  key={b.key}
                  onClick={() => setSort(b.key)}
                  style={{
                    padding: "5px 12px", borderRadius: 16, border: "1px solid #333", cursor: "pointer",
                    fontSize: 12, transition: "all .2s",
                    background: sort === b.key ? "#2563eb" : "#222",
                    color: sort === b.key ? "#fff" : "#888",
                    borderColor: sort === b.key ? "#2563eb" : "#333",
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
            <p style={{ textAlign: "center", color: "#666", padding: 32 }}>Keine Maschine gefunden.</p>
          )}
        </>
      )}

      <section style={{ marginTop: 40 }}>
        <h2 style={{ fontSize: 20, fontWeight: 600, marginBottom: 16 }}>Activity Feed</h2>
        <ActivityFeed events={events} />
      </section>

      {/* Install footer */}
      <footer style={{
        marginTop: 48, padding: "24px 0", borderTop: "1px solid #222",
        textAlign: "center", color: "#555", fontSize: 12,
      }}>
        <span style={{ color: "#888" }}>Add more Macs: </span>
        <code style={{
          background: "#1a1a1a", padding: "4px 10px", borderRadius: 6,
          border: "1px solid #333", fontSize: 12, color: "#22c55e",
        }}>
          brew install maf4711/heald/heald
        </code>
        <span style={{ margin: "0 8px", color: "#333" }}>|</span>
        <a href="https://github.com/maf4711/heald" target="_blank" rel="noopener" style={{ color: "#3b82f6", textDecoration: "none" }}>
          GitHub
        </a>
        <span style={{ margin: "0 8px", color: "#333" }}>|</span>
        <span>heald v1.3.0</span>
      </footer>
    </div>
  );
}
