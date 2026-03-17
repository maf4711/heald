"use client";

interface Event {
  timestamp: string;
  machineId: string;
  type: string;
  summary: string;
  aiGenerated: boolean;
}

const typeColors: Record<string, string> = {
  process_killed: "#ef4444",
  process_restarted: "#eab308",
  dns_flushed: "#3b82f6",
  swap_spike: "#f97316",
  smart_failure: "#ef4444",
  crash_detected: "#ef4444",
  healing_success: "#22c55e",
  healing_failed: "#ef4444",
  healing_attempt: "#a855f7",
  daemon_started: "#22c55e",
  daemon_stopped: "#888",
  icloud_sync_degraded: "#eab308",
  icloud_daemon_down: "#ef4444",
  spotlight_fix: "#3b82f6",
  retention_purge: "#555",
  maintenance_started: "#a855f7",
  maintenance_completed: "#22c55e",
};

export function ActivityFeed({ events }: { events: Event[] }) {
  if (events.length === 0) {
    return <p style={{ color: "#666", fontSize: 14 }}>No activity yet.</p>;
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
      {events.map((event, i) => {
        const color = typeColors[event.type] ?? "#888";
        const time = new Date(event.timestamp).toLocaleString([], {
          month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit",
        });

        return (
          <div key={i} style={{ display: "flex", alignItems: "center", gap: 10, padding: "8px 12px", background: "#1a1a1a", borderRadius: 8, fontSize: 13 }}>
            <span style={{ width: 8, height: 8, borderRadius: "50%", background: color, flexShrink: 0 }} />
            <span style={{ color: "#666", minWidth: 140, fontSize: 11 }}>{time}</span>
            <span style={{ flex: 1 }}>{event.summary}</span>
            {/* DASH-05: AI badge */}
            {event.aiGenerated && (
              <span style={{
                background: "#7c3aed", color: "#fff", fontSize: 10, fontWeight: 700,
                padding: "2px 6px", borderRadius: 4, flexShrink: 0,
              }}>
                AI
              </span>
            )}
            <span style={{ color: "#555", fontSize: 11 }}>{event.machineId.slice(0, 8)}</span>
          </div>
        );
      })}
    </div>
  );
}
