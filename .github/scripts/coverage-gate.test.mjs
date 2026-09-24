// Tests for coverage-gate.mjs. Run with: node --test .github/scripts/
import { test } from "node:test";
import assert from "node:assert/strict";

import { checkCoverage, parseLcov, validateBaseline } from "./coverage-gate.mjs";

const lcov = (records) =>
  records
    .map(({ path, found, hit }) => `TN:\nSF:${path}\nBRF:${found}\nBRH:${hit}\nend_of_record`)
    .join("\n");

const baseline = (files) => ({ schemaVersion: 1, issue: "V2-SC-089", files });

test("passes when coverage meets or exceeds the baseline", () => {
  const files = parseLcov(lcov([{ path: "contracts/v2/StakeVault.sol", found: 10, hit: 8 }]));
  assert.deepEqual(checkCoverage(files, baseline({ "contracts/v2/StakeVault.sol": 80 })), []);
});

test("fails when branch coverage drops below the baseline", () => {
  const files = parseLcov(lcov([{ path: "contracts/v2/StakeVault.sol", found: 10, hit: 7 }]));
  const failures = checkCoverage(files, baseline({ "contracts/v2/StakeVault.sol": 80 }));
  assert.equal(failures.length, 1);
  assert.match(failures[0], /70\.00% is below baseline 80%/);
});

test("fails closed when a baselined contract is missing from the report", () => {
  const files = parseLcov(lcov([{ path: "contracts/Other.sol", found: 2, hit: 2 }]));
  const failures = checkCoverage(files, baseline({ "contracts/v2/StakeVault.sol": 50 }));
  assert.match(failures[0], /missing from coverage report/);
});

test("normalizes Windows and ./-prefixed paths", () => {
  const files = parseLcov(lcov([{ path: ".\\contracts\\v2\\StakeVault.sol", found: 4, hit: 4 }]));
  assert.deepEqual(checkCoverage(files, baseline({ "contracts/v2/StakeVault.sol": 100 })), []);
});

test("treats a contract with no branches as fully covered", () => {
  const files = parseLcov(lcov([{ path: "contracts/v2/libraries/V2Errors.sol", found: 0, hit: 0 }]));
  assert.deepEqual(checkCoverage(files, baseline({ "contracts/v2/libraries/V2Errors.sol": 100 })), []);
});

test("rejects an invalid baseline configuration", () => {
  assert.throws(() => validateBaseline({ schemaVersion: 2, files: { "a.sol": 1 } }), /schemaVersion/);
  assert.throws(() => validateBaseline({ schemaVersion: 1, files: {} }), /at least one contract/);
  assert.throws(() => validateBaseline({ schemaVersion: 1, files: { "a.sol": "90" } }), /between 0 and 100/);
  assert.throws(() => validateBaseline({ schemaVersion: 1, files: { "a.sol": 101 } }), /between 0 and 100/);
});
