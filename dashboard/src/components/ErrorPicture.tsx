"use client";

import { t } from "@/lib/theme";
import { usePolled } from "@/components/usePolled";
import type { MachineErrorPicture } from "@/lib/heal-report";

type MachineName = { machineId: string; hostname: string };

const plural = (n: number, word: string) => `${n} open ${word}${n === 1 ? "" : "s"}`;

/** Card headline, e.g. "node-a · 1 open error · 3 fixed". */
export function pictureSummary(name: string, p: MachineErrorPicture): string {
  const parts = [name];
  if (p.critical) parts.push(plural(p.critical, "critical"));
  if (p.error) parts.push(plural(p.error, "error"));
  if (p.warning) parts.push(plural(p.warning, "warning"));
  if (!p.critical && !p.error && !p.warning) parts.push("no open findings");
  parts.push(`${p.fixed} fixed`);
  return parts.join(" · ");
}

// Per-machine "Fehlerbild": open findings by severity, fixed count, last fix.
// Computed server-side over the full buckets (GET /api/error-picture).
export function ErrorPicture({ machines }: { machines: MachineName[] }) {
  const pictures = usePolled<MachineErrorPicture>("/api/error-picture", "machines", 10000);

  const names = new Map(machines.map((m) => [m.machineId, m.hostname]));

  return (
    <section style={{ marginTop: 36 }}>
      <h2 style={{ fontSize: 16, fontWeight: 500, marginBottom: 12, color: t.text1 }}>Fehlerbild</h2>
      {pictures.length === 0 ? (
        <p style={{ color: t.text3, fontSize: 13 }}>No findings reported yet.</p>
      ) : (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(300px, 1fr))", gap: 10 }}>
          {pictures.map((p) => {
            const accent = p.critical || p.error ? t.error : p.warning ? t.warning : t.success;
            const name = names.get(p.machineId) ?? p.machineId.slice(0, 10);
            return (
              <div
                key={p.machineId}
                style={{
                  padding: "12px 14px", background: t.surface, borderRadius: 10,
                  border: `1px solid ${t.border}`, borderLeft: `3px solid ${accent}`, fontSize: 12,
                }}
              >
                <div style={{ color: t.text1, fontWeight: 500, marginBottom: 6 }}>{pictureSummary(name, p)}</div>
                <div style={{ color: t.text3, fontSize: 11 }}>
                  {p.lastFix
                    ? `last fix: ${p.lastFix.action} · ${new Date(p.lastFix.ts).toLocaleString()}`
                    : "no successful heal yet"}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
