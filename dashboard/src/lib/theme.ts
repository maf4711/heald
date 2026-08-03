export const t = {
  bg: "#050508",
  surface: "#0a0a0f",
  surfaceRaised: "#111118",
  surfaceHover: "#14141c",
  border: "rgba(255, 255, 255, 0.06)",
  borderStrong: "rgba(255, 255, 255, 0.1)",
  text1: "rgba(255, 255, 255, 0.88)",
  text2: "rgba(255, 255, 255, 0.45)",
  text3: "rgba(255, 255, 255, 0.22)",
  brand300: "#7dd3fc",
  brand400: "#38bdf8",
  brand500: "#0ea5e9",
  success: "#34d399",
  warning: "#f5a623",
  error: "#ef4444",
  info: "#3b82f6",
  radius: "12px",
};

export type HealthStatus = "online" | "stale" | "warning" | "critical";

export interface FleetMachine {
  machineId: string;
  hostname: string;
  lastSeen: string;
  cpu?: { overall: number; perCore: number[] };
  ram?: {
    usedGB: number;
    wiredGB: number;
    compressedGB: number;
    swapUsedMB: number;
    pressureLevel: number;
  };
  disk?: {
    volumes: { name: string; mountPoint: string; totalGB: number; freeGB: number }[];
    smart: { bsdName: string; status: string }[];
  };
  processes?: {
    topCPU: { pid: number; name: string; cpuPercent: number; ramMB: number; system: boolean }[];
    topRAM: { pid: number; name: string; cpuPercent: number; ramMB: number; system: boolean }[];
  };
  icloud?: {
    isEnabled: boolean;
    optimizeStorage: boolean;
    localFiles: number;
    cloudFiles: number;
    syncPercent: number;
    directories: number;
    evictedDirs: string[];
    conflicts: number;
    docsSizeGB: number;
    diskFreeGB: number;
    birdRunning: boolean;
  };
  battery?: {
    cycleCount: number;
    maxCapacityPercent: number;
    currentCharge: number;
    isCharging: boolean;
    condition: string;
    temperature: number | null;
  };
  uptime?: { systemSeconds: number; daemonSeconds: number; systemFormatted: string };
  thermal?: string;
  history?: { timestamp: string; cpu: number; ramUsedGB: number }[];
  kind?: string;
  tags?: string[];
  /** Thunderbolt mesh cluster snapshot (from maccluster-heald-push) */
  maccluster?: {
    schema?: string;
    cluster_name?: string;
    overall?: string;
    self_node_id?: string;
    bridge?: {
      name?: string;
      exists?: boolean;
      admin_up?: boolean;
      addresses?: string[];
    };
    nodes?: {
      id?: string;
      ip?: string;
      role?: string;
      reachability?: string;
      link_state?: string;
      rtt_ms?: number | null;
      notes?: string | string[] | null;
    }[];
    nodes_up?: number;
    nodes_total?: number;
    service_running?: boolean;
    doctor_excerpt?: string;
    source?: string;
    ts?: string;
  };
}

export const STALE_MS = 10 * 60_000;

export function isMaccluster(m: FleetMachine): boolean {
  return (
    m.kind === "maccluster" ||
    m.machineId?.startsWith("maccluster:") ||
    !!m.maccluster
  );
}

export function machineStatus(m: FleetMachine, now = Date.now()): HealthStatus {
  const age = now - new Date(m.lastSeen).getTime();
  if (age > STALE_MS || Number.isNaN(age)) return "stale";

  // Virtual / attached maccluster entities use overall + service flags
  if (isMaccluster(m) && m.maccluster) {
    const o = (m.maccluster.overall || "").toLowerCase();
    if (!m.maccluster.service_running) return "critical";
    if (o === "down" || o === "critical" || o === "failed") return "critical";
    if (o === "degraded" || o === "warning" || o === "partial") return "warning";
    if (o === "healthy" || o === "up" || o === "ok") return "online";
  }

  const ic = m.icloud;
  const pr = m.ram?.pressureLevel ?? 0;
  if (m.disk?.smart?.some((s) => s.status === "Failing")) return "critical";
  if (pr >= 4) return "critical";
  if (ic?.isEnabled && !ic.birdRunning) return "critical";
  if (ic?.isEnabled && ic.syncPercent < 50) return "critical";
  if ((m.cpu?.overall ?? 0) > 0.95) return "critical";
  if (pr >= 2) return "warning";
  if (ic?.syncPercent !== undefined && ic.syncPercent < 90) return "warning";
  if (ic && ic.conflicts > 0) return "warning";
  if (ic && (ic.evictedDirs?.length ?? 0) > 0) return "warning";
  if ((m.cpu?.overall ?? 0) > 0.8) return "warning";
  return "online";
}

export function statusColor(s: HealthStatus): string {
  switch (s) {
    case "online":
      return t.success;
    case "warning":
      return t.warning;
    case "critical":
      return t.error;
    case "stale":
      return t.text3;
  }
}

export function ago(iso: string): string {
  const d = Date.now() - new Date(iso).getTime();
  if (Number.isNaN(d) || d < 0) return "—";
  if (d < 60_000) return "now";
  if (d < 3600_000) return `${Math.floor(d / 60_000)}m`;
  if (d < 86400_000) return `${Math.floor(d / 3600_000)}h`;
  return `${Math.floor(d / 86400_000)}d`;
}

export function issueCount(m: FleetMachine): number {
  if (isMaccluster(m) && m.maccluster) {
    let n = 0;
    if (!m.maccluster.service_running) n += 1;
    const o = (m.maccluster.overall || "").toLowerCase();
    if (o && o !== "healthy" && o !== "up" && o !== "ok") n += 1;
    const total = m.maccluster.nodes_total ?? m.maccluster.nodes?.length ?? 0;
    const up = m.maccluster.nodes_up ?? 0;
    if (total > 0 && up < total) n += total - up;
    if (machineStatus(m) === "stale") n += 1;
    return n;
  }
  const ic = m.icloud;
  let n = 0;
  if (ic) {
    n += ic.conflicts ?? 0;
    n += ic.cloudFiles > 0 ? 1 : 0;
    n += ic.evictedDirs?.length ?? 0;
    if (ic.isEnabled && !ic.birdRunning) n += 1;
    if (ic.syncPercent < 99) n += 1;
  }
  if ((m.ram?.pressureLevel ?? 0) >= 2) n += 1;
  if ((m.cpu?.overall ?? 0) > 0.8) n += 1;
  if (machineStatus(m) === "stale") n += 1;
  return n;
}
