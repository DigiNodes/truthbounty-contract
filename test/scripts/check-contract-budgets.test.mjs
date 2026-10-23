import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import { REQUIRED_OPERATIONS, checkRegressions, deriveCalldataBytes, validateBudgets } from "../../scripts/check-contract-budgets.mjs";

const load = (path) => JSON.parse(readFileSync(new URL(`../../${path}`, import.meta.url), "utf8"));
const fixture = () => ({
  budgets: load("config/contract-budgets.json"),
  gas: load("config/gas-budgets.json"),
  sizes: load("config/deployment-size-budgets.json"),
  baseline: load("config/contract-budget-baseline.json"),
});

describe("contract budget gate", () => {
  it("accepts the committed budgets and covers every required operation", () => {
    const { errors, derived } = validateBudgets(fixture());
    assert.deepEqual(errors, []);
    assert.deepEqual(Object.keys(derived).sort(), [...REQUIRED_OPERATIONS].sort());
  });

  it("derives worst-case calldata from the ABI word model and bounds", () => {
    const { budgets, gas } = fixture();
    const bytes = deriveCalldataBytes(budgets.calldataModel, budgets.operations.settlement.calldata, gas.bounds);
    assert.equal(bytes, 4 + (2 + 2 + gas.bounds.MAX_SETTLEMENT_BATCH_SIZE) * 32);
  });

  it("fails closed when an operation is missing", () => {
    const f = fixture();
    delete f.budgets.operations.pause;
    assert.match(validateBudgets(f).errors.join("\n"), /pause: missing operation budget/);
  });

  it("rejects gas ceilings above the shared gas budget", () => {
    const f = fixture();
    f.budgets.operations.claim.maxGas += 1;
    assert.match(validateBudgets(f).errors.join("\n"), /claim: maxGas .* exceeds gas budget/);
  });

  it("rejects oversized calldata beyond the reviewed ceiling and policy cap", () => {
    const f = fixture();
    f.gas.bounds.MAX_SETTLEMENT_BATCH_SIZE = 100000;
    const text = validateBudgets(f).errors.join("\n");
    assert.match(text, /settlement: worst-case calldata/);
    f.budgets.operations.settlement.calldata.maxBytes = 10_000_000;
    assert.match(validateBudgets(f).errors.join("\n"), /settlement: calldata ceiling .* exceeds policy cap/);
  });

  it("rejects unknown bounds and malformed input without throwing", () => {
    const f = fixture();
    f.budgets.operations.rewards.calldata.boundKey = "NOPE";
    assert.match(validateBudgets(f).errors.join("\n"), /rewards: unknown or invalid bound NOPE/);
    assert.ok(validateBudgets({ budgets: null, gas: {}, sizes: {}, baseline: {} }).errors.length > 0);
  });

  it("rejects size budgets above the network limit", () => {
    const f = fixture();
    const [name] = Object.keys(f.sizes.contracts);
    f.sizes.contracts[name].hardLimitBytes = f.sizes.networkLimitBytes + 1;
    assert.match(validateBudgets(f).errors.join("\n"), new RegExp(`${name}: hardLimitBytes`));
  });
});

describe("budget regressions and overrides", () => {
  const raise = () => {
    const f = fixture();
    f.gas.budgets.EMERGENCY_PAUSE += 10;
    f.budgets.operations.pause.maxGas += 10;
    return f;
  };

  it("flags an unexplained regression", () => {
    assert.match(validateBudgets(raise()).errors.join("\n"), /pause\.maxGas: 180000 -> 180010 regression has no reviewed override/);
  });

  it("accepts a regression with a reviewed override (explicit budget-override test)", () => {
    const f = raise();
    f.budgets.overrides = [
      { operation: "pause", field: "maxGas", from: 180000, to: 180010, rationale: "Extra module added to the pause fan-out.", reviewer: "security-reviewer" },
    ];
    assert.deepEqual(validateBudgets(f).errors, []);
  });

  it("rejects overrides without rationale or reviewer, and stale overrides", () => {
    const f = raise();
    f.budgets.overrides = [{ operation: "pause", field: "maxGas", from: 180000, to: 180010, rationale: "short", reviewer: "" }];
    const text = validateBudgets(f).errors.join("\n");
    assert.match(text, /rationale must be at least/);
    assert.match(text, /requires a reviewer/);
    const stale = fixture();
    stale.budgets.overrides = [{ operation: "claim", field: "maxGas", from: 1, to: 2, rationale: "x".repeat(30), reviewer: "r" }];
    assert.match(validateBudgets(stale).errors.join("\n"), /does not match any regression/);
  });

  it("fails closed without a baseline", () => {
    assert.match(checkRegressions({}, {}, null).join("\n"), /baseline: missing/);
  });
});
