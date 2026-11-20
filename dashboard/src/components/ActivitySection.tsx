"use client";

import { useEffect, useState } from "react";
import { ActivityFeed } from "@/components/ActivityFeed";
import { t } from "@/lib/theme";

interface Event {
  timestamp: string;
  machineId: string;
  type: string;
  summary: string;
  aiGenerated: boolean;
}

// "Activity" section: polls GET /api/events (last 100) every 5 s.
export function ActivitySection() {
  const [events, setEvents] = useState<Event[]>([]);

  useEffect(() => {
    const load = async () => {
      try {
        const res = await fetch("/api/events?limit=100", { cache: "no-store" });
        if (res.ok) setEvents((await res.json()).events ?? []);
      } catch {
        /* retry */
      }
    };
    load();
    const interval = setInterval(load, 5000);
    return () => clearInterval(interval);
  }, []);

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
