import { test } from "node:test";
import assert from "node:assert/strict";
import {
  validateHealReport,
  validateFinding,
  applyHeals,
  applyFindings,
  clampLimit,
  MAX_HEALS,
  MAX_FINDINGS_PER_MACHINE,
  type HealReport,
  type Finding,
} from "./heal-report.ts";

function heal(over: Partial<HealReport> = {}): HealReport {
  return {
    schema: "heald.heal_report/v1",
    id: "7f0c-0001",
    machineId: "409C591A-node-a",
    ts: "2026-11-21T09:00:00Z",
    healdVersion: "3.6.0",
    action: "disk_cleanup",
    trigger: "disk free 9%",
    consent: "auto",
    outcome: "executed_ok",
    durationMs: 4120,
    findingFingerprint: null,
    advisor: {
      source: "appleFM",
      recommendation: "proceed",
      confidence: 0.82,
      rationale: "Root volume under 10 % free.",
      latencyMs: 740,
    },
    ...over,
  };
}

function finding(over: Partial<Finding> = {}): Finding {
  return {
    schema: "heald.findings/v1",
    machineId: "409C591A-node-a",
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
    ...over,
  };
}

// (a)
test("(a) valid v1 heal is accepted", () => {
  assert.deepEqual(validateHealReport(heal()), { ok: true });
});

// (b)
test("(b) unknown heal schema is rejected", () => {
  assert.deepEqual(validateHealReport(heal({ schema: "heald.heal_report/v2" as HealReport["schema"] })), {
    ok: false,
    reason: "unknown schema",
  });
});

test("heal missing id / machineId / action / outcome is rejected with a reason", () => {
  for (const field of ["id", "machineId", "action", "outcome"] as const) {
    const h = heal() as unknown as Record<string, unknown>;
    delete h[field];
    const r = validateHealReport(h);
    assert.equal(r.ok, false, field);
    assert.equal(r.ok === false && r.reason, `missing ${field}`);
  }
});

test("heal that is not an object is rejected", () => {
  assert.deepEqual(validateHealReport(null), { ok: false, reason: "not an object" });
  assert.deepEqual(validateHealReport("x"), { ok: false, reason: "not an object" });
});

test("heal with unknown outcome is rejected", () => {
  const r = validateHealReport(heal({ outcome: "exploded" as HealReport["outcome"] }));
  assert.deepEqual(r, { ok: false, reason: "invalid outcome" });
});

// (e)
test("(e) heal detail of 4001 chars is rejected, 4000 accepted", () => {
  assert.deepEqual(validateHealReport(heal({ detail: "x".repeat(4001) })), {
    ok: false,
    reason: "detail too long",
  });
  assert.deepEqual(validateHealReport(heal({ detail: "x".repeat(4000) })), { ok: true });
});

test("valid v1 finding is accepted", () => {
  assert.deepEqual(validateFinding(finding()), { ok: true });
});

test("finding with unknown schema is rejected", () => {
  assert.deepEqual(validateFinding(finding({ schema: "heald.findings/v2" as Finding["schema"] })), {
    ok: false,
    reason: "unknown schema",
  });
});

test("finding missing fingerprint / machineId / status is rejected with a reason", () => {
  for (const field of ["fingerprint", "machineId", "status"] as const) {
    const f = finding() as unknown as Record<string, unknown>;
    delete f[field];
    const r = validateFinding(f);
    assert.equal(r.ok, false, field);
    assert.equal(r.ok === false && r.reason, `missing ${field}`);
  }
});

test("finding with invalid status is rejected", () => {
  assert.deepEqual(validateFinding(finding({ status: "gone" as Finding["status"] })), {
    ok: false,
    reason: "invalid status",
  });
});

test("finding detail of 4001 chars is rejected", () => {
  assert.deepEqual(validateFinding(finding({ detail: "x".repeat(4001) })), {
    ok: false,
    reason: "detail too long",
  });
});

// (c)
test("(c) duplicate heal id (daemon retry) is stored once", () => {
  const bucket = applyHeals([], [heal()]);
  const again = applyHeals(bucket, [heal()]);
  assert.equal(again.length, 1);
});

test("applyHeals sorts newest first and caps at MAX_HEALS", () => {
  const sorted = applyHeals([], [
    heal({ id: "old", ts: "2026-11-01T00:00:00Z" }),
    heal({ id: "new", ts: "2026-11-21T00:00:00Z" }),
    heal({ id: "mid", ts: "2026-11-10T00:00:00Z" }),
  ]);
  assert.deepEqual(sorted.map((h) => h.id), ["new", "mid", "old"]);

  const many = Array.from({ length: MAX_HEALS + 10 }, (_, i) =>
    heal({ id: `h${i}`, ts: new Date(Date.UTC(2026, 0, 1) + i * 1000).toISOString() }),
  );
  const capped = applyHeals([], many);
  assert.equal(MAX_HEALS, 5000);
  assert.equal(capped.length, 5000);
  assert.equal(capped[0].id, `h${MAX_HEALS + 9}`);
});

test("applyHeals does not mutate its input bucket", () => {
  const bucket = applyHeals([], [heal()]);
  applyHeals(bucket, [heal({ id: "other" })]);
  assert.equal(bucket.length, 1);
});

// (f)
test("(f) clampLimit clamps to 1..500", () => {
  assert.equal(clampLimit(0), 1);
  assert.equal(clampLimit(10000), 500);
  assert.equal(clampLimit(42), 42);
  assert.equal(clampLimit(Number.NaN), 50);
  assert.equal(clampLimit("7"), 7);
  assert.equal(clampLimit(null), 50);
  assert.equal(clampLimit("abc"), 50);
});

// (h)
test("(h) open then fixed finding with same fingerprint -> 1 entry, status fixed", () => {
  const open = applyFindings([], [finding({ status: "open" })]);
  const fixed = applyFindings(open, [finding({ status: "fixed", lastSeen: "2026-11-21T10:00:00Z" })]);
  assert.equal(fixed.length, 1);
  assert.equal(fixed[0].status, "fixed");
});

test("applyFindings keys by (machineId, fingerprint)", () => {
  const out = applyFindings([], [
    finding({ machineId: "node-a" }),
    finding({ machineId: "node-b" }),
    finding({ machineId: "node-a", fingerprint: "panic:kernel" }),
  ]);
  assert.equal(out.length, 3);
});

test("applyFindings caps at MAX_FINDINGS_PER_MACHINE per machine, keeping newest", () => {
  const many = Array.from({ length: MAX_FINDINGS_PER_MACHINE + 5 }, (_, i) =>
    finding({
      fingerprint: `fp${i}`,
      lastSeen: new Date(Date.UTC(2026, 0, 1) + i * 1000).toISOString(),
    }),
  );
  const out = applyFindings([finding({ machineId: "node-b" })], many);
  assert.equal(MAX_FINDINGS_PER_MACHINE, 500);
  assert.equal(out.filter((f) => f.machineId === "409C591A-node-a").length, 500);
  assert.equal(out.filter((f) => f.machineId === "node-b").length, 1);
  assert.ok(!out.some((f) => f.fingerprint === "fp0"));
});
