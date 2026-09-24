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

test("fails when a baselined contract reports zero branches", () => {
  const files = parseLcov(lcov([{ path: "contracts/v2/StakeVault.sol", found: 0, hit: 0 }]));
  const failures = checkCoverage(files, baseline({ "contracts/v2/StakeVault.sol": 50 }));
  assert.match(failures[0], /measured no branches/);
});

test("rejects duplicate records for the same contract", () => {
  const text = lcov([
    { path: "contracts/v2/StakeVault.sol", found: 10, hit: 1 },
    { path: "contracts/v2/StakeVault.sol", found: 10, hit: 10 },
  ]);
  assert.throws(() => parseLcov(text), /duplicate record/);
});

test("rejects records with missing or malformed branch totals", () => {
  assert.throws(() => parseLcov("SF:contracts/v2/StakeVault.sol\nend_of_record"), /missing BRF or BRH/);
  assert.throws(() => parseLcov("SF:a.sol\nBRF:10\nBRH:bad\nend_of_record"), /invalid BRH/);
  assert.throws(() => parseLcov("SF:a.sol\nBRF:-1\nBRH:0\nend_of_record"), /invalid BRF/);
  assert.throws(() => parseLcov("SF:a.sol\nBRF:2\nBRH:3\nend_of_record"), /exceeds BRF/);
});

test("rejects an invalid baseline configuration", () => {
  assert.throws(() => validateBaseline({ schemaVersion: 2, files: { "a.sol": 1 } }), /schemaVersion/);
  assert.throws(() => validateBaseline({ schemaVersion: 1, files: {} }), /at least one contract/);
  assert.throws(() => validateBaseline({ schemaVersion: 1, files: { "a.sol": "90" } }), /between 0 and 100/);
  assert.throws(() => validateBaseline({ schemaVersion: 1, files: { "a.sol": 101 } }), /between 0 and 100/);
});
