# SC-008: Reputation Update Engine

## Overview

Implements the **Reputation Update Engine** — the sole authorised mechanism for modifying verifier reputation within the protocol. Every completed claim resolution produces a transparent, deterministic, and reproducible reputation update that rewards accurate participation while penalising inaccurate or malicious behaviour.

## Changes

### New Contracts

- **`contracts/IReputationUpdateEngine.sol`** — Interface defining the reputation update API, types (`ReputationUpdate`, `ReputationUpdateRecord`, `UpdateReason` enum), events, governance parameters, and view functions.

- **`contracts/ReputationUpdateEngine.sol`** — Implementation of the reputation update engine with:
  - `updateReputation()` — Deterministic reputation mutation via `UPDATE_ROLE`-gated function
  - Duplicate prevention per `(verifier, claimId)` pair
  - Configurable deltas based on outcome reason:
    - `CORRECT_VERIFICATION`: `+rewardIncrement` (default: +10)
    - `INCORRECT_VERIFICATION`: `-penaltyAmount` (default: -10)
    - `MALICIOUS_BEHAVIOUR`: `-(penaltyAmount × maliciousMultiplier)` (default: -50)
    - `DISPUTED_CLAIM`: `±disputeAdjustment` (default: 0)
  - Reputation floor (`minimumReputationFloor`) and cap (`maximumReputationCap`) enforcement
  - Immutable update history per verifier (with paginated read)
  - Cumulative statistics: total gained, total lost, successful updates, failed verifications, malicious penalties, disputed outcomes
  - Governance-controlled parameters via `GovernanceOwnable` mixin
  - Pausable by `PAUSER_ROLE`
  - `UPDATE_ROLE` — only authorised protocol contracts may call `updateReputation()`

### New Tests

- **`test/ReputationUpdateEngine.t.sol`** — Unit tests:
  - Positive/negative/disputed/malicious updates
  - Reputation floor and cap enforcement
  - Duplicate prevention
  - Unauthorized access rejection
  - Zero-address rejection
  - Governance parameter updates
  - Update history pagination
  - Pausability lifecycle

- **`test/ReputationUpdateEngineAccess.t.sol`** — Access control and integration tests:
  - Role management (grant/revoke UPDATE_ROLE)
  - Governance controller integration
  - Multiple updates per verifier
  - History pagination edge cases

- **`test/invariant/ReputationUpdateEngineInvariant.t.sol`** — Invariant tests:
  - Reputation never drops below floor
  - Reputation never exceeds cap
  - Total gained - total lost consistency
  - Statistics consistency (updates = successful + failed + disputed + malicious)
  - Deterministic behaviour

### Architecture

```
┌─────────────────────────────────────────┐
│         TruthBountyWeighted             │
│  (settleClaim → calls updateReputation) │
└────────────────────┬────────────────────┘
                     │ UPDATE_ROLE
                     ▼
┌─────────────────────────────────────────┐
│        ReputationUpdateEngine           │
│  - Verifies authorization               │
│  - Prevents duplicates                  │
│  - Computes deltas from reason          │
│  - Enforces floor/cap                   │
│  - Records history                      │
│  - Updates statistics                   │
└─────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────┐
│         Governance Controller           │
│  (parameter updates via governance)     │
└─────────────────────────────────────────┘
```

## Security Considerations

- Only `UPDATE_ROLE` holders may mutate reputation — EOAs and external contracts are blocked
- Duplicate updates per `(verifier, claimId)` are prevented
- Reputation floor prevents underflow to negative values
- Reputation cap prevents excessive accumulation
- Integer overflow/underflow protection via checked arithmetic
- Pausability for emergency stop
- `updateReputation()` is `nonReentrant`

## Gas Benchmarks

| Operation | Gas (estimated) |
|-----------|----------------|
| Single positive update | ~45,000 |
| Single negative update | ~45,000 |
| Malicious behaviour update | ~45,000 |
| Disputed claim update | ~45,000 |
| History read (paginated) | ~10,000 + per record |

## ⛓ Dependencies

- SC-007 — Reputation Engine (consumes reputation data)
- SC-002 — Claim Lifecycle State Machine
- SC-006 — Claim Settlement Engine

## ✅ Acceptance Checklist

- [x] Reputation updates implemented
- [x] Update logic is deterministic
- [x] Positive and negative deltas supported
- [x] Duplicate updates prevented
- [x] Settlement integration designed
- [x] Historical metrics tracked
- [x] Update events emitted
- [x] Governance parameters configurable
- [x] Unit tests added
- [x] Invariant tests pass
- [x] Gas benchmarks documented
- [x] CI passes successfully
