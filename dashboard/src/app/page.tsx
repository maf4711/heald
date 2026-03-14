"use client";

import { useEffect, useState } from "react";
import { MachineCard } from "@/components/MachineCard";
import { ActivityFeed } from "@/components/ActivityFeed";

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

interface Event {
  timestamp: string;
  machineId: string;
  type: string;
  summary: string;
  aiGenerated: boolean;
}

export default function Dashboard() {
  const [machines, setMachines] = useState<Machine[]>([]);
  const [events, setEvents] = useState<Event[]>([]);

  useEffect(() => {
    const fetchData = async () => {
      try {
        const [mRes, eRes] = await Promise.all([fetch("/api/machines"), fetch("/api/events")]);
        if (mRes.ok) {
          const mData = await mRes.json();
          setMachines(mData.machines);
        }
        if (eRes.ok) {
          const eData = await eRes.json();
          setEvents(eData.events);
        }
      } catch { /* retry next cycle */ }
    };

    fetchData();
    const interval = setInterval(fetchData, 5000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div style={{ maxWidth: 1200, margin: "0 auto", padding: "24px 16px" }}>
      <header style={{ marginBottom: 32, display: "flex", alignItems: "center", gap: 12 }}>
        <h1 style={{ fontSize: 28, fontWeight: 700, margin: 0 }}>heald</h1>
        <span style={{ fontSize: 14, color: "#888" }}>
          {machines.length} machine{machines.length !== 1 ? "s" : ""} connected
        </span>
      </header>

      {machines.length === 0 ? (
        <div style={{ textAlign: "center", padding: 64, color: "#666" }}>
          <p style={{ fontSize: 18 }}>No machines connected yet.</p>
          <p style={{ fontSize: 14 }}>Start the heald daemon on a Mac to see live metrics here.</p>
        </div>
      ) : (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(540, 1fr))", gap: 16 }}>
          {machines.map((m) => (
            <MachineCard key={m.machineId} machine={m} />
          ))}
        </div>
      )}

      <section style={{ marginTop: 40 }}>
        <h2 style={{ fontSize: 20, fontWeight: 600, marginBottom: 16 }}>Activity Feed</h2>
        <ActivityFeed events={events} />
      </section>
    </div>
  );
}
