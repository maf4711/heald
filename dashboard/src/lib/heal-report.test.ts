import { test } from "node:test";
import assert from "node:assert/strict";
import {
  validateHealReport,
  validateFinding,
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
