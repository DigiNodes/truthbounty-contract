#!/usr/bin/env node
/**
 * @file check-contract-budgets.mjs
 * @issue PREWAVE-SC-009
 * @description Contract size, gas and calldata budget gate for the canonical
 * V2 operations (claim, commit, reveal, dispute, appeal, settlement, rewards,
 * governance, pause).
 *
 * Gate contract (fails closed on missing, malformed or ambiguous input):
 *  1. Every required operation has a reviewed gas ceiling and calldata ceiling.
 *  2. Gas ceilings never exceed config/gas-budgets.json nor its tx gas ceiling.
 *  3. Worst-case calldata is derived from the declared ABI word model and the
 *     bounds in config/gas-budgets.json, and must fit the reviewed ceiling and
 *     the policy cap (oversized calldata boundary).
 *  4. Every deployment size budget stays below the EIP-170 network limit.
 *  5. Any increase over config/contract-budget-baseline.json needs a matching
 *     entry in `overrides` with a rationale and reviewer; unmatched overrides
 *     fail so stale rationale cannot linger.
 *  6. Evidence (commit, config hashes, derived values) is written to
 *     deployments/releases/contract-budget-evidence.json.
 *
 * Usage:
 *   node scripts/check-contract-budgets.mjs
 *   node scripts/check-contract-budgets.mjs --write-baseline
 */
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
export const REQUIRED_OPERATIONS = [
  "claim",
  "commit",
  "reveal",
  "dispute",
  "appeal",
  "settlement",
  "rewards",
  "governance",
  "pause",
];
const MIN_RATIONALE_LENGTH = 20;

const isPositiveInt = (v) => Number.isSafeInteger(v) && v > 0;
const isNonNegativeInt = (v) => Number.isSafeInteger(v) && v >= 0;
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

/** Worst-case calldata bytes for an operation under the static ABI word model. */
export function deriveCalldataBytes(model, calldata, bounds) {
  const bound = calldata.boundKey === null ? 0 : bounds[calldata.boundKey];
  if (calldata.boundKey !== null && !isPositiveInt(bound)) {
    throw new Error(`unknown or invalid bound ${calldata.boundKey}`);
  }
  const words =
    calldata.fixedWords +
    calldata.dynamicArrays * model.dynamicArrayOverheadWords +
    calldata.perItemWords * bound;
  return model.selectorBytes + words * model.wordBytes;
}

/** Validates budgets and returns { errors, derived }. Never throws on bad input. */
export function validateBudgets({ budgets, gas, sizes, baseline }) {
  const errors = [];
  const derived = {};
  if (!isObject(budgets) || !isObject(budgets.operations)) {
    return { errors: ["contract budgets: operations must be an object"], derived };
  }
  if (!isObject(gas) || !isObject(gas.budgets) || !isObject(gas.bounds) || !isPositiveInt(gas.recommendedTxGasCeiling)) {
    return { errors: ["gas budgets: budgets, bounds and recommendedTxGasCeiling are required"], derived };
  }
  const model = budgets.calldataModel;
  if (
    !isObject(model) ||
    !isPositiveInt(model.selectorBytes) ||
    !isPositiveInt(model.wordBytes) ||
    !isNonNegativeInt(model.dynamicArrayOverheadWords) ||
    !isPositiveInt(model.policyCapBytes)
  ) {
    return { errors: ["contract budgets: calldataModel is missing or malformed"], derived };
  }

  for (const name of Object.keys(budgets.operations)) {
    if (!REQUIRED_OPERATIONS.includes(name)) errors.push(`${name}: unknown operation`);
  }
  for (const name of REQUIRED_OPERATIONS) {
    const op = budgets.operations[name];
    if (!isObject(op) || !isObject(op.calldata)) {
      errors.push(`${name}: missing operation budget`);
      continue;
    }
    const limit = gas.budgets[op.gasBudgetKey];
    if (!isPositiveInt(limit)) {
      errors.push(`${name}: gasBudgetKey ${op.gasBudgetKey} not found in gas budgets`);
    } else if (!isPositiveInt(op.maxGas)) {
      errors.push(`${name}: maxGas must be a positive integer`);
    } else if (op.maxGas > limit) {
      errors.push(`${name}: maxGas ${op.maxGas} exceeds gas budget ${op.gasBudgetKey}=${limit}`);
    }
    if (isPositiveInt(op.maxGas) && op.maxGas > gas.recommendedTxGasCeiling) {
      errors.push(`${name}: maxGas ${op.maxGas} exceeds transaction gas ceiling ${gas.recommendedTxGasCeiling}`);
    }
    const cd = op.calldata;
    if (![cd.fixedWords, cd.dynamicArrays, cd.perItemWords].every(isNonNegativeInt) || !isPositiveInt(cd.maxBytes)) {
      errors.push(`${name}: calldata model is malformed`);
      continue;
    }
    if (cd.perItemWords > 0 && cd.boundKey === null) {
      errors.push(`${name}: per-item calldata requires a boundKey`);
      continue;
    }
    let bytes;
    try {
      bytes = deriveCalldataBytes(model, cd, gas.bounds);
    } catch (error) {
      errors.push(`${name}: ${error.message}`);
      continue;
    }
    if (bytes > cd.maxBytes) errors.push(`${name}: worst-case calldata ${bytes}B exceeds reviewed ceiling ${cd.maxBytes}B`);
    if (cd.maxBytes > model.policyCapBytes) errors.push(`${name}: calldata ceiling ${cd.maxBytes}B exceeds policy cap ${model.policyCapBytes}B`);
    derived[name] = { maxGas: op.maxGas, maxCalldataBytes: cd.maxBytes, derivedCalldataBytes: bytes };
  }

  const limitBytes = sizes?.networkLimitBytes;
  if (!isPositiveInt(limitBytes) || !isObject(sizes?.contracts)) {
    errors.push("size budgets: networkLimitBytes and contracts are required");
  } else {
    for (const [name, c] of Object.entries(sizes.contracts)) {
      if (!isPositiveInt(c?.hardLimitBytes) || c.hardLimitBytes > limitBytes) {
        errors.push(`${name}: hardLimitBytes must be a positive value within the ${limitBytes}B network limit`);
      }
    }
  }

  errors.push(...checkRegressions(budgets, derived, baseline));
  return { errors, derived };
}

const FIELDS = ["maxGas", "maxCalldataBytes"];

/** Increases over the baseline must be covered by exactly one reviewed override. */
export function checkRegressions(budgets, derived, baseline) {
  if (!isObject(baseline) || !isObject(baseline.operations)) {
    return ["baseline: missing or malformed (run with --write-baseline after review)"];
  }
  const errors = [];
  const overrides = Array.isArray(budgets.overrides) ? budgets.overrides : [];
  const used = new Set();
  for (const name of REQUIRED_OPERATIONS) {
    const previous = baseline.operations[name];
    const current = derived[name];
    if (!current) continue;
    if (!isObject(previous)) {
      errors.push(`${name}: missing from baseline`);
      continue;
    }
    for (const field of FIELDS) {
      if (current[field] <= previous[field]) continue;
      const index = overrides.findIndex(
        (o) => o?.operation === name && o.field === field && o.from === previous[field] && o.to === current[field],
      );
      if (index === -1) {
        errors.push(`${name}.${field}: ${previous[field]} -> ${current[field]} regression has no reviewed override`);
        continue;
      }
      used.add(index);
      const o = overrides[index];
      if (typeof o.rationale !== "string" || o.rationale.trim().length < MIN_RATIONALE_LENGTH) {
        errors.push(`${name}.${field}: override rationale must be at least ${MIN_RATIONALE_LENGTH} characters`);
      }
      if (typeof o.reviewer !== "string" || !o.reviewer.trim()) {
        errors.push(`${name}.${field}: override requires a reviewer`);
      }
    }
  }
  overrides.forEach((o, index) => {
    if (!used.has(index)) errors.push(`override #${index} (${o?.operation}.${o?.field}) does not match any regression`);
  });
  return errors;
}

const sha256 = (text) => createHash("sha256").update(text).digest("hex");

function gitSha() {
  try {
    return execFileSync("git", ["rev-parse", "HEAD"], { cwd: REPO_ROOT, encoding: "utf8" }).trim();
  } catch {
    return null;
  }
}

function main() {
  const files = {
    budgets: "config/contract-budgets.json",
    gas: "config/gas-budgets.json",
    sizes: "config/deployment-size-budgets.json",
    baseline: "config/contract-budget-baseline.json",
  };
  const texts = {};
  const parsed = {};
  for (const [key, rel] of Object.entries(files)) {
    try {
      texts[key] = readFileSync(resolve(REPO_ROOT, rel), "utf8");
      parsed[key] = JSON.parse(texts[key]);
    } catch (error) {
      console.error(`[PREWAVE-SC-009] cannot read ${rel}: ${error.message}`);
      process.exit(1);
    }
  }

  if (process.argv.includes("--write-baseline")) {
    const { derived } = validateBudgets({ ...parsed, baseline: { operations: {} } });
    const operations = Object.fromEntries(
      Object.entries(derived).map(([name, d]) => [name, { maxGas: d.maxGas, maxCalldataBytes: d.maxCalldataBytes }]),
    );
    writeFileSync(resolve(REPO_ROOT, files.baseline), `${JSON.stringify({ schemaVersion: 1, operations }, null, 2)}\n`);
    console.log("[PREWAVE-SC-009] baseline written; review the diff before committing.");
    return;
  }

  const { errors, derived } = validateBudgets(parsed);
  const outDir = resolve(REPO_ROOT, "deployments/releases");
  mkdirSync(outDir, { recursive: true });
  const evidence = {
    schemaVersion: 1,
    issue: "PREWAVE-SC-009",
    gitSha: gitSha(),
    toolchain: parsed.gas.toolchain ?? null,
    inputHashes: Object.fromEntries(Object.entries(texts).map(([k, t]) => [files[k], sha256(t)])),
    passed: errors.length === 0,
    errors,
    operations: derived,
    feeContext: parsed.budgets.feeContext ?? null,
  };
  writeFileSync(resolve(outDir, "contract-budget-evidence.json"), `${JSON.stringify(evidence, null, 2)}\n`);
  if (errors.length > 0) {
    for (const error of errors) console.error(`[PREWAVE-SC-009] ${error}`);
    process.exit(1);
  }
  console.log(`[PREWAVE-SC-009] ${REQUIRED_OPERATIONS.length} operation budgets verified.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
