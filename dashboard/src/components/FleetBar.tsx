"use client";

import {
  t,
  FleetMachine,
  machineStatus,
  STALE_MS,
  issueCount,
  HealthStatus,
} from "@/lib/theme";
import type { StatusFilter } from "@/components/MachineTable";

export function FleetBar({
  machines,
  filter,
  onFilter,
}: {
  machines: FleetMachine[];
  filter: StatusFilter;
  onFilter: (f: StatusFilter) => void;
}) {
  if (machines.length === 0) return null;

  const now = Date.now();
  let online = 0;
  let stale = 0;
  let warning = 0;
  let critical = 0;
  let issues = 0;
  let highCpu = 0;
  let highRam = 0;
  let avgCpu = 0;

  for (const m of machines) {
    const st = machineStatus(m, now);
    if (st === "online") online++;
    else if (st === "stale") stale++;
    else if (st === "warning") warning++;
    else if (st === "critical") critical++;
    if (issueCount(m) > 0) issues++;
    if ((m.cpu?.overall ?? 0) > 0.8) highCpu++;
    if ((m.ram?.pressureLevel ?? 0) >= 2) highRam++;
    avgCpu += m.cpu?.overall ?? 0;
  }
  const total = machines.length;
  avgCpu = total > 0 ? (avgCpu / total) * 100 : 0;

  const chips: {
    key: StatusFilter;
    label: string;
    value: string | number;
    color?: string;
  }[] = [
    { key: "all", label: "All", value: total },
    { key: "online", label: "Online", value: online, color: t.success },
    { key: "stale", label: "Stale", value: stale, color: stale > 0 ? t.error : t.text2 },
    { key: "warning", label: "Warn", value: warning, color: warning > 0 ? t.warning : t.text2 },
    {
      key: "critical",
      label: "Critical",
      value: critical,
      color: critical > 0 ? t.error : t.text2,
    },
    { key: "issues", label: "Issues", value: issues, color: issues > 0 ? t.warning : t.text2 },
    {
      key: "highcpu",
      label: "CPU>80%",
      value: highCpu,
      color: highCpu > 0 ? t.error : t.text2,
    },
    {
      key: "highram",
      label: "RAM press.",
      value: highRam,
      color: highRam > 0 ? t.warning : t.text2,
    },
  ];

  return (
    <div style={{ marginBottom: 16 }}>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 8 }}>
        {chips.map((s) => {
          const active = filter === s.key;
          return (
            <button
              key={s.key}
              type="button"
              onClick={() => onFilter(s.key)}
              style={{
                background: active ? t.brand400 + "18" : t.surface,
                border: `1px solid ${active ? t.brand400 + "44" : t.border}`,
                borderRadius: 12,
                padding: "10px 14px",
                textAlign: "center",
                minWidth: 72,
                cursor: "pointer",
                transition: "all 150ms ease",
              }}
            >
              <div
                style={{
                  fontSize: 18,
                  fontWeight: 600,
                  color: s.color ?? t.text1,
                  lineHeight: 1.15,
                  fontVariantNumeric: "tabular-nums",
                  letterSpacing: "-0.02em",
                }}
              >
                {s.value}
              </div>
              <div
                style={{
                  fontSize: 10,
                  color: active ? t.brand400 : t.text2,
                  marginTop: 2,
                  fontWeight: 600,
                  letterSpacing: "0.03em",
                  textTransform: "uppercase",
                }}
              >
                {s.label}
              </div>
            </button>
          );
        })}
        <div
          style={{
            background: t.surface,
            border: `1px solid ${t.border}`,
            borderRadius: 12,
            padding: "10px 14px",
            textAlign: "center",
            minWidth: 72,
          }}
        >
          <div
            style={{
              fontSize: 18,
              fontWeight: 600,
              color: avgCpu > 80 ? t.error : avgCpu > 60 ? t.warning : t.text1,
              fontVariantNumeric: "tabular-nums",
            }}
          >
            {avgCpu.toFixed(0)}%
          </div>
          <div
            style={{
              fontSize: 10,
              color: t.text2,
              marginTop: 2,
              fontWeight: 600,
              letterSpacing: "0.03em",
              textTransform: "uppercase",
            }}
          >
            CPU avg
          </div>
        </div>
      </div>
      <div style={{ fontSize: 11, color: t.text3 }}>
        Stale = no heartbeat &gt; {Math.round(STALE_MS / 60000)} min · click a chip to filter ·
        click a row for detail
      </div>
    </div>
  );
}

// re-export type used by page
export type { HealthStatus };
