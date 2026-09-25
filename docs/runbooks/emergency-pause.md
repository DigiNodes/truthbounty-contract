# Emergency Pause Runbook

## Purpose

This runbook defines the authoritative operational procedure for activating, verifying, and monitoring emergency pause states across the TruthBounty protocol. It governs both the multi-level circuit breaker framework (`EmergencyController.sol`) and the scoped V2 module controls (`EmergencyControls.sol`).

---

## Authority & Separation of Powers

The protocol enforces strict separation of powers across distinct administrative roles:

| Role | Authorized Address / Actor | Activation Powers | Lifting Powers | Security Invariants |
|---|---|---|---|---|
| **EMERGENCY_COUNCIL** | Multi-sig / rapid response key | Levels 1, 2, 3 (or any V2 scope) | **NONE (Cannot lift pause)** | Rapid response only; cannot unilaterally resume operations |
| **DAO_GOVERNANCE** | Governor + Timelock | Levels 1, 2 (or any V2 scope) | **Full lifting authority** | Formal governance consensus required to lift any pause |
| **TIMELOCK_CONTROLLER** | Governance Timelock contract | Level 1 only (HighRisk) | **NONE** | Subject to mandatory `timelockCooldown` (default 1 hour) |
| **RECOVERY_EXECUTOR** | Designated operational role | None (execution only) | Stepwise recovery | Must execute post-lift verification steps (1 → 2 → 3) |

---

## Multi-Level Circuit Breaker Matrix

The protocol supports four tiered operational levels:

### Level 0 — Normal
- **Description:** Full protocol operations.
- **Allowed Operations:** All claims, evidence, verifications, staking, disputes, treasury, and withdrawals.
- **Recovery Status:** `recoveryComplete == true`.

### Level 1 — HighRisk
- **Description:** Halts high-risk protocol mutations when suspect activity, oracle drift, or verification anomalies are detected.
- **Blocked Operations:**
  - `claim_creation`
  - `staking`
  - `verification_submission`
- **Permitted Operations:**
  - Treasury movements and reward distributions
  - Withdrawals
  - All read-only state queries
  - Governance proposals and timelock executions

### Level 2 — Financial
- **Description:** Halts all value transfers and financial movements in addition to Level 1 restrictions when fund drain risk or invariant violation is suspected.
- **Blocked Operations:**
  - All Level 1 blocked operations
  - `reward_distribution`
  - `treasury_transfer`
  - `withdrawal`
- **Permitted Operations:**
  - Read-only queries
  - Governance recovery actions

### Level 3 — Shutdown
- **Description:** Global emergency lockdown.
- **Blocked Operations:**
  - All standard protocol mutations and user actions.
- **Permitted Operations:**
  - `governance_recovery` calls authorized by DAO governance.

---

## Trigger Procedures

### 1. Emergency Council Rapid Activation (Levels 1–3)

1. Verify the incident nature and select the appropriate pause level.
2. Formulate an immutable on-chain reason and governance tracking reference:
   ```solidity
   emergencyController.activatePause(
       level,              // 1, 2, or 3
       "Reason string",    // e.g. "Oracle discrepancy in verification round"
       proposalRef         // keccak256("INCIDENT-YYYY-MM-DD-001")
   );
   ```
3. For canonical V2 module-scoped emergencies:
   ```solidity
   emergencyControls.pause(scope); // e.g. SCOPE_CLAIMS, SCOPE_TREASURY, or SCOPE_ALL
   ```

### 2. Timelock Controller Activation (Level 1)

1. Timelock initiates `activatePause(LEVEL_HIGH_RISK, reason, proposalRef)`.
2. Must verify that `block.timestamp >= lastTimelockActivation + timelockCooldown`.

---

## Verification & Monitoring

Immediately following pause activation, on-call operators must execute the following checks:

1. **Verify On-Chain Pause Level:**
   ```bash
   cast call $EMERGENCY_CONTROLLER "getPauseLevel()(uint8)"
   ```
   *Expected:* Returns target level (1, 2, or 3).

2. **Verify Audit Trail Registration:**
   ```bash
   cast call $EMERGENCY_CONTROLLER "getEmergencyHistoryCount()(uint256)"
   ```
   Query the latest record via `getEmergencyHistory(start, count)` to ensure initiator, reason, and proposal reference are immutably logged.

3. **Verify Operation Freezing:**
   Simulate restricted transactions via `eth_call`:
   - High-risk operations must revert with `OperationPaused(operationType, level)`.
   - Financial withdrawals must revert when level ≥ 2.

4. **Confirm Read Integrity:**
   Ensure read calls (e.g. balance queries, claim state, parameter queries) succeed without disruption.

---

## Post-Pause Recovery Handoff

Once the pause is active and state is frozen:
1. Initiate the **Emergency Recovery and Unpause Drill Runbook** (`docs/runbooks/emergency-drills.md`).
2. Convene DAO Governance and Security Council to diagnose root cause.
3. Prepare timelocked configuration repairs or module upgrades before lifting.