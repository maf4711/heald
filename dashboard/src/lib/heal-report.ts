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

const newestFirst = (a: string | undefined, b: string | undefined) =>
  (a ?? "") < (b ?? "") ? 1 : (a ?? "") > (b ?? "") ? -1 : 0;

/** Merge heals into a bucket: dedupe by id (latest copy wins), newest first, cap MAX_HEALS. */
export function applyHeals(bucket: readonly HealReport[], incoming: readonly HealReport[]): HealReport[] {
  const byId = new Map<string, HealReport>();
  for (const h of bucket) byId.set(h.id, h);
  for (const h of incoming) byId.set(h.id, h);
  const out = Array.from(byId.values()).sort((a, b) => newestFirst(a.ts, b.ts));
  if (out.length > MAX_HEALS) out.length = MAX_HEALS;
  return out;
}

const findingKey = (f: Pick<Finding, "machineId" | "fingerprint">) => `${f.machineId}\u0000${f.fingerprint}`;

/** Upsert findings by (machineId, fingerprint); newest lastSeen first; cap per machine. */
export function applyFindings(bucket: readonly Finding[], incoming: readonly Finding[]): Finding[] {
  const byKey = new Map<string, Finding>();
  for (const f of bucket) byKey.set(findingKey(f), f);
  for (const f of incoming) byKey.set(findingKey(f), f);
  const sorted = Array.from(byKey.values()).sort((a, b) => newestFirst(a.lastSeen, b.lastSeen));
  const perMachine = new Map<string, number>();
  return sorted.filter((f) => {
    const n = (perMachine.get(f.machineId) ?? 0) + 1;
    perMachine.set(f.machineId, n);
    return n <= MAX_FINDINGS_PER_MACHINE;
  });
}

/** Parse a GET `limit` and clamp it to MIN_LIMIT..MAX_LIMIT (fallback when absent/invalid). */
export function clampLimit(raw: unknown, fallback = 50): number {
  const n = typeof raw === "number" ? raw : typeof raw === "string" && raw.trim() ? Number(raw) : NaN;
  if (!Number.isFinite(n)) return fallback;
  return Math.min(MAX_LIMIT, Math.max(MIN_LIMIT, Math.trunc(n)));
}

export interface HealBuckets {
  heals: HealReport[];
  findings: Finding[];
}

/**
 * Merge persisted (possibly cold-start / untrusted) bucket data into the live
 * buckets. Invalid records are dropped; caps and dedupe from applyHeals /
 * applyFindings apply.
 */
export function mergeHealBuckets(target: HealBuckets, data: unknown): HealBuckets {
  if (!isRecord(data)) return { heals: target.heals, findings: target.findings };
  const heals = Array.isArray(data.heals)
    ? (data.heals.filter((h) => validateHealReport(h).ok) as HealReport[])
    : [];
  const findings = Array.isArray(data.findings)
    ? (data.findings.filter((f) => validateFinding(f).ok) as Finding[])
    : [];
  return {
    heals: heals.length ? applyHeals(target.heals, heals) : target.heals,
    findings: findings.length ? applyFindings(target.findings, findings) : target.findings,
  };
}

type Counts = { accepted: number; rejected: number };

export type IngestResult =
  | { status: 400; json: { error: string } }
  | {
      status: 200;
      json: { ok: true; heals: Counts; findings: Counts };
      heals: HealReport[];
      findings: Finding[];
    };

function partition<T>(items: unknown[], validate: (v: unknown) => Validation): { valid: T[]; counts: Counts } {
  const valid = items.filter((v) => validate(v).ok) as T[];
  return { valid, counts: { accepted: valid.length, rejected: items.length - valid.length } };
}

/**
 * Validate the heal/finding part of a POST /api/ingest body. Invalid records
 * are counted as rejected (batch still 200); a non-array `heals`/`findings`
 * or a non-object body is a 400. `metrics`/`events` are handled by the route.
 */
export function ingestBody(body: unknown): IngestResult {
  if (!isRecord(body)) return { status: 400, json: { error: "Invalid payload" } };
  if (body.heals !== undefined && !Array.isArray(body.heals)) {
    return { status: 400, json: { error: "heals must be an array" } };
  }
  if (body.findings !== undefined && !Array.isArray(body.findings)) {
    return { status: 400, json: { error: "findings must be an array" } };
  }
  const heals = partition<HealReport>((body.heals as unknown[]) ?? [], validateHealReport);
  const findings = partition<Finding>((body.findings as unknown[]) ?? [], validateFinding);
  return {
    status: 200,
    json: { ok: true, heals: heals.counts, findings: findings.counts },
    heals: heals.valid,
    findings: findings.valid,
  };
}
