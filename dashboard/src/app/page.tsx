"use client";

import { useEffect, useState, useMemo, useCallback } from "react";
import { MachineCard } from "@/components/MachineCard";
import { ActivitySection } from "@/components/ActivitySection";
import { Pagination } from "@/components/Pagination";
import { FleetBar } from "@/components/FleetBar";
import { InstallPanel } from "@/components/InstallPanel";
import { MachineTable, StatusFilter } from "@/components/MachineTable";
import { MachineDrawer } from "@/components/MachineDrawer";
import { HealFeed } from "@/components/HealFeed";
import { ErrorPicture } from "@/components/ErrorPicture";
import { t, FleetMachine, machineStatus, issueCount } from "@/lib/theme";

type SortKey = "name" | "cpu" | "ram" | "sync" | "lastSeen" | "issues";
type ViewMode = "table" | "cards";

export default function Dashboard() {
  const [machines, setMachines] = useState<FleetMachine[]>([]);
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState<SortKey>("issues");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [view, setView] = useState<ViewMode>("table");
  const [page, setPage] = useState(0);
  const [pageSize, setPageSize] = useState<number>(50);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<FleetMachine | null>(null);

  useEffect(() => {
    const fetchData = async () => {
      try {
        const mRes = await fetch("/api/machines", { cache: "no-store" });
        if (mRes.ok) {
          setMachines((await mRes.json()).machines ?? []);
          setLoading(false);
        }
      } catch {
        /* retry */
      }
    };
    fetchData();
    const interval = setInterval(fetchData, 5000);
    return () => clearInterval(interval);
  }, []);

  // Keep selected machine fresh when data refreshes
  useEffect(() => {
    if (!selected) return;
    const fresh = machines.find((m) => m.machineId === selected.machineId);
    if (fresh) setSelected(fresh);
  }, [machines, selected?.machineId]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    const now = Date.now();
    let list = machines;

    if (q) {
      list = list.filter(
        (m) =>
          m.hostname.toLowerCase().includes(q) ||
          m.machineId.toLowerCase().includes(q)
      );
    }

    list = list.filter((m) => {
      const st = machineStatus(m, now);
      switch (statusFilter) {
        case "all":
          return true;
        case "online":
        case "stale":
        case "warning":
        case "critical":
          return st === statusFilter;
        case "issues":
          return issueCount(m) > 0 || st === "stale" || st === "critical" || st === "warning";
        case "highcpu":
          return (m.cpu?.overall ?? 0) > 0.8;
        case "highram":
          return (m.ram?.pressureLevel ?? 0) >= 2;
        default:
          return true;
      }
    });

    list = [...list].sort((a, b) => {
      switch (sort) {
        case "cpu":
          return (b.cpu?.overall ?? 0) - (a.cpu?.overall ?? 0);
        case "ram":
          return (b.ram?.usedGB ?? 0) - (a.ram?.usedGB ?? 0);
        case "sync":
          return (a.icloud?.syncPercent ?? 100) - (b.icloud?.syncPercent ?? 100);
        case "lastSeen":
          return new Date(a.lastSeen).getTime() - new Date(b.lastSeen).getTime();
        case "issues": {
          const score = (m: FleetMachine) => {
            const st = machineStatus(m, now);
            const base = issueCount(m);
            if (st === "critical") return base + 100;
            if (st === "stale") return base + 50;
            if (st === "warning") return base + 20;
            return base;
          };
          return score(b) - score(a) || a.hostname.localeCompare(b.hostname);
        }
        default:
          return a.hostname.localeCompare(b.hostname);
      }
    });

    return list;
  }, [machines, search, sort, statusFilter]);

  // Reset page when filters change
  useEffect(() => {
    setPage(0);
  }, [search, sort, statusFilter, pageSize]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / pageSize));
  const safePage = Math.min(page, pageCount - 1);
  const pageSlice = useMemo(() => {
    const start = safePage * pageSize;
    return filtered.slice(start, start + pageSize);
  }, [filtered, safePage, pageSize]);

  const onFilter = useCallback((f: StatusFilter) => {
    setStatusFilter((prev) => (prev === f ? "all" : f));
  }, []);

  const sortBtns: { key: SortKey; label: string }[] = [
    { key: "issues", label: "Priority" },
    { key: "name", label: "Name" },
    { key: "cpu", label: "CPU" },
    { key: "ram", label: "RAM" },
    { key: "sync", label: "iCloud" },
    { key: "lastSeen", label: "Seen" },
  ];

  return (
    <div style={{ maxWidth: 1440, margin: "0 auto", padding: "20px 16px 48px" }}>
      <header
        style={{
          marginBottom: 20,
          display: "flex",
          alignItems: "center",
          gap: 12,
          flexWrap: "wrap",
        }}
      >
        <h1
          style={{
            fontSize: 26,
            fontWeight: 200,
            margin: 0,
            letterSpacing: "0.02em",
            fontFamily:
              "-apple-system, BlinkMacSystemFont, 'SF Pro Display', Inter, sans-serif",
          }}
        >
          heald
        </h1>
        <span
          style={{
            fontSize: 13,
            color: t.text2,
            fontVariantNumeric: "tabular-nums",
          }}
        >
          {machines.length.toLocaleString()} machine
          {machines.length !== 1 ? "s" : ""}
          {filtered.length !== machines.length && (
            <span style={{ color: t.brand400 }}>
              {" "}
              · {filtered.length.toLocaleString()} shown
            </span>
          )}
        </span>
        <span style={{ marginLeft: "auto", fontSize: 11, color: t.text3 }}>
          auto-refresh 5s · fleet scale
        </span>
      </header>

      <InstallPanel />
      <FleetBar machines={machines} filter={statusFilter} onFilter={onFilter} />

      {loading ? (
        <div style={{ textAlign: "center", padding: 64, color: t.text2 }}>
          <div style={{ fontSize: 18, fontWeight: 500, marginBottom: 8 }}>
            Connecting to fleet…
          </div>
          <div style={{ fontSize: 13, color: t.text3 }}>Waiting for daemon metrics</div>
        </div>
      ) : machines.length === 0 ? (
        <div style={{ textAlign: "center", padding: 64, color: t.text2 }}>
          <div style={{ fontSize: 18, fontWeight: 500, marginBottom: 8 }}>
            No machines connected yet.
          </div>
          <div style={{ fontSize: 13, color: t.text3 }}>
            Open the install panel above to get started.
          </div>
        </div>
      ) : (
        <>
          {/* Toolbar */}
          <div
            style={{
              display: "flex",
              gap: 10,
              marginBottom: 12,
              flexWrap: "wrap",
              alignItems: "center",
            }}
          >
            <input
              type="search"
              placeholder="Search hostname or machine id…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{
                padding: "8px 14px",
                background: t.surface,
                border: `1px solid ${t.border}`,
                borderRadius: 8,
                color: t.text1,
                fontSize: 14,
                flex: "1 1 220px",
                minWidth: 180,
                outline: "none",
              }}
            />

            <div style={{ display: "flex", gap: 4, flexWrap: "wrap" }}>
              {sortBtns.map((b) => (
                <button
                  key={b.key}
                  type="button"
                  onClick={() => setSort(b.key)}
                  style={{
                    padding: "5px 11px",
                    borderRadius: 16,
                    cursor: "pointer",
                    fontSize: 12,
                    fontWeight: 500,
                    background: sort === b.key ? t.brand400 + "18" : t.surface,
                    color: sort === b.key ? t.brand400 : t.text2,
                    border: `1px solid ${sort === b.key ? t.brand400 + "33" : t.border}`,
                  }}
                >
                  {b.label}
                </button>
              ))}
            </div>

            <div
              style={{
                display: "flex",
                gap: 4,
                marginLeft: "auto",
                border: `1px solid ${t.border}`,
                borderRadius: 8,
                overflow: "hidden",
              }}
            >
              {(
                [
                  ["table", "Table"],
                  ["cards", "Cards"],
                ] as const
              ).map(([mode, label]) => (
                <button
                  key={mode}
                  type="button"
                  onClick={() => setView(mode)}
                  style={{
                    padding: "6px 12px",
                    border: "none",
                    cursor: "pointer",
                    fontSize: 12,
                    fontWeight: 500,
                    background: view === mode ? t.brand400 + "22" : t.surface,
                    color: view === mode ? t.brand400 : t.text2,
                  }}
                >
                  {label}
                </button>
              ))}
            </div>
          </div>

          {/* Pagination top */}
          <Pagination
            page={safePage}
            pageCount={pageCount}
            pageSize={pageSize}
            total={filtered.length}
            onPage={setPage}
            onPageSize={setPageSize}
          />

          {view === "table" ? (
            <MachineTable
              machines={pageSlice}
              selectedId={selected?.machineId}
              onSelect={setSelected}
            />
          ) : (
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fill, minmax(360px, 1fr))",
                gap: 12,
              }}
            >
              {pageSlice.map((m) => (
                <div
                  key={m.machineId}
                  onClick={() => setSelected(m)}
                  style={{ cursor: "pointer" }}
                >
                  <MachineCard machine={{ ...m, history: m.history ?? [] }} />
                </div>
              ))}
            </div>
          )}

          <div style={{ marginTop: 12 }}>
            <Pagination
              page={safePage}
              pageCount={pageCount}
              pageSize={pageSize}
              total={filtered.length}
              onPage={setPage}
              onPageSize={setPageSize}
            />
          </div>
        </>
      )}

      <ErrorPicture machines={machines} />
      <HealFeed machines={machines} />

      <ActivitySection />

      <footer
        style={{
          marginTop: 40,
          padding: "16px 0",
          borderTop: `1px solid ${t.border}`,
          textAlign: "center",
          color: t.text3,
          fontSize: 11,
        }}
      >
        <a
          href="https://github.com/maf4711/heald"
          target="_blank"
          rel="noopener"
          style={{ color: t.brand500, textDecoration: "none" }}
        >
          GitHub
        </a>
        <span style={{ margin: "0 12px" }}>|</span>
        <span>heald fleet</span>
        <span style={{ margin: "0 12px" }}>|</span>
        <a href="https://heald.sh/api/update" style={{ color: t.text3 }}>
          /api/update
        </a>
      </footer>

      <MachineDrawer machine={selected} onClose={() => setSelected(null)} />
    </div>
  );
}
