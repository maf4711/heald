// Pure heal-log + fleet error picture logic (GOAL 4).
// No imports: node --test loads this file directly (type stripping), and
// store.ts / routes / components reuse it through the `@/` alias.

export const HEAL_SCHEMA = "heald.heal_report/v1";
export const FINDING_SCHEMA = "heald.findings/v1";
export const MAX_HEALS = 5000;
export const MAX_FINDINGS_PER_MACHINE = 500;
export const MAX_BATCH = 500;
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

// Per-field caps (reviewer F1) and clock-skew allowance (F6)
export const MAX_ID_CHARS = 128;
export const MAX_SHORT_CHARS = 64;
export const MAX_TEXT_CHARS = 500;
export const MAX_SAMPLE_CHARS = 400;
export const MAX_ISO_CHARS = 40;
export const MAX_SOURCES = 20;
export const MAX_SOURCE_CHARS = 256;
export const MAX_FUTURE_MS = 24 * 60 * 60 * 1000;

const CONSENTS = ["auto", "ask", "log"] as const;
const SEVERITIES = ["info", "warning", "error", "critical"] as const;
const ADVISOR_SOURCES = ["appleFM", "rules"] as const;
const RECOMMENDATIONS = ["proceed", "defer", "skip"] as const;

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

type Check = string | null; // reason, or null when the field is fine

function str(v: unknown, field: string, max: number, required = false, nullable = false): Check {
  if (v === undefined || v === null) {
    if (required) return `missing ${field}`;
    return v === null && !nullable ? `invalid ${field}` : null;
  }
  if (typeof v !== "string") return `invalid ${field}`;
  if (required && !v.trim()) return `missing ${field}`;
  return v.length > max ? `${field} too long` : null;
}

function num(v: unknown, field: string): Check {
  return v === undefined || (typeof v === "number" && Number.isFinite(v)) ? null : `invalid ${field}`;
}

function oneOf(v: unknown, field: string, allowed: readonly string[], required = false): Check {
  if (v === undefined || v === null) return required ? `missing ${field}` : null;
  return allowed.includes(v as string) ? null : `invalid ${field}`;
}

function iso(v: unknown, field: string, now: number, required = false, futureCheck = false): Check {
  if (v === undefined || v === null) return required ? `missing ${field}` : null;
  if (typeof v !== "string" || v.length > MAX_ISO_CHARS) return `invalid ${field}`;
  const t = Date.parse(v);
  if (!Number.isFinite(t)) return `invalid ${field}`;
  return futureCheck && t > now + MAX_FUTURE_MS ? `${field} in the future` : null;
}

function first(checks: Check[]): Validation {
  const reason = checks.find((c) => c !== null);
  return reason ? { ok: false, reason } : { ok: true };
}

function detail(v: unknown): Check {
  if (v === undefined) return null;
  if (typeof v !== "string") return "invalid detail";
  return v.length > MAX_DETAIL_CHARS ? "detail too long" : null;
}

function advisorCheck(v: unknown): Check {
  if (v === undefined || v === null) return "missing advisor";
  if (!isRecord(v)) return "invalid advisor";
  const r = first([
    oneOf(v.source, "advisor.source", ADVISOR_SOURCES, true),
    oneOf(v.recommendation, "advisor.recommendation", RECOMMENDATIONS, true),
    num(v.confidence, "advisor.confidence"),
    num(v.latencyMs, "advisor.latencyMs"),
    str(v.rationale, "advisor.rationale", MAX_TEXT_CHARS),
  ]);
  return r.ok ? null : r.reason;
}

export function validateHealReport(v: unknown, now: number = Date.now()): Validation {
  if (!isRecord(v)) return { ok: false, reason: "not an object" };
  if (v.schema !== HEAL_SCHEMA) return { ok: false, reason: "unknown schema" };
  return first([
    str(v.id, "id", MAX_ID_CHARS, true),
    str(v.machineId, "machineId", MAX_ID_CHARS, true),
    str(v.action, "action", MAX_SHORT_CHARS, true),
    v.outcome === undefined || v.outcome === null || v.outcome === "" ? "missing outcome" : null,
    oneOf(v.outcome, "outcome", HEAL_OUTCOMES),
    iso(v.ts, "ts", now, true, true),
    str(v.healdVersion, "healdVersion", MAX_SHORT_CHARS),
    str(v.trigger, "trigger", MAX_TEXT_CHARS),
    oneOf(v.consent, "consent", CONSENTS),
    num(v.durationMs, "durationMs"),
    str(v.findingFingerprint, "findingFingerprint", MAX_ID_CHARS, false, true),
    detail(v.detail),
    advisorCheck(v.advisor),
  ]);
}

function sourcesCheck(v: unknown): Check {
  if (v === undefined) return null;
  if (!Array.isArray(v)) return "invalid sources";
  if (v.length > MAX_SOURCES) return "too many sources";
  return v.every((x) => typeof x === "string" && x.length <= MAX_SOURCE_CHARS) ? null : "invalid sources";
}

export function validateFinding(v: unknown, now: number = Date.now()): Validation {
  if (!isRecord(v)) return { ok: false, reason: "not an object" };
  if (v.schema !== FINDING_SCHEMA) return { ok: false, reason: "unknown schema" };
  return first([
    str(v.fingerprint, "fingerprint", MAX_ID_CHARS, true),
    str(v.machineId, "machineId", MAX_ID_CHARS, true),
    v.status === undefined || v.status === null || v.status === "" ? "missing status" : null,
    oneOf(v.status, "status", FINDING_STATUSES),
    oneOf(v.severity, "severity", SEVERITIES, true),
    str(v.category, "category", MAX_SHORT_CHARS),
    str(v.component, "component", MAX_SHORT_CHARS),
    str(v.linkedAction, "linkedAction", MAX_SHORT_CHARS, false, true),
    num(v.count, "count"),
    num(v.recurrenceCount, "recurrenceCount"),
    iso(v.firstSeen, "firstSeen", now),
    iso(v.lastSeen, "lastSeen", now, false, true),
    str(v.sample, "sample", MAX_SAMPLE_CHARS),
    sourcesCheck(v.sources),
    detail(v.detail),
  ]);
}

function pick<T>(src: Record<string, unknown>, keys: readonly string[]): T {
  const out: Record<string, unknown> = {};
  for (const k of keys) if (src[k] !== undefined) out[k] = src[k];
  return out as T;
}

const HEAL_KEYS = [
  "schema", "id", "machineId", "ts", "healdVersion", "action", "trigger", "consent",
  "outcome", "durationMs", "findingFingerprint", "detail",
] as const;
const ADVISOR_KEYS = ["source", "recommendation", "confidence", "rationale", "latencyMs"] as const;
const FINDING_KEYS = [
  "schema", "machineId", "fingerprint", "category", "component", "severity", "count", "status",
  "recurrenceCount", "linkedAction", "firstSeen", "lastSeen", "sources", "sample", "detail",
] as const;

/** Copy only known heal fields (call after validateHealReport). */
export function projectHeal(v: Record<string, unknown>): HealReport {
  const h = pick<HealReport>(v, HEAL_KEYS);
  h.advisor = pick<HealAdvisor>(v.advisor as Record<string, unknown>, ADVISOR_KEYS);
  if (h.findingFingerprint === undefined) h.findingFingerprint = null;
  return h;
}

/** Copy only known finding fields (call after validateFinding). */
export function projectFinding(v: Record<string, unknown>): Finding {
  const f = pick<Finding>(v, FINDING_KEYS);
  if (Array.isArray(f.sources)) f.sources = [...f.sources];
  return f;
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

type Counts = { accepted: number; rejected: number };

/** Validate + project up to `max` items; everything else counts as rejected. */
function partition<T>(
  items: unknown[],
  validate: (v: unknown) => Validation,
  project: (v: Record<string, unknown>) => T,
  max = Infinity,
): { valid: T[]; counts: Counts } {
  const valid: T[] = [];
  items.slice(0, max).forEach((v) => {
    if (validate(v).ok) valid.push(project(v as Record<string, unknown>));
  });
  return { valid, counts: { accepted: valid.length, rejected: items.length - valid.length } };
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
export function mergeHealBuckets(target: HealBuckets, data: unknown, now: number = Date.now()): HealBuckets {
  if (!isRecord(data)) return { heals: target.heals, findings: target.findings };
  const heals = Array.isArray(data.heals) ? partition(data.heals, (v) => validateHealReport(v, now), projectHeal).valid : [];
  const findings = Array.isArray(data.findings)
    ? partition(data.findings, (v) => validateFinding(v, now), projectFinding).valid
    : [];
  return {
    heals: heals.length ? applyHeals(target.heals, heals) : target.heals,
    findings: findings.length ? applyFindings(target.findings, findings) : target.findings,
  };
}


export type IngestResult =
  | { status: 400; json: { error: string } }
  | {
      status: 200;
      json: { ok: true; heals: Counts; findings: Counts };
      heals: HealReport[];
      findings: Finding[];
    };


/**
 * Validate the heal/finding part of a POST /api/ingest body. Invalid records
 * are counted as rejected (batch still 200); a non-array `heals`/`findings`
 * or a non-object body is a 400. Only the first MAX_BATCH records of each
 * array are considered; the excess counts as rejected. Stored records are a
 * projection of known fields. `metrics`/`events` are handled by the route.
 */
export function ingestBody(body: unknown, now: number = Date.now()): IngestResult {
  if (!isRecord(body)) return { status: 400, json: { error: "Invalid payload" } };
  if (body.heals !== undefined && !Array.isArray(body.heals)) {
    return { status: 400, json: { error: "heals must be an array" } };
  }
  if (body.findings !== undefined && !Array.isArray(body.findings)) {
    return { status: 400, json: { error: "findings must be an array" } };
  }
  const heals = partition((body.heals as unknown[]) ?? [], (v) => validateHealReport(v, now), projectHeal, MAX_BATCH);
  const findings = partition((body.findings as unknown[]) ?? [], (v) => validateFinding(v, now), projectFinding, MAX_BATCH);
  return {
    status: 200,
    json: { ok: true, heals: heals.counts, findings: findings.counts },
    heals: heals.valid,
    findings: findings.valid,
  };
}

export interface MachineErrorPicture {
  machineId: string;
  critical: number;
  error: number;
  warning: number;
  info: number;
  fixed: number;
  lastFix: HealReport | null;
}

const FIX_OUTCOMES: readonly HealOutcome[] = ["executed_ok", "approved_executed"];

/**
 * Per-machine "Fehlerbild": open (open|recurring) findings by severity, fixed
 * findings, and the newest successful heal. Most severe machines first.
 */
export function machineErrorPicture(
  findings: readonly Finding[],
  heals: readonly HealReport[],
): MachineErrorPicture[] {
  const pics = new Map<string, MachineErrorPicture>();
  const pic = (machineId: string) => {
    let p = pics.get(machineId);
    if (!p) {
      p = { machineId, critical: 0, error: 0, warning: 0, info: 0, fixed: 0, lastFix: null };
      pics.set(machineId, p);
    }
    return p;
  };
  for (const f of findings) {
    const p = pic(f.machineId);
    if (f.status === "fixed") p.fixed++;
    else if (f.severity === "critical" || f.severity === "error" || f.severity === "warning") p[f.severity]++;
    else p.info++;
  }
  for (const h of heals) {
    if (!FIX_OUTCOMES.includes(h.outcome)) {
      pic(h.machineId);
      continue;
    }
    const p = pic(h.machineId);
    if (!p.lastFix || (h.ts ?? "") > (p.lastFix.ts ?? "")) p.lastFix = h;
  }
  const weight = (p: MachineErrorPicture) => [p.critical, p.error, p.warning, p.info];
  return Array.from(pics.values()).sort((a, b) => {
    const wa = weight(a);
    const wb = weight(b);
    for (let i = 0; i < wa.length; i++) if (wa[i] !== wb[i]) return wb[i] - wa[i];
    return a.machineId.localeCompare(b.machineId);
  });
}
