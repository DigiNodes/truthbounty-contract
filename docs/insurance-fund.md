# Protocol Insurance Fund & Loss Recovery Framework

## Overview

The `InsuranceFund` contract provides a dedicated on-chain insurance reserve designed to absorb exceptional losses, compensate eligible participants, and strengthen protocol resilience. All payouts require governance approval, and the fund remains fully auditable and segregated from normal treasury operations.

## Architecture

```
InsuranceFund
├── Claims Pipeline       — SUBMITTED → INVESTIGATING → REVIEW → APPROVED → PAID
├── Funding Registry      — Tracks contributions by source & history
├── Coverage Categories   — SMART_CONTRACT_FAILURE, ECONOMIC_ATTACK, ORACLE_FAILURE, GOVERNANCE_INCIDENT
├── Governance Controls   — Max payout, utilization limit, allocation %, timelock
├── Reserve Accounting    — Balance, funding totals, payout totals, metrics
└── Access Control        — ADMIN, INSURANCE_MANAGER, GOVERNANCE, PAUSER roles
```

## Coverage Categories

| Enum Value | Name | Description |
|-----------|------|-------------|
| 0 | `SMART_CONTRACT_FAILURE` | Protocol bugs, upgrade failures, unexpected execution errors |
| 1 | `ECONOMIC_ATTACK` | Protocol insolvency, reward accounting failures, treasury reconciliation failures |
| 2 | `ORACLE_FAILURE` | Incorrect reputation data, external dependency failures |
| 3 | `GOVERNANCE_INCIDENT` | Approved governance recovery actions, emergency protocol recovery |

## Funding Sources

| Enum Value | Name | Description |
|-----------|------|-------------|
| 0 | `PROTOCOL_FEE` | Allocations from protocol fee revenue |
| 1 | `SLASHED_STAKE` | Proceeds from verifier slashing events |
| 2 | `GOVERNANCE` | Direct governance allocations |
| 3 | `TREASURY_TRANSFER` | Transfers from the protocol treasury |
| 4 | `EXTERNAL_DONATION` | Community or ecosystem donations |

## Claims Workflow

```
Incident Reported
       ↓
Claim Submitted (SUBMITTED)
       ↓
Investigation (INVESTIGATING)   ← Insurance Manager
       ↓
Governance Review (REVIEW)      ← Insurance Manager / Governance
       ↓
Governance Approval (APPROVED)  ← Governance Only
       ↓
Payout Timelock (1 day default)
       ↓
Payout Execution (PAID)         ← Anyone (after timelock)
       ↓
Audit Record Stored
```

**Rejection** can happen at any non-terminal state by governance or insurance managers.

## Governance Parameters

| Parameter | Storage | Valid Range | Default | Policy ID |
|-----------|---------|-------------|---------|-----------|
| `maxPayoutPerClaim` | Token amount | 0–unlimited | 0 (unlimited) | `MAX_PAYOUT_PER_CLAIM` |
| `globalUtilizationLimit` | Basis points | 0–10000 | 2000 (20%) | `GLOBAL_UTILIZATION_LIMIT` |
| `allocationPercentage` | Basis points | 0–10000 | 0 | `ALLOCATION_PERCENTAGE` |
| `payoutTimelock` | Seconds | 0–30 days | 1 day | `PAYOUT_TIMELOCK` |
| Coverage toggle | bool per category | — | All enabled | `COVERAGE_ENABLED` |

## Security Model

### Duplicate Payout Prevention
- Strict state machine: claims can only transition `SUBMITTED → ... → APPROVED → PAID`
- `executePayout()` validates `state == APPROVED` and atomically sets `state = PAID` before transfer
- Terminal states (PAID, REJECTED) cannot transition further

### Fraud Prevention
- Incident hash deduplication: identical claims (same claimant + category + amount + URI) are rejected within 30 days
- Governance-only approval prevents unauthorized payouts
- Payout timelock allows community review before execution

### Reserve Protection
- `maxPayoutPerClaim` caps individual claim amounts
- `globalUtilizationLimit` prevents any single claim from draining the reserve (e.g., 20% max)
- Emergency pause via PAUSER_ROLE
- Emergency withdrawal gated behind governance

### Access Control
- **ADMIN_ROLE**: Full administrative access, role management
- **INSURANCE_MANAGER_ROLE**: Can update claim states (investigate, review) and reject claims
- **GOVERNANCE_ROLE**: Can approve claims, set policies, execute emergency withdrawals
- **PAUSER_ROLE**: Can pause/unpause the contract

## Events

| Event | When | Parameters |
|-------|------|------------|
| `InsuranceFunded` | Reserve receives funds | funder, source, amount |
| `InsuranceClaimSubmitted` | New claim created | claimId, claimant, category, requestedAmount |
| `InsuranceClaimStateUpdated` | Claim state changes | claimId, oldState, newState, updatedBy |
| `InsuranceClaimApproved` | Claim approved by governance | claimId, amount |
| `InsuranceClaimRejected` | Claim rejected | claimId, reason, rejectedBy |
| `InsurancePayoutExecuted` | Payout transferred to claimant | recipient, amount, claimId |
| `InsurancePolicyUpdated` | Policy parameter changed | policyId, oldValue, newValue |
| `EmergencyWithdrawal` | Emergency funds withdrawn | recipient, amount, authorizedBy |

## Read Interfaces

| Function | Returns | Description |
|----------|---------|-------------|
| `getReserveBalance()` | `uint256` | Current reserve balance |
| `getUtilizationRatio()` | `uint256` | Paid out / total (basis points) |
| `getClaim(claimId)` | `Claim` | Full claim details |
| `getClaimCount()` | `uint256` | Total claims (including resolved) |
| `getActiveClaims()` | `uint256[]` | Active claim IDs |
| `getFundingHistory(offset, limit)` | `FundingRecord[]` | Paginated funding history |
| `getFundingTotalBySource(source)` | `uint256` | Total by funding source |
| `getReserveMetrics()` | `ReserveMetrics` | Comprehensive metrics |

## Integration with BootstrapController

The Insurance Fund is registered as module `INSURANCE` (`keccak256("INSURANCE")`) in the `BootstrapController`. It is initialized last in the module order (after `REPUTATION_RECEIVER`).

### Bootstrap Registration
```typescript
const MODULE_INSURANCE = ethers.id("INSURANCE");
await controller.registerModule(MODULE_INSURANCE, insuranceFund.target, "InsuranceFund");
```

## Deployment Example

```typescript
import { ethers } from "hardhat";

async function main() {
  const [admin] = await ethers.getSigners();

  // Deploy token (or use existing)
  const Token = await ethers.getContractFactory("TruthBountyToken");
  const token = await Token.deploy(admin.address);

  // Deploy InsuranceFund
  const InsuranceFund = await ethers.getContractFactory("InsuranceFund");
  const fund = await InsuranceFund.deploy(
    await token.getAddress(),
    admin.address,
    governanceController.target
  );
  await fund.waitForDeployment();

  // Fund initial reserve
  await token.approve(fund.target, ethers.parseEther("50000"));
  await fund.fundReserve(2, ethers.parseEther("50000")); // GOVERNANCE
}
```

## Gas Benchmarks (estimated)

| Operation | Gas |
|-----------|-----|
| `fundReserve` | ~55,000 |
| `submitClaim` | ~120,000 |
| `updateClaimState` | ~35,000 |
| `reviewAndApproveClaim` | ~50,000 |
| `executePayout` | ~65,000 |
| `rejectClaim` | ~40,000 |
| `getReserveMetrics` (view) | ~15,000 |
| `getActiveClaims` (view) | ~10,000 |

*Actual gas costs will vary by network and configuration.*

## Future Compatibility

The interface is designed to support:
- Decentralized insurance providers
- Third-party coverage pools
- DAO-managed underwriting
- Protocol reinsurance
- Cross-chain insurance integration

Implementation of these features is outside the scope of this issue.
