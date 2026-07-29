"use client";

const t = {
  surface: "#0a0a0f",
  border: "rgba(255, 255, 255, 0.04)",
  text2: "rgba(255, 255, 255, 0.45)",
  text3: "rgba(255, 255, 255, 0.2)",
  success: "#34d399",
  warning: "#f5a623",
  error: "#ef4444",
  info: "#3b82f6",
  brand400: "#38bdf8",
};

interface Event {
  timestamp: string;
  machineId: string;
  type: string;
  summary: string;
  aiGenerated: boolean;
}

const typeColors: Record<string, string> = {
  process_killed: t.error,
  process_restarted: t.warning,
  dns_flushed: t.info,
  swap_spike: t.warning,
  smart_failure: t.error,
  crash_detected: t.error,
  system_fault: t.error,
  self_healed: t.success,
  healing_success: t.success,
  healing_failed: t.error,
  healing_attempt: t.brand400,
  daemon_started: t.success,
  daemon_stopped: t.text3,
  icloud_sync_degraded: t.warning,
  icloud_daemon_down: t.error,
  spotlight_stuck: t.warning,
  spotlight_fix: t.info,
  retention_purge: t.text3,
  maintenance_started: t.brand400,
  maintenance_completed: t.success,
};

export function ActivityFeed({ events }: { events: Event[] }) {
  if (events.length === 0) {
    return <p style={{ color: t.text3, fontSize: 13 }}>No activity yet.</p>;
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
      {events.map((event, i) => {
        const color = typeColors[event.type] ?? t.text3;
        const time = new Date(event.timestamp).toLocaleString([], {
          month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit",
        });

        return (
          <div key={i} style={{
            display: "flex", alignItems: "center", gap: 10,
            padding: "7px 12px", background: t.surface, borderRadius: 8,
            fontSize: 12, border: `1px solid ${t.border}`,
            transition: "border-color 200ms",
          }}>
            <span style={{ width: 6, height: 6, borderRadius: "50%", background: color, flexShrink: 0 }} />
            <span style={{ color: t.text3, minWidth: 130, fontSize: 10, fontFamily: "'SF Mono', monospace" }}>{time}</span>
            <span style={{ flex: 1, color: t.text2 }}>{event.summary}</span>
            {event.aiGenerated && (
              <span style={{
                background: t.brand400 + "18", color: t.brand400, fontSize: 9, fontWeight: 600,
                padding: "1px 5px", borderRadius: 4, flexShrink: 0, letterSpacing: "0.04em",
              }}>
                AI
              </span>
            )}
            <span style={{ color: t.text3, fontSize: 10, fontFamily: "'SF Mono', monospace" }}>
              {event.machineId.slice(0, 10)}
            </span>
          </div>
        );
      })}
    </div>
  );
}
