# Protocol Invariant Catalogue

## Overview

This document defines protocol-wide invariants that must always hold true.

Invariant testing validates these properties throughout protocol execution.

---

# Claims

## INV-CLAIM-001

Claim IDs are unique.

## INV-CLAIM-002

Claim state transitions cannot regress.

## INV-CLAIM-003

Terminal claim states are immutable.

## INV-CLAIM-004

Claim settlement occurs only once.

---

# Treasury

## INV-TREASURY-001

Treasury balances are never negative.

## INV-TREASURY-002

Accounting always reconciles.

## INV-TREASURY-003

No funds are created unexpectedly.

## INV-TREASURY-004

Every transfer is recorded consistently.

---

# Rewards

## INV-REWARD-001

Rewards never exceed treasury balance.

## INV-REWARD-002

Duplicate rewards are impossible.

## INV-REWARD-003

Reward calculations are deterministic.

---

# Staking

## INV-STAKE-001

Locked stake cannot disappear.

## INV-STAKE-002

Withdrawals cannot exceed deposited stake.

## INV-STAKE-003

Slash accounting remains consistent.

## INV-STAKE-004

Total stake equals the sum of all active stakes.

---

# Governance

## INV-GOV-001

Only authorized governance may execute privileged actions.

## INV-GOV-002

Timelocks are always enforced.

## INV-GOV-003

Proposal execution occurs at most once.

## INV-GOV-004

Voting power calculation is deterministic.

---

# Reputation

## INV-REP-001

Reputation remains within defined bounds.

## INV-REP-002

Reputation updates are deterministic.

## INV-REP-003

Expired reputation cannot influence protocol decisions.

---

# Settlement

## INV-SETTLE-001

Settlement is deterministic.

## INV-SETTLE-002

Settlement cannot execute twice.

## INV-SETTLE-003

Reward allocation matches settlement outcome.

---

# Cross-Module Invariants

## INV-CROSS-001

Treasury accounting remains consistent after settlement.

## INV-CROSS-002

Reward distribution preserves treasury conservation.

## INV-CROSS-003

Governance upgrades preserve storage layout.

## INV-CROSS-004

Emergency controls do not violate accounting invariants.

---

# Validation Strategy

These invariants are validated using:

- Foundry invariant tests
- Stateful fuzz testing
- Unit tests
- Integration tests
- Static analysis
- Manual review

Any invariant violation blocks a production release until resolved.