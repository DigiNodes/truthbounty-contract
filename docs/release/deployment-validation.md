# Deployment Validation

## Purpose

This document defines the deployment verification steps required before a production release. It also defines the repeatable Optimism Sepolia rehearsal procedure for the V2 contract boundary consumed by the API and approved frontend designs.

## Scope

This validation covers the canonical deployment composition for the V2 topology on the Optimism/EVM runtime. It does not cover mainnet deployment, frontend/API implementation, or any storage-layout, role, pause, upgrade, or economic change inferred from legacy contracts.

## Pinned Inputs

All evidence must be generated from pinned artifacts and exact commits. Record the following before starting:

- Repository commit SHA (`with rev-parse HEAD`)
- Compiler version and build settings from the pinned configuration
- Contract artifact directory and artifact checksums
- Deployment manifest and its checksum
- Target chain ID and network name
- Deployer address and approved signer identity

## Automated Validation

The deployment verification script validates:

- Contract deployment addresses
- Token configuration
- Oracle configuration
- Staking configuration
- Claims configuration
- Migration manager verification
- Initial configuration block and deployment block
- Initial balances and pause state

## Manual Validation

Operators should additionally verify:

- Governance ownership
- Treasury ownership
- Role assignments
- Upgrade permissions
- Emergency controls
- Network configuration
- Deployment artifacts

## Optimism Sepolia Rehearsal

### Prerequisites

- A reproducible local fork of Optimism Sepolia at the pinned block.
- A funded deployer account on the rehearsal environment.
- The approved signer available for role transfer and timelock queuing.
- Access to the explorer verification endpoint for the target chain.

### Execution Steps

1. Checkout the pinned commit and record the commit SHA.
2. Build artifacts from the pinned configuration and record artifact checksums.
3. Execute the canonical deployment composition on the local fork.
4. Repeat the deployment on the Optimism Sepolia rehearsal environment.
5. Verify source and artifacts against the explorer.
6. Publish the manifest and record its checksum.
7. Transfer roles to the approved governance authority.8. Qeue timelocked actions and record the queue transaction hashes.
9. Revoke deployer authority and confirm no residual privileged roles remain.
10. Confirm initial configuration, balances, pause state, and deployment block.
11. Produce signed/checksummed evidence and pin the published release package for API/frontend consumption.

### Required Tests

- Fresh deployment and rerun/idempotency tests.
- Partial failure, wrong chain, wrong signer, stale artifact, and verification failure tests.
- Post-transfer unauthorized deployer tests.

### Evidence Requirements

The rehearsal must produce:

- Signed deployment transaction records with chain ID and block numbers.
- Explorer verification receipts for each deployed contract.
- The published manifest with a checksum matching the artifacts.
- Role transfer and timelock queue transaction hashes.
- Proof that the deployer retains no undocumented privileged authority.

## Fail-Closed Authority

Missing or ambiguous authority must fail closed. If any of the following cannot be unambiguously established, the rehearsal must halt and not proceed:

- The approved governance authority address.
- The approved signer identity for role transfer.
- The timelock delay and queue parameters.
- The expected deployment block and initial configuration.

## Release Requirement

Deployment validation must complete successfully before any release candidate progresses to governance approval or mainnet deployment. The API/frontend may pin the published release package only after all acceptance criteria are met:

- Exact commands reproduce the same deployment package.
- Explorer verification and manifest checksums match artifacts.
- Deployer retains no undocumented privileged authority.
- API/frontend can pin the published release package.
