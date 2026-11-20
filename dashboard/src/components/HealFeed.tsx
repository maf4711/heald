"use client";

import { t } from "@/lib/theme";
import { usePolled } from "@/components/usePolled";
import type { HealOutcome, HealReport } from "@/lib/heal-report";

type MachineName = { machineId: string; hostname: string };

const outcomeColors: Record<HealOutcome, string> = {
  executed_ok: t.success,
  approved_executed: t.success,
  executed_failed: t.error,
  blocked_consent: t.warning,
  advisor_skipped: t.text3,
  advisor_deferred: t.info,
};

/** One-line summary, e.g. "disk_cleanup · executed_ok · advisor proceed 0.82". */
export function healSummary(h: HealReport): string {
  const parts = [h.action, h.outcome];
  if (h.advisor) {
    const conf = typeof h.advisor.confidence === "number" ? ` ${h.advisor.confidence.toFixed(2)}` : "";
    parts.push(`advisor ${h.advisor.recommendation}${conf}`);
  }
  return parts.join(" · ");
}

// Central "Autoheal" log: GET /api/heals, polled like the activity feed.
export function HealFeed({ machines }: { machines: MachineName[] }) {
  const heals = usePolled<HealReport>("/api/heals?limit=100", "heals", 10000);

  const names = new Map(machines.map((m) => [m.machineId, m.hostname]));

  return (
    <section style={{ marginTop: 36 }}>
      <h2 style={{ fontSize: 16, fontWeight: 500, marginBottom: 12, color: t.text1, display: "flex", alignItems: "center", gap: 8 }}>
        Autoheal
        <span style={{ fontSize: 12, color: t.text3, fontWeight: 400 }}>last {heals.length} heals</span>
      </h2>
      {heals.length === 0 ? (
        <p style={{ color: t.text3, fontSize: 13 }}>No heal reports yet.</p>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          {heals.map((h) => {
            const time = new Date(h.ts).toLocaleString([], {
              month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit",
            });
            return (
              <div
                key={h.id}
                title={[h.trigger, h.advisor?.rationale, h.detail].filter(Boolean).join("\n")}
                style={{
                  display: "flex", alignItems: "center", gap: 10, padding: "7px 12px",
                  background: t.surface, borderRadius: 8, fontSize: 12, border: `1px solid ${t.border}`,
                }}
              >
                <span style={{ width: 6, height: 6, borderRadius: "50%", background: outcomeColors[h.outcome] ?? t.text3, flexShrink: 0 }} />
                <span style={{ color: t.text3, minWidth: 130, fontSize: 10, fontFamily: "'SF Mono', monospace" }}>{time}</span>
                <span style={{ flex: 1, color: t.text2 }}>{healSummary(h)}</span>
                <span style={{ color: t.text3, fontSize: 10 }}>{h.consent}</span>
                <span style={{ color: t.text3, fontSize: 10, fontFamily: "'SF Mono', monospace" }}>
                  {names.get(h.machineId) ?? h.machineId.slice(0, 10)}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
