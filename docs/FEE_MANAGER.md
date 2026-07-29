# FeeManager — Protocol Fee Management & Treasury Revenue Framework

**SC-028 | TruthBounty Protocol V2**

---

## Overview

The `FeeManager` is the single, canonical entry point for every protocol fee in TruthBounty. No module implements its own fee logic; every fee calculation, collection, and routing decision passes through this contract.

---

## Architecture

```
Protocol Module
       │
       │ collectFee(feeType, payer, amount)
       ▼
  ┌─────────────┐
  │  FeeManager  │ ← governance-controlled schedules
  └──────┬──────┘
         │ _distribute(amount)
         │
   ┌─────┴──────────────────────────────────────┐
   │  AllocationTarget routing (basis points)    │
   └────────────────────────────────────────────┘
         │
   ┌─────┼──────────────────────────────────────────┐
   │     │          │            │             │     │
   ▼     ▼          ▼            ▼             ▼
Treasury Security Ecosystem Contributors Emergency
Reserve  Fund     Fund       Incentives   Reserve
 40%     20%      20%          10%          10%
```

---

## Fee Categories

### Claim Fees
| Identifier | Default | Description |
|------------|---------|-------------|
| `CLAIM_SUBMISSION_FEE` | 0.001 tokens (fixed) | Fee paid when submitting a new claim |
| `CLAIM_UPDATE_FEE` | 0.0005 tokens (fixed) | Fee paid when updating an existing claim |

### Verification Fees
| Identifier | Default | Description |
|------------|---------|-------------|
| `VERIFICATION_SUBMISSION_FEE` | 0.001 tokens (fixed) | Fee paid when submitting a verification |
| `DISPUTE_INITIATION_FEE` | 0.002 tokens (fixed) | Fee paid when initiating a dispute |

### Treasury Fees
| Identifier | Default | Description |
|------------|---------|-------------|
| `PROTOCOL_RESERVE_FEE` | 50 bps (0.5%) | Percentage fee routed to protocol reserve |
| `ECOSYSTEM_ALLOCATION_FEE` | 25 bps (0.25%) | Percentage fee for ecosystem growth |

### Miscellaneous
| Identifier | Default | Description |
|------------|---------|-------------|
| `PROTOCOL_SERVICE_FEE` | 0.0005 tokens (fixed) | General-purpose protocol service fee |

---

## Fee Schedule

Each fee type maintains a versioned `FeeSchedule`:

```solidity
struct FeeSchedule {
    bytes32 feeType;       // keccak256 identifier
    uint256 fixedAmount;   // Fixed fee in token units
    uint256 basisPoints;   // Percentage fee (10000 = 100%)
    uint256 minValue;      // Floor — enforced after calculation
    uint256 maxValue;      // Cap — enforced after calculation (0 = no cap)
    uint256 effectiveAt;   // Timestamp when this schedule took effect
    uint256 govVersion;    // Governance proposal version
    bool    active;        // Whether the fee type is accepting payments
}
```

Fee schedules are fully versioned. Every governance update archives the current schedule before applying the new one, enabling historical audits.

---

## Fee Routing

Collected fees are distributed immediately via basis-point splits:

```
Protocol Fee
      │
      ├─ 40% → Treasury Reserve      (ALLOC_TREASURY_RESERVE)
      ├─ 20% → Security Fund         (ALLOC_SECURITY_FUND)
      ├─ 20% → Ecosystem Fund        (ALLOC_ECOSYSTEM_FUND)
      ├─ 10% → Contributor Incentives (ALLOC_CONTRIBUTOR_INCENTIVES)
      └─ 10% → Emergency Reserve     (ALLOC_EMERGENCY_RESERVE)
```

Routing is deterministic. The last active allocation target absorbs integer-division dust to ensure 100% of collected fees are distributed.

---

## Governance Controls

All fee parameters are adjustable by addresses holding `GOVERNANCE_ROLE` or `DEFAULT_ADMIN_ROLE`:

| Function | Effect |
|----------|--------|
| `updateFeeSchedule(feeType, fixed, bps, min, max)` | Update fee schedule; emits `FeeScheduleUpdated` |
| `setAllocationTargets(targets[])` | Replace routing table; all active targets must sum to 10 000 bps |
| `setFeeActive(feeType, active)` | Activate or deactivate a fee type |
| `setFeeToken(newToken)` | Update the ERC20 fee token (admin only) |

Every schedule update bumps `globalGovVersion` and archives the previous schedule.

---

## Fee Lifecycle

```
1. Module calls calculateFee(feeType, baseAmount)    → previews fee owed
2. Payer approves FeeManager for calculated amount
3. Module calls collectFee(feeType, payer, amount)
   ├── Validates fee type is active and effective
   ├── Validates amount against min/max bounds
   ├── Pulls tokens from payer via SafeERC20.safeTransferFrom
   ├── Generates unique record ID (prevents duplicate processing)
   ├── Updates totalFeesCollected and feesByType[feeType]
   ├── Appends FeeRecord to history
   ├── Emits FeeCollected(feeType, payer, amount)
   └── Calls _distribute(amount)
        ├── Splits amount by allocationTargets basisPoints
        ├── Transfers each share via SafeERC20.safeTransfer
        ├── Updates totalByAllocation[name] and totalFeesDistributed
        └── Emits FeeDistributed(allocation, share) per target
```

---

## Events

```solidity
// Emitted on every successful fee collection
event FeeCollected(bytes32 indexed feeType, address indexed payer, uint256 amount);

// Emitted once per allocation target per collection
event FeeDistributed(bytes32 indexed allocation, uint256 amount);

// Emitted on every fee schedule governance update
event FeeScheduleUpdated(bytes32 indexed feeType, uint256 previousValue, uint256 newValue);

// Emitted when allocation routing table is replaced
event AllocationTargetsUpdated(address indexed updater, uint256 targetCount);

// Emitted when the fee token is changed
event FeeTokenUpdated(address indexed oldToken, address indexed newToken);
```

---

## Read Interfaces

| Function | Returns |
|----------|---------|
| `calculateFee(feeType, baseAmount)` | Calculated fee owed |
| `getFeeSchedule(feeType)` | Active `FeeSchedule` struct |
| `getFeeScheduleAtVersion(feeType, version)` | Archived historical schedule |
| `getAllocationTargets()` | Current routing table |
| `getTotalFeesCollected()` | Cumulative fees collected (all types) |
| `getFeesByType(feeType)` | Cumulative fees for a specific type |
| `getTotalByAllocation(name)` | Cumulative distributed to a target |
| `getTotalFeesDistributed()` | Total distributed across all targets |
| `getRetainedBalance()` | Current undistributed balance (normally 0) |
| `getFeeHistory(offset, limit)` | Paginated `FeeRecord[]` |
| `getFeeRecordCount()` | Total number of fee events |
| `getFeeRecord(index)` | Single `FeeRecord` by index |
| `getTreasuryDistributions()` | Full distribution stats (names, recipients, amounts, shares) |
| `getFeeToken()` | ERC20 fee token address |

---

## Accounting Model

The contract maintains the following invariant at all times:

```
totalFeesCollected == totalFeesDistributed + getRetainedBalance()
```

Under normal operation `getRetainedBalance()` is zero because fees are distributed immediately upon collection. A non-zero retained balance indicates either that all allocation targets are inactive or a transfer failed.

Per-type and per-allocation accounting is maintained separately to support governance transparency and off-chain indexing.

---

## Security Considerations

| Threat | Mitigation |
|--------|-----------|
| Fee bypass | Only `COLLECTOR_ROLE` can call `collectFee` |
| Duplicate collection | Unique record IDs derived from `(feeType, payer, amount, timestamp, index)` |
| Incorrect routing | Allocation targets must sum to exactly 10 000 bps on every update |
| Arithmetic overflow | Solidity 0.8.x built-in overflow protection |
| Reentrancy | `ReentrancyGuard` on `collectFee` |
| Unsafe ERC20 | `SafeERC20` on all token transfers |
| Governance abuse | Two-tier access: `GOVERNANCE_ROLE` for fee updates, `DEFAULT_ADMIN_ROLE` for token changes |
| Treasury inconsistency | `totalFeesCollected == totalFeesDistributed + retained` enforced by design |

---

## Deployment

```bash
# Local
npx hardhat ignition deploy ignition/modules/FeeManager.ts

# Testnet
npx hardhat ignition deploy ignition/modules/FeeManager.ts \
  --network optimismSepolia \
  --parameters ignition/parameters/fee_manager_sepolia.json

# Mainnet
npx hardhat ignition deploy ignition/modules/FeeManager.ts \
  --network optimismMainnet \
  --parameters ignition/parameters/fee_manager_mainnet.json
```

### Parameter File Example (`fee_manager_sepolia.json`)

```json
{
  "FeeManagerModule": {
    "feeToken_":             "0x<BOUNTY_TOKEN_ADDRESS>",
    "initialAdmin":          "0x<ADMIN_ADDRESS>",
    "governanceController":  "0x<GOVERNANCE_CONTROLLER_ADDRESS>",
    "treasuryReserve":       "0x<TREASURY_RESERVE_ADDRESS>",
    "securityFund":          "0x<SECURITY_FUND_ADDRESS>",
    "ecosystemFund":         "0x<ECOSYSTEM_FUND_ADDRESS>",
    "contributorIncentives": "0x<CONTRIBUTOR_INCENTIVES_ADDRESS>",
    "emergencyReserve":      "0x<EMERGENCY_RESERVE_ADDRESS>"
  }
}
```

---

## Integration Guide

### Protocol Module Integration

Protocol modules must:
1. Hold `COLLECTOR_ROLE` on the FeeManager.
2. Ensure payers approve the FeeManager before submitting transactions.
3. Call `calculateFee(feeType, baseAmount)` to preview fees.
4. Call `collectFee(feeType, payer, amount)` to collect.

```solidity
// In a protocol module
IFeeManager feeManager = IFeeManager(feeManagerAddress);

function submitClaim(/* ... */) external {
    uint256 fee = feeManager.calculateFee(
        keccak256("CLAIM_SUBMISSION_FEE"),
        0
    );
    feeManager.collectFee(
        keccak256("CLAIM_SUBMISSION_FEE"),
        msg.sender,
        fee
    );
    // ... claim logic
}
```

---

## Dependencies

| Contract | Purpose |
|----------|---------|
| `GovernanceOwnable` | Governance role integration and `onlyGovernanceOrAdmin` modifier |
| `AccessControl` | Role-based access for `COLLECTOR_ROLE`, `ADMIN_ROLE`, `PAUSER_ROLE` |
| `ReentrancyGuard` | Reentrancy protection on `collectFee` |
| `Pausable` | Emergency pause mechanism |
| `SafeERC20` | Safe ERC20 transfers to recipients |

---

## Gas Benchmarks

| Operation | Approx. Gas |
|-----------|-------------|
| `collectFee` (5 allocation targets) | ~120 000–150 000 |
| `updateFeeSchedule` | ~50 000–70 000 |
| `setAllocationTargets` (5 targets) | ~80 000–100 000 |

Exact benchmarks are recorded in `.gas-reports.json` when tests are run with `REPORT_GAS=true`.

```bash
npm run test:gas
```
