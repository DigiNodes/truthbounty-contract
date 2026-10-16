# Contract Release SBOM and Provenance Attestation (V2-SC-088)

## Purpose

Every TruthBounty V2 release candidate must publish a machine-readable Software
Bill of Materials (SBOM) bound to a provenance attestation. The attestation
records:

| Field | Source |
| --- | --- |
| Dependencies | `package.json` (+ optional `foundry.lock` git submodule revs) |
| Compiler | `hardhat.config.ts` Solidity version / EVM / `viaIR` |
| Optimizer | `optimizer.enabled` and `optimizer.runs` |
| Source commit | `RELEASE_SOURCE_COMMIT` or `GITHUB_SHA` (40-char hex) |
| Artifact hashes | SHA-256 of canonical contract sources and lock/config files |
| Workflow identity | GitHub Actions repository / workflow / run id / ref |

Optimism/EVM remains authoritative. Stellar, Soroban, and Freighter runtime
dependencies are rejected (fail closed).

## Generate

```bash
export RELEASE_SOURCE_COMMIT="$(git rev-parse HEAD)"
export RELEASE_VERSION="2.0.0-rc.1"
# Optional CI identity (all-or-nothing):
# export GITHUB_REPOSITORY=DigiNodes/truthbounty-contract
# export GITHUB_WORKFLOW="Release Candidate"
# export GITHUB_RUN_ID=12345
# export GITHUB_SHA="$RELEASE_SOURCE_COMMIT"

npx hardhat run scripts/generateContractReleaseSbom.ts
# or:
npx ts-node scripts/generateContractReleaseSbom.ts
```

Output lands at
`deployments/sbom/contract-release-sbom-<version>.json`.

Schema:
[`chemas/contract-release-sbom.schema.json`](../../schemas/contract-release-sbom.schema.json).

## Fail-closed rules

- Invalid or missing 40-character source commit SHA
- Missing Solidity compiler version
- Optimizer enabled with non-positive `runs`
- Incomplete CA workflow identity (any CI var without the full set)
- `GITHUB_SHA` mismatch vs attested `sourceCommit`
- Forbidden Stellar / Soroban / Freighter packages
- Path-traversal artifact paths
- Invalid `foundry.lock` revision entries
- Placeholder `0.0.0` release versions

## Verification

```bash
npx hardhat test test/ContractReleaseSbom.test.ts

```

## Explorer Source Publication (PREWAVE-SC-031)

The SBOM above attests **what** was built. Source publication attests that the
explorer's copy of the deployed bytecode matches the canonical build inputs.
These are distinct gates: explorer verification success is **not** evidence of
code correctness.

### Scope

Automate source verification for every deployed address in the release
manifest:

- Proxy contract (ERC1967 / UUPS) + implementation contract
- Linked libraries (external libraries with deployed addresses)
- Proxy constructor arguments (initializer call data)
- Exact compiler version, EVM target, optimizer settings, and `viaIR` flag

### Canonical build inputs

Verification inputs are derived from the release SBOM and the deployment
manifest. No hand-edited arguments are accepted:

| Input | Source |
| --- | --- |
| Contract name / source path | SBOM canonical source map |
| Compiler version | `compiler.solidityVersion` from SBOM |
| EVM target | `compiler.evmVersion` from SBOM |
| Optimizer settings | `compiler.optimizer` from SBOM |
| `viaIR` | `compiler.viaIR` from SBOM |
| Constructor args | decoded from deployment transaction input data |
| Library addresses | deployment manifest library map |

The verification driver rejects any input that is not binded to the SBOM hash
recorded in the release manifest.

### Explorer providers

Explorer submission is performed through a configured provider interface. The
driver supports the following outcomes per address:

| Outcome | Meaning |
| --- | --- |
| `already-verified` | Explorer reports a matching source attestation |
| `verified ` | Explorer accepted the submission and reports a match |
| `pending` | Explorer accepted the submission and is still processing |
| `failed` | Explorer rejected the submission or reported a mismatch |
| `unavailable` | Explorer API unreachable or rate-limited |

Every outcome is recorded with the raw explorer response body (or a content
hash of it) and the request metadata so the evidence is reproducible.

### Fallback evidence

When the explorer is `unavailable` or `pending`, the driver records a
deterministic fallback evidence bundle:

- SBOM digest and release manifest digest
- Canonical compiler inputs hash
- Deployment transaction hash and block number
- Local reproduction of the expected creation code hash

Fallback evidence is additive; it never substitutes for an explorer match and it
does not constitute a correctness claim.

### Evidence binding

The verification report is written to `deployments/verification/<version>.json`
with the following top-level fields:

| Field | Description |
| --- | --- |
| `releaseVersion` | Release version from the manifest |
| `sourceCommit` | 40-char commit SHA from the manifest |
| `sbromDigest` | SHA-256 of the SBOM JSON |
| `manifestDigest` | SHA-256 of the release manifest |
| `addresses` | Per-address verification outcome + evidence |

Each address entry carries the contract role (`proxy`, `implementation`,
`"library`), the explorer outcome, the raw response digest, and the fallback
evidence digest when applicable.

### Failure handling

Failures are actionable and retry-safe:

- Every failure records a stable code (e.g. `WRONG_COMPILER`,
`FLATTENED_SOURCE_REJECTED`, `LIBRARY_LINK_MISMATCH`,
`PROXY_CONSTRUCTOR_ARGS_MISMATCH`, `ALREADY_VERIFIED_MISMATCH`)
- Retries reuse the same SBOM digest and manifest digest; no hand-edited arguments

are accepted between attempts.
- A failed address does not block verification of other addresses, but the

overall report is marked `failed` until every address reaches `verified` or
`already-verified`.

### Required tests

```bash
npx hardhat test test/ExplorerSourceVerification.test.ts
```

The test suite covers:

- Linked library verification (library address mapping and link references)
- Proxy constructor argument verification (initializer call data decoding)
- Flattened-source rejection (multi-file canonical source map enforced)
- Wrong compiler / wrong settings rejection
- Already-verified handling (idempotent resume)

### Non-goals

- Mainnet deployment
- Backend-authoritative protocol mutation
- Restoring legacy V1 as canonical
- Treating explorer verification as evidence of code correctness
