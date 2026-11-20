// Pure heal-log + fleet error picture logic (GOAL 4).
// No imports: node --test loads this file directly (type stripping), and
// store.ts / routes / components reuse it through the `@/` alias.

export const HEAL_SCHEMA = "heald.heal_report/v1";
export const FINDING_SCHEMA = "heald.findings/v1";
export const MAX_HEALS = 5000;
export const MAX_FINDINGS_PER_MACHINE = 500;
export const MAX_DETAIL_CHARS = 4000;
export const MIN_LIMIT = 1;
export const MAX_LIMIT = 500;

export const HEAL_OUTCOMES = [
  "executed_ok",
  "executed_failed",
  "blocked_consent",
  "approved_executed",
  "advisor_skipped",
  "advisor_deferred",
] as const;
export const FINDING_STATUSES = ["open", "fixed", "recurring"] as const;

export type HealOutcome = (typeof HEAL_OUTCOMES)[number];
export type FindingStatus = (typeof FINDING_STATUSES)[number];
export type FindingSeverity = "info" | "warning" | "error" | "critical";

export interface HealAdvisor {
  source: "appleFM" | "rules";
  recommendation: "proceed" | "defer" | "skip";
  confidence: number;
  rationale: string;
  latencyMs: number;
}

export interface HealReport {
  schema: typeof HEAL_SCHEMA;
  id: string;
  machineId: string;
  ts: string;
  healdVersion: string;
  action: string;
  trigger: string;
  consent: "auto" | "ask" | "log";
  outcome: HealOutcome;
  durationMs: number;
  findingFingerprint: string | null;
  detail?: string;
  advisor: HealAdvisor;
}

export interface Finding {
  schema: typeof FINDING_SCHEMA;
  machineId: string;
  fingerprint: string;
  category: string;
  component: string;
  severity: FindingSeverity;
  count: number;
  status: FindingStatus;
  recurrenceCount: number;
  linkedAction: string | null;
  firstSeen: string;
  lastSeen: string;
  sources?: string[];
  sample?: string;
  detail?: string;
}

export type Validation = { ok: true } | { ok: false; reason: string };

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function nonEmpty(v: unknown): boolean {
  return typeof v === "string" && v.trim().length > 0;
}

function checkRequired(
  rec: Record<string, unknown>,
  schema: string,
  required: readonly string[],
): Validation | null {
  if (rec.schema !== schema) return { ok: false, reason: "unknown schema" };
  for (const field of required) {
    if (!nonEmpty(rec[field])) return { ok: false, reason: `missing ${field}` };
  }
  if (rec.detail !== undefined) {
    if (typeof rec.detail !== "string") return { ok: false, reason: "invalid detail" };
    if (rec.detail.length > MAX_DETAIL_CHARS) return { ok: false, reason: "detail too long" };
  }
  return null;
}

export function validateHealReport(v: unknown): Validation {
  if (!isRecord(v)) return { ok: false, reason: "not an object" };
  const err = checkRequired(v, HEAL_SCHEMA, ["id", "machineId", "action", "outcome"]);
  if (err) return err;
  if (!(HEAL_OUTCOMES as readonly unknown[]).includes(v.outcome)) {
    return { ok: false, reason: "invalid outcome" };
  }
  return { ok: true };
}

export function validateFinding(v: unknown): Validation {
  if (!isRecord(v)) return { ok: false, reason: "not an object" };
  const err = checkRequired(v, FINDING_SCHEMA, ["fingerprint", "machineId", "status"]);
  if (err) return err;
  if (!(FINDING_STATUSES as readonly unknown[]).includes(v.status)) {
    return { ok: false, reason: "invalid status" };
  }
  return { ok: true };
}
