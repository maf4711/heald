"use client";

import {
  t,
  FleetMachine,
  machineStatus,
  statusColor,
  ago,
  issueCount,
  isMaccluster,
  HealthStatus,
} from "@/lib/theme";

export type StatusFilter = "all" | HealthStatus | "issues" | "highcpu" | "highram";

function pct(n: number | undefined, asFraction = true): number {
  if (n == null || Number.isNaN(n)) return 0;
  return asFraction && n <= 1.5 ? n * 100 : n;
}

function barColor(p: number): string {
  if (p >= 90) return t.error;
  if (p >= 70) return t.warning;
  return t.brand400;
}

function MiniBar({ value }: { value: number }) {
  const p = Math.min(100, Math.max(0, value));
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 88 }}>
      <div
        style={{
          flex: 1,
          height: 4,
          borderRadius: 2,
          background: t.borderStrong,
          overflow: "hidden",
        }}
      >
        <div
          style={{
            width: `${p}%`,
            height: "100%",
            background: barColor(p),
            borderRadius: 2,
            transition: "width 200ms ease",
          }}
        />
      </div>
      <span
        style={{
          fontSize: 11,
          fontVariantNumeric: "tabular-nums",
          color: t.text2,
          width: 32,
          textAlign: "right",
        }}
      >
        {p.toFixed(0)}%
      </span>
    </div>
  );
}

export function MachineTable({
  machines,
  selectedId,
  onSelect,
}: {
  machines: FleetMachine[];
  selectedId?: string | null;
  onSelect: (m: FleetMachine) => void;
}) {
  return (
    <div
      style={{
        background: t.surface,
        border: `1px solid ${t.border}`,
        borderRadius: 12,
        overflow: "hidden",
      }}
    >
      <div style={{ overflowX: "auto" }}>
        <table
          style={{
            width: "100%",
            borderCollapse: "collapse",
            fontSize: 13,
            minWidth: 880,
          }}
        >
          <thead>
            <tr
              style={{
                borderBottom: `1px solid ${t.border}`,
                color: t.text3,
                fontSize: 11,
                fontWeight: 600,
                letterSpacing: "0.04em",
                textTransform: "uppercase",
              }}
            >
              {[
                { k: "status", w: 36, label: "" },
                { k: "host", w: undefined, label: "Host" },
                { k: "cpu", w: 120, label: "CPU" },
                { k: "ram", w: 100, label: "RAM" },
                { k: "disk", w: 90, label: "Disk free" },
                { k: "icloud", w: 100, label: "iCloud" },
                { k: "issues", w: 64, label: "Issues" },
                { k: "seen", w: 72, label: "Seen" },
              ].map((col) => (
                <th
                  key={col.k}
                  style={{
                    textAlign: col.k === "host" || col.k === "status" ? "left" : "right",
                    padding: "10px 12px",
                    fontWeight: 600,
                    whiteSpace: "nowrap",
                    width: col.w,
                  }}
                >
                  {col.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {machines.map((m) => {
              const st = machineStatus(m);
              const color = statusColor(st);
              const cpu = pct(m.cpu?.overall);
              const root = m.disk?.volumes?.find((v) => v.mountPoint === "/");
              const diskFree = root
                ? root.totalGB > 0
                  ? (root.freeGB / root.totalGB) * 100
                  : 0
                : null;
              const sync = m.icloud?.syncPercent;
              const issues = issueCount(m);
              const selected = selectedId === m.machineId;
              const mac = isMaccluster(m);
              const mc = m.maccluster;
              const nodesUp =
                mc?.nodes_up ??
                (mc?.nodes ?? []).filter((n) => n.reachability === "up").length;
              const nodesTotal = mc?.nodes_total ?? mc?.nodes?.length ?? 0;
              const nodeRatio =
                nodesTotal > 0 ? (nodesUp / nodesTotal) * 100 : 0;

              return (
                <tr
                  key={m.machineId}
                  onClick={() => onSelect(m)}
                  style={{
                    borderBottom: `1px solid ${t.border}`,
                    cursor: "pointer",
                    background: selected ? t.brand400 + "12" : "transparent",
                    opacity: st === "stale" ? 0.55 : 1,
                    transition: "background 120ms ease",
                  }}
                  onMouseEnter={(e) => {
                    if (!selected) e.currentTarget.style.background = t.surfaceHover;
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.background = selected
                      ? t.brand400 + "12"
                      : "transparent";
                  }}
                >
                  <td style={{ padding: "8px 12px" }}>
                    <span
                      title={st}
                      style={{
                        display: "inline-block",
                        width: 8,
                        height: 8,
                        borderRadius: "50%",
                        background: color,
                        boxShadow: st === "online" ? `0 0 0 3px ${color}22` : undefined,
                      }}
                    />
                  </td>
                  <td style={{ padding: "8px 12px", textAlign: "left" }}>
                    <div
                      style={{
                        fontWeight: 500,
                        color: t.text1,
                        letterSpacing: "-0.01em",
                        maxWidth: 220,
                        overflow: "hidden",
                        textOverflow: "ellipsis",
                        whiteSpace: "nowrap",
                      }}
                      title={m.hostname}
                    >
                      {m.hostname}
                      {mac ? (
                        <span
                          style={{
                            marginLeft: 6,
                            fontSize: 9,
                            fontWeight: 600,
                            color: t.brand400,
                            letterSpacing: "0.04em",
                            textTransform: "uppercase",
                          }}
                        >
                          mesh
                        </span>
                      ) : null}
                    </div>
                    <div
                      style={{
                        fontSize: 10,
                        color: t.text3,
                        fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
                        maxWidth: 220,
                        overflow: "hidden",
                        textOverflow: "ellipsis",
                      }}
                      title={m.machineId}
                    >
                      {mac && mc?.overall
                        ? `${mc.overall} · ${nodesUp}/${nodesTotal} nodes`
                        : m.machineId}
                    </div>
                  </td>
                  <td style={{ padding: "8px 12px" }}>
                    <div style={{ display: "flex", justifyContent: "flex-end" }}>
                      {mac ? (
                        <MiniBar value={nodeRatio} />
                      ) : (
                        <MiniBar value={cpu} />
                      )}
                    </div>
                  </td>
                  <td
                    style={{
                      padding: "8px 12px",
                      textAlign: "right",
                      fontVariantNumeric: "tabular-nums",
                      color: mac
                        ? color
                        : (m.ram?.pressureLevel ?? 0) >= 2
                          ? t.warning
                          : t.text2,
                    }}
                  >
                    {mac
                      ? mc?.overall || "—"
                      : (
                        <>
                          {(m.ram?.usedGB ?? 0).toFixed(1)}G
                          {(m.ram?.pressureLevel ?? 0) >= 2 ? (
                            <span style={{ color: t.warning, marginLeft: 4, fontSize: 10 }}>
                              P{m.ram?.pressureLevel}
                            </span>
                          ) : null}
                        </>
                      )}
                  </td>
                  <td
                    style={{
                      padding: "8px 12px",
                      textAlign: "right",
                      fontVariantNumeric: "tabular-nums",
                      color: mac
                        ? mc?.service_running
                          ? t.success
                          : t.error
                        : diskFree != null && diskFree < 10
                          ? t.error
                          : diskFree != null && diskFree < 20
                            ? t.warning
                            : t.text2,
                    }}
                  >
                    {mac
                      ? mc?.service_running
                        ? "svc up"
                        : "svc down"
                      : root
                        ? `${root.freeGB.toFixed(0)}G`
                        : "—"}
                  </td>
                  <td
                    style={{
                      padding: "8px 12px",
                      textAlign: "right",
                      fontVariantNumeric: "tabular-nums",
                      color: mac
                        ? t.text2
                        : sync == null
                          ? t.text3
                          : sync >= 99
                            ? t.success
                            : sync >= 90
                              ? t.warning
                              : t.error,
                    }}
                  >
                    {mac
                      ? mc?.bridge?.admin_up
                        ? "bridge up"
                        : mc?.bridge?.exists
                          ? "bridge down"
                          : "—"
                      : (
                        <>
                          {sync == null ? "—" : `${sync.toFixed(0)}%`}
                          {m.icloud && !m.icloud.birdRunning ? (
                            <span style={{ color: t.error, marginLeft: 4, fontSize: 10 }}>bird</span>
                          ) : null}
                        </>
                      )}
                  </td>
                  <td
                    style={{
                      padding: "8px 12px",
                      textAlign: "right",
                      fontVariantNumeric: "tabular-nums",
                      color: issues > 0 ? t.warning : t.text3,
                      fontWeight: issues > 0 ? 600 : 400,
                    }}
                  >
                    {issues || "—"}
                  </td>
                  <td
                    style={{
                      padding: "8px 12px",
                      textAlign: "right",
                      color: st === "stale" ? t.error : t.text3,
                      fontVariantNumeric: "tabular-nums",
                    }}
                  >
                    {ago(m.lastSeen)}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {machines.length === 0 && (
        <div style={{ padding: 40, textAlign: "center", color: t.text3, fontSize: 13 }}>
          No machines match the current filters.
        </div>
      )}
    </div>
  );
}
