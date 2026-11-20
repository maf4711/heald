// Reviewer F1/F6: per-field caps, projection, batch caps, future timestamps.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  validateHealReport,
  validateFinding,
  ingestBody,
  MAX_BATCH,
  type HealReport,
  type Finding,
} from "./heal-report.ts";

const NOW = Date.parse("2026-11-21T12:00:00Z");

function heal(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    schema: "heald.heal_report/v1",
    id: "h-1",
    machineId: "node-a",
    ts: "2026-11-21T09:00:00Z",
    healdVersion: "3.6.0",
    action: "disk_cleanup",
    trigger: "disk free 9%",
    consent: "auto",
    outcome: "executed_ok",
    durationMs: 4120,
    findingFingerprint: null,
    advisor: { source: "appleFM", recommendation: "proceed", confidence: 0.82, rationale: "ok", latencyMs: 740 },
    ...over,
  };
}

function finding(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    schema: "heald.findings/v1",
    machineId: "node-a",
    fingerprint: "crash:Finder:EXC_BAD_ACCESS",
    category: "crash",
    component: "Finder",
    severity: "warning",
    count: 12,
    status: "open",
    recurrenceCount: 0,
    linkedAction: "app_restart",
    firstSeen: "2026-11-21T08:00:00Z",
    lastSeen: "2026-11-21T09:00:00Z",
    sources: ["crash_report"],
    sample: "Finder crashed",
    ...over,
  };
}

const rejects = (r: ReturnType<typeof validateHealReport>, reason: string) =>
  assert.deepEqual(r, { ok: false, reason });

test("F1 heal string caps: id/machineId ≤128, action/healdVersion ≤64, trigger ≤500", () => {
  const vh = (o: Record<string, unknown>) => validateHealReport(heal(o), NOW);
  assert.deepEqual(vh({ id: "i".repeat(128) }), { ok: true });
  rejects(vh({ id: "i".repeat(129) }), "id too long");
  rejects(vh({ machineId: "m".repeat(129) }), "machineId too long");
  rejects(vh({ action: "a".repeat(65) }), "action too long");
  rejects(vh({ healdVersion: "v".repeat(65) }), "healdVersion too long");
  rejects(vh({ trigger: "t".repeat(501) }), "trigger too long");
  rejects(vh({ findingFingerprint: "f".repeat(129) }), "findingFingerprint too long");
  rejects(vh({ id: 42 }), "invalid id");
});

test("F1 heal consent enum, numeric fields finite, ts ISO ≤40 and parseable", () => {
  const vh = (o: Record<string, unknown>) => validateHealReport(heal(o), NOW);
  rejects(vh({ consent: "always" }), "invalid consent");
  rejects(vh({ durationMs: "fast" }), "invalid durationMs");
  rejects(vh({ durationMs: Infinity }), "invalid durationMs");
  rejects(vh({ ts: "not a date" }), "invalid ts");
  rejects(vh({ ts: "2026-11-21T09:00:00Z" + " ".repeat(30) }), "invalid ts");
  rejects(vh({ ts: undefined }), "missing ts");
});

test("F1 heal advisor must be an object with enum source + recommendation", () => {
  const vh = (o: Record<string, unknown>) => validateHealReport(heal(o), NOW);
  rejects(vh({ advisor: undefined }), "missing advisor");
  rejects(vh({ advisor: "proceed" }), "invalid advisor");
  const adv = (a: Record<string, unknown>) =>
    vh({ advisor: { source: "rules", recommendation: "skip", confidence: 0.1, rationale: "r", latencyMs: 1, ...a } });
  assert.deepEqual(adv({}), { ok: true });
  rejects(adv({ source: "gpt" }), "invalid advisor.source");
  rejects(adv({ recommendation: "yolo" }), "invalid advisor.recommendation");
  rejects(adv({ confidence: Number.NaN }), "invalid advisor.confidence");
  rejects(adv({ latencyMs: "1" }), "invalid advisor.latencyMs");
  rejects(adv({ rationale: "r".repeat(501) }), "advisor.rationale too long");
});

test("F1 finding caps: fingerprint ≤128, category/component/linkedAction ≤64, sample ≤400, sources ≤20×256", () => {
  const vf = (o: Record<string, unknown>) => validateFinding(finding(o), NOW);
  assert.deepEqual(vf({}), { ok: true });
  rejects(vf({ fingerprint: "f".repeat(129) }), "fingerprint too long");
  rejects(vf({ category: "c".repeat(65) }), "category too long");
  rejects(vf({ component: "c".repeat(65) }), "component too long");
  rejects(vf({ linkedAction: "l".repeat(65) }), "linkedAction too long");
  assert.deepEqual(vf({ linkedAction: null }), { ok: true });
  rejects(vf({ sample: "s".repeat(401) }), "sample too long");
  rejects(vf({ sources: Array.from({ length: 21 }, () => "x") }), "too many sources");
  rejects(vf({ sources: ["s".repeat(257)] }), "invalid sources");
  rejects(vf({ sources: "crash" }), "invalid sources");
});

test("F1 finding severity enum, numeric fields finite, dates ISO", () => {
  const vf = (o: Record<string, unknown>) => validateFinding(finding(o), NOW);
  rejects(vf({ severity: "meh" }), "invalid severity");
  rejects(vf({ severity: undefined }), "missing severity");
  rejects(vf({ count: "12" }), "invalid count");
  rejects(vf({ recurrenceCount: Number.POSITIVE_INFINITY }), "invalid recurrenceCount");
  rejects(vf({ firstSeen: "yesterday" }), "invalid firstSeen");
  rejects(vf({ lastSeen: 5 }), "invalid lastSeen");
});

test("F6 heal ts / finding lastSeen more than 24 h in the future is rejected", () => {
  const in23h = new Date(NOW + 23 * 3600_000).toISOString();
  const in25h = new Date(NOW + 25 * 3600_000).toISOString();
  assert.deepEqual(validateHealReport(heal({ ts: in23h }), NOW), { ok: true });
  rejects(validateHealReport(heal({ ts: in25h }), NOW), "ts in the future");
  assert.deepEqual(validateFinding(finding({ lastSeen: in23h }), NOW), { ok: true });
  rejects(validateFinding(finding({ lastSeen: in25h }), NOW), "lastSeen in the future");
});

test("F1 ingestBody stores only a projection of known fields", () => {
  const r = ingestBody(
    {
      heals: [heal({ evil: "x".repeat(10_000), advisor: { source: "rules", recommendation: "defer", confidence: 1, rationale: "r", latencyMs: 2, extra: 1 } })],
      findings: [finding({ junk: { deep: true } })],
    },
    NOW,
  );
  assert.equal(r.status, 200);
  if (r.status !== 200) return;
  const h = r.heals[0] as HealReport & Record<string, unknown>;
  assert.equal("evil" in h, false);
  assert.equal("extra" in (h.advisor as unknown as Record<string, unknown>), false);
  assert.equal(h.action, "disk_cleanup");
  const f = r.findings[0] as Finding & Record<string, unknown>;
  assert.equal("junk" in f, false);
  assert.deepEqual(f.sources, ["crash_report"]);
});

test("F1 batch cap: >500 heals / findings per request -> excess rejected and counted", () => {
  assert.equal(MAX_BATCH, 500);
  const heals = Array.from({ length: 502 }, (_, i) => heal({ id: `h${i}` }));
  const findings = Array.from({ length: 501 }, (_, i) => finding({ fingerprint: `fp${i}` }));
  const r = ingestBody({ heals, findings }, NOW);
  assert.deepEqual(r.json, {
    ok: true,
    heals: { accepted: 500, rejected: 2 },
    findings: { accepted: 500, rejected: 1 },
  });
  assert.ok(r.status === 200 && r.heals.length === 500 && r.findings.length === 500);
});
