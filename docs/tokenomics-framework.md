# Tokenomics & Incentive Distribution Framework (SC-027)

## Overview

The TokenomicsEngine is the central deterministic allocation engine for the TruthBounty protocol. It receives protocol revenue from modular sources and distributes it according to governance-controlled, basis-point-percentage allocations.

## Allocation Flow

```
Revenue
  → Treasury (internal accounting)
  → Verifier Rewards (REWARDS_POOL)
  → Governance (GOVERNANCE_RESERVES)
  → Ecosystem (ECOSYSTEM_FUND)
  → Protocol Development (PROTOCOL_FEES)
  → Emergency Reserve (ECOSYSTEM_FUND)
```

Every allocation is reproducible and auditable through on-chain events and an append-only distribution history.

## Incentive Model

The protocol supports configurable allocations for:

- **Verifier Rewards** — Distributed to verifiers via the REWARDS_POOL treasury account
- **Treasury Reserves** — Stored in GOVERNANCE_RESERVES for protocol sustainability
- **Ecosystem Incentives** — Funded via ECOSYSTEM_FUND for community programs
- **Governance Incentives** — Reserved for governance participant rewards
- **Protocol Development** — Funded via PROTOCOL_FEES for engineering and audits
- **Emergency Reserve** — Held in ECOSYSTEM_FUND for protocol emergencies

All allocations are expressed in basis points (BPS) and must sum to exactly 10,000 (100%).

## Reward Lifecycle

1. **Revenue Reception**: A caller approves the TokenomicsEngine and calls `distributeRevenue(source, amount)`.
2. **Validation**: The engine checks allocation configuration, emission limits, and treasury solvency.
3. **Calculation**: Shares are computed via `AllocationPolicies.calculateProportionalAllocation()`.
4. **Multiplier Application**: The governance `rewardMultiplier` scales the verifier rewards portion.
5. **Treasury Integration**: Allocated amounts are deposited into internal TreasuryAccounting accounts via `depositToAccount()`.
6. **Recording**: An immutable `DistributionRecord` is appended to on-chain history.
7. **Events**: Auditable events (`RevenueReceived`, `TokenomicsAllocated`, `IncentiveDistributionCompleted`) are emitted.

## Governance Controls

Governance (via GovernanceController + GovernanceOwnable) controls:

- **Allocation Percentages** — `setSourceAllocation(source, config)`
- **Emission Limits** — `setEmissionLimit(limit)`
- **Reward Multipliers** — `setRewardMultiplier(multiplier)`
- **Treasury Reserve Targets** — `setTreasuryReserveTarget(bps)`

### Parameter Types

The following `ParameterType` values were added to `GovernanceHooks`:

- `VERIFIER_REWARD_ALLOCATION_BPS`
- `TREASURY_RESERVE_ALLOCATION_BPS`
- `ECOSYSTEM_INCENTIVE_ALLOCATION_BPS`
- `GOVERNANCE_INCENTIVE_ALLOCATION_BPS`
- `PROTOCOL_DEVELOPMENT_ALLOCATION_BPS`
- `EMERGENCY_RESERVE_ALLOCATION_BPS`
- `EMISSION_LIMIT`
- `REWARD_MULTIPLIER`
- `TREASURY_RESERVE_TARGET_BPS`
- `PROTOCOL_FEE_ALLOCATION_BPS`

## Treasury Interaction

The TokenomicsEngine integrates with `TreasuryAccounting` (SC-017) using:

- `calculateTotalAssets()` — for solvency validation before distribution
- `depositToAccount(account, amount)` — for crediting internal treasury accounts
- `getAccountBalance(account)` — for balance introspection via read interfaces

Before distribution, the engine validates that `actualTokenBalance >= accountedTotal` to prevent structuring allocations during a treasury deficit.

## Distribution Policies

Modular policies in `AllocationPolicies.sol`:

| Policy | Use Case |
|---|---|
| `calculateProportionalAllocation` | Standard proportional split |
| `calculateReputationWeightedAllocation` | Verifier share modulated by reputation score |
| `calculateStakeWeightedAllocation` | Verifier share modulated by active stake |
| `calculateGovernanceIncentiveAllocation` | Governance reward distribution |

Referral incentives can be added later by extending `AllocationPolicies` without modifying the core engine.

## Modular Reward Sources

New revenue sources require only:

1. Adding a value to the `RevenueSource` enum
2. Calling `_setSourceAllocationRaw()` with a default `SourceAllocation` in `_initDefaultAllocations()`

No changes to allocation math are required.

## Read Interfaces

| Function | Purpose |
|---|---|
| `getAllocationConfig(source)` | Return BPS configuration per source |
| `getDistributionRecord(id)` | Return full distribution record by ID |
| `getEmissionStats()` | Return total distributed, emission limit, multiplier, reserve target |
| `getTotalBySource(source)` | Return cumulative distributed per source |
| `getDistributionHistory(offset, limit)` | Return paginated distribution history |
| `getDistributionHistoryLength()` | Return total distribution count |

## Safety Constraints

- **ReentrancyGuard** on all state-mutating external calls
- **Pausable** for emergency stops
- **Duplicate distribution rejection** via `processedDistributions` mapping
- **Emission limit enforcement** per source
- **Treasury solvency validation** before distribution
- **Basis point validation** (must sum to 10,000)
- **Invariant**: allocation shares always sum to total amount distributed

## Events

| Event | When Emitted |
|---|---|
| `RevenueReceived(source, amount, sender)` | Revenue enters the engine |
| `TokenomicsAllocated(distributionId, source, totalAmount)` | Allocation is executed |
| `IncentiveDistributionCompleted(...)` | Final destination details are recorded |
| `AllocationUpdated(source, oldBPS, newBPS)` | Governance updates allocation config |
| `EmissionLimitUpdated(old, new)` | Emission limit is changed |
| `RewardMultiplierUpdated(old, new)` | Reward multiplier is changed |
| `TreasuryReserveTargetUpdated(old, new)` | Treasury reserve target is changed |
