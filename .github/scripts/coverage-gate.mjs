// V2-SC-089: fail CI when branch coverage of a security-critical contract
// drops below its committed baseline in config/coverage-baseline.json.
// Lowering a baseline is only possible by editing that file in the PR, so
// any regression is visible to reviewers instead of passing silently.
//
// Usage: node .github/scripts/coverage-gate.mjs <lcov.info> <coverage-baseline.json>
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const SCHEMA_VERSION = 1;
// Baselines are stored with two decimals; ignore differences below that.
const EPSILON = 0.005;

const normalizePath = (path) => path.trim().replace(/\\/g, "/").replace(/^\.\//, "");

/** Parses lcov text into a map of source path -> { found, hit } branch counts. */
export function parseLcov(text) {
  const files = new Map();
  let current = null;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (line.startsWith("SF:")) {
      current = normalizePath(line.slice(3));
      files.set(current, { found: 0, hit: 0 });
    } else if (current && line.startsWith("BRF:")) {
      files.get(current).found = Number(line.slice(4));
    } else if (current && line.startsWith("BRH:")) {
      files.get(current).hit = Number(line.slice(4));
    } else if (line === "end_of_record") {
      current = null;
    }
  }
  return files;
}

/** Validates the baseline config, throwing on anything malformed (fail closed). */
export function validateBaseline(baseline) {
  if (!baseline || typeof baseline !== "object") throw new Error("baseline must be a JSON object");
  if (baseline.schemaVersion !== SCHEMA_VERSION) {
    throw new Error(`unsupported baseline schemaVersion ${baseline.schemaVersion}, expected ${SCHEMA_VERSION}`);
  }
  const entries = Object.entries(baseline.files ?? {});
  if (entries.length === 0) throw new Error("baseline.files must list at least one contract");
  for (const [path, min] of entries) {
    if (typeof min !== "number" || !Number.isFinite(min) || min < 0 || min > 100) {
      throw new Error(`baseline for ${path} must be a number between 0 and 100, got ${JSON.stringify(min)}`);
    }
  }
  return entries.map(([path, min]) => [normalizePath(path), min]);
}

/** Returns one failure message per contract below its baseline or missing from the report. */
export function checkCoverage(lcovFiles, baseline) {
  const failures = [];
  for (const [path, min] of validateBaseline(baseline)) {
    const counts = lcovFiles.get(path);
    if (!counts) {
      failures.push(`${path}: missing from coverage report (baseline ${min}%)`);
      continue;
    }
    const pct = counts.found === 0 ? 100 : (counts.hit / counts.found) * 100;
    if (pct + EPSILON < min) {
      failures.push(`${path}: branch coverage ${pct.toFixed(2)}% is below baseline ${min}% (${counts.hit}/${counts.found})`);
    }
  }
  return failures;
}

async function main([lcovPath, baselinePath]) {
  if (!lcovPath || !baselinePath) {
    throw new Error("usage: coverage-gate.mjs <lcov.info> <coverage-baseline.json>");
  }
  const lcovFiles = parseLcov(await readFile(lcovPath, "utf8"));
  const baseline = JSON.parse(await readFile(baselinePath, "utf8"));
  const failures = checkCoverage(lcovFiles, baseline);
  if (failures.length > 0) {
    console.error("Branch coverage regression on security-critical contracts:");
    for (const failure of failures) console.error(`  - ${failure}`);
    console.error(`If a drop is intentional, lower the baseline in ${baselinePath} and explain why in the PR.`);
    process.exit(1);
  }
  console.log(`Branch coverage gate passed for ${Object.keys(baseline.files).length} security-critical contract(s).`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(`coverage gate error: ${error.message}`);
    process.exit(1);
  });
}
