// In-memory store for metrics (Vercel serverless — no persistent state).
// For production, swap with Vercel KV / Postgres / Turso.

export interface MachineMetrics {
  machineId: string;
  hostname: string;
  lastSeen: string;
  cpu: { overall: number; perCore: number[] };
  ram: {
    usedGB: number;
    wiredGB: number;
    compressedGB: number;
    swapUsedMB: number;
    pressureLevel: number;
  };
  disk: {
    volumes: { name: string; mountPoint: string; totalGB: number; freeGB: number }[];
    smart: { bsdName: string; status: string }[];
  };
  processes: {
    topCPU: { pid: number; name: string; cpuPercent: number; ramMB: number; system: boolean }[];
    topRAM: { pid: number; name: string; cpuPercent: number; ramMB: number; system: boolean }[];
  };
}

export interface ActivityEntry {
  timestamp: string;
  machineId: string;
  type: string;
  summary: string;
  detail?: string;
  aiGenerated: boolean;
}

// In-memory maps — resets on cold start (acceptable for MVP)
const machines = new Map<string, MachineMetrics>();
const events: ActivityEntry[] = [];
const metricsHistory = new Map<string, { timestamp: string; cpu: number; ramUsedGB: number }[]>();

const MAX_EVENTS = 1000;
const MAX_HISTORY_PER_MACHINE = 720; // ~1 hour at 5s intervals

export function upsertMachine(data: MachineMetrics) {
  machines.set(data.machineId, { ...data, lastSeen: new Date().toISOString() });

  // Append to history
  const history = metricsHistory.get(data.machineId) ?? [];
  history.push({
    timestamp: new Date().toISOString(),
    cpu: data.cpu.overall,
    ramUsedGB: data.ram.usedGB,
  });
  if (history.length > MAX_HISTORY_PER_MACHINE) {
    history.splice(0, history.length - MAX_HISTORY_PER_MACHINE);
  }
  metricsHistory.set(data.machineId, history);
}

export function addEvent(entry: ActivityEntry) {
  events.unshift(entry);
  if (events.length > MAX_EVENTS) events.length = MAX_EVENTS;
}

export function getMachines(): MachineMetrics[] {
  return Array.from(machines.values());
}

export function getEvents(machineId?: string, limit = 50): ActivityEntry[] {
  const filtered = machineId ? events.filter((e) => e.machineId === machineId) : events;
  return filtered.slice(0, limit);
}

export function getHistory(machineId: string) {
  return metricsHistory.get(machineId) ?? [];
}
