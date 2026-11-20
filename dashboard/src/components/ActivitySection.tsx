"use client";

import { ActivityFeed } from "@/components/ActivityFeed";
import { t } from "@/lib/theme";
import { usePolled } from "@/components/usePolled";

interface Event {
  timestamp: string;
  machineId: string;
  type: string;
  summary: string;
  aiGenerated: boolean;
}

// "Activity" section: polls GET /api/events (last 100) every 5 s.
export function ActivitySection() {
  const events = usePolled<Event>("/api/events?limit=100", "events", 5000);

  return (
    <section style={{ marginTop: 36 }}>
      <h2
        style={{
          fontSize: 16,
          fontWeight: 500,
          marginBottom: 12,
          color: t.text1,
          display: "flex",
          alignItems: "center",
          gap: 8,
        }}
      >
        Activity
        <span style={{ fontSize: 12, color: t.text3, fontWeight: 400 }}>
          last {events.length} events
        </span>
      </h2>
      <ActivityFeed events={events} />
    </section>
  );
}
