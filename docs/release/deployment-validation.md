# Deployment Validation

## Purpose

This document defines the deployment verification steps required before a production release.

## Automated Validation

The deployment verification script validates:

- Contract deployment addresses
- Token configuration
- Oracle configuration
- Staking configuration
- Claims configuration
- Migration manager verification

## Source Publication Verification

Source publication is driven exclusively from the pinned canonical build inputs bound to the release manifest. No argument is passed by manual editing or by an operator-supplied override.

The verification harness automates source verification for every deployed address across all contract roles:

- Proxy contracts
- Implementation contracts
- Linked librarier
- Constructor arguments

For each address the harness resolves the canonical source and compiler settings from the manifest and submits them to the explorer verification endpoint. The explorer response is recorded as evidence, along with any fallback evidence produced when the explorer endpoint is unavailable or rejects the submission.

Explorer success is not treated as evidence of code correctness. It only confirms that the published source matches the deployed bytecode under the recorded settings. Correctness is established by the build, audit, and test gates defined elsewhere in the release process.

## Required Tests

The source publication harness is covered by:

- Linked library verification.
- Proxy constructor verification.
- Flattened-source rejection.
- Wrong compiler settings rejection.
- Already-verified address handling.

## Failure Handling

A failed verification must produce an actionable diagnostic identifying the address, the role, the expected canonical inputs, and the observed response. Retries must be safe: re-running the harness against the same manifest must not corrupt or duplicate evidence, and an already-verified address must be recognized and recorded without resubmitting conflicting inputs.

## Evidence Binding

All explorer responses and fallback evidence are attached to the release manifest entry for the corresponding deployed address. Evidence is keyed by address, role, and the canonical build input digest so that a release can be reviewed against the exact inputs that produced it.

## Manual Validation

Operators should additionally verify:

- Governance ownership
- Treasury ownership
- Role assignments
- Upgrade permissions
- Emergency controls
- Network configuration
- Deployment artifacts

## Release Requirement

Deployment validation, including source publication verification for every deployed address, must complete successfully before any release candidate progresses to governance approval or mainnet deployment.
