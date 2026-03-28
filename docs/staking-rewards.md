# Staking & Reward Flows Documentation

## Overview

This document provides a comprehensive guide to how staking and rewards operate within the TruthBounty protocol. It covers the complete lifecycle from initial stake deposit through verification, settlement, and reward distribution, including all edge cases and slashing scenarios.

---

## Table of Contents

1. [Staking Lifecycle](#staking-lifecycle)
2. [Reward Distribution Logic](#reward-distribution-logic)
3. [Slashing Scenarios](#slashing-scenarios)
4. [Reward Formulas](#reward-formulas)
5. [Example Scenarios](#example-scenarios)
6. [Edge Cases](#edge-cases)

---

## Staking Lifecycle

### 1. Stake Deposit

Verifiers begin by depositing BOUNTY tokens into the protocol to participate in claim verification.

**Contracts Involved:**
- `TruthBounty.sol` - Primary staking interface
- `Staking.sol` - Standalone staking contract
- `TruthBountyToken.sol` - Token contract with built-in staking

**Process Flow:**

```
User → approve(contract, amount) → BOUNTY Token
User → stake(amount) → TruthBounty/Staking Contract
Contract → transferFrom(user, contract, amount) → BOUNTY Token
Contract → Update verifierStakes[user].totalStaked
Contract → Emit StakeDeposited(user, amount)
```

**Key Parameters:**
| Parameter | Value | Description |
|-----------|-------|-------------|
| `MIN_STAKE_AMOUNT` | 100 BOUNTY | Minimum stake required to participate |
| `lockDuration` | Configurable | Time tokens must remain locked (Staking.sol) |

**Code Example:**
```solidity
// In TruthBounty.sol
function stake(uint256 amount) external nonReentrant whenNotPaused {
    require(amount >= MIN_STAKE_AMOUNT, "Stake below minimum");
    require(bountyToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

    verifierStakes[msg.sender].totalStaked += amount;
    emit StakeDeposited(msg.sender, amount);
}
```

### 2. Active Staking for Voting

When verifiers vote on claims, a portion of their stake becomes "active" and locked until settlement.

**Process Flow:**

```
Verifier → vote(claimId, support, stakeAmount) → TruthBounty
Contract → Check: totalStaked >= activeStakes + stakeAmount
Contract → activeStakes += stakeAmount
Contract → Record vote with stakeAmount
Contract → Update claim totals (totalStakedFor/Against)
```

**Stake States:**
- **Total Staked**: All tokens deposited by verifier
- **Active Stakes**: Tokens currently locked in votes
- **Available Stakes**: Total Staked - Active Stakes (can be withdrawn)

### 3. Stake Withdrawal

Verifiers can withdraw unstaked tokens at any time, subject to lock periods in the standalone Staking contract.

**In TruthBounty.sol:**
```solidity
function withdrawStake(uint256 amount) external nonReentrant {
    VerifierStake storage stake = verifierStakes[msg.sender];
    require(stake.totalStaked >= stake.activeStakes + amount, "Insufficient available stake");

    stake.totalStaked -= amount;
    require(bountyToken.transfer(msg.sender, amount), "Transfer failed");
    emit StakeWithdrawn(msg.sender, amount);
}
```

**In Staking.sol (with lock period):**
```solidity
function unstake(uint256 amount) external nonReentrant {
    StakeInfo storage info = stakes[msg.sender];
    require(info.amount >= amount, "Insufficient staked balance");
    require(block.timestamp >= info.unlockTime, "Stake is still locked");
    
    info.amount -= amount;
    stakingToken.transfer(msg.sender, amount);
    emit Unstaked(msg.sender, amount, info.amount);
}
```

---

## Reward Distribution Logic

### Complete Flow: Stake → Verify → Resolve → Reward

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Stake     │────▶│    Vote     │────▶│  Settlement │────▶│   Reward    │
│   Deposit   │     │   on Claim  │     │   Resolve   │     │   Claim     │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
      │                    │                   │                   │
      ▼                    ▼                   ▼                   ▼
  Lock tokens         Lock active        Determine          Distribute
  in contract         stake in           winner/loser       proportional
                      claim              slash losers       rewards
```

### Settlement Process

1. **Trigger**: Anyone can call `settleClaim(claimId)` after the verification window closes (7 days)

2. **Outcome Determination**:
   ```solidity
   uint256 forPercent = (totalStakedFor * 100) / totalStake;
   bool passed = forPercent >= SETTLEMENT_THRESHOLD_PERCENT; // 60%
   ```

3. **Settlement Calculation**:
   ```solidity
   uint256 winnerStake = passed ? totalStakedFor : totalStakedAgainst;
   uint256 loserStake = passed ? totalStakedAgainst : totalStakedFor;
   
   uint256 slashedAmount = (loserStake * SLASH_PERCENT) / 100;      // 20%
   uint256 rewardAmount = (slashedAmount * REWARD_PERCENT) / 100;   // 80% of slash
   ```

4. **Reward Distribution**:
   ```solidity
   uint256 reward = (vote.stakeAmount * settlement.totalRewards) / settlement.winnerStake;
   ```

### Reward Claiming

Winners claim rewards through `claimSettlementRewards(claimId)`:

```solidity
function claimSettlementRewards(uint256 claimId) external nonReentrant {
    // Verify claim is settled
    require(claim.settled, "Claim not settled");
    
    // Verify user voted and hasn't claimed
    Vote storage vote = votes[claimId][msg.sender];
    require(vote.voted, "No vote cast");
    require(!vote.rewardClaimed, "Rewards already claimed");
    
    // Verify user is winner
    bool isWinner = (vote.support == settlement.passed);
    require(isWinner, "Not a winner");
    
    // Calculate proportional reward
    uint256 reward = (vote.stakeAmount * settlement.totalRewards) / settlement.winnerStake;
    
    // Transfer reward + return original stake
    bountyToken.transfer(msg.sender, reward);
    bountyToken.transfer(msg.sender, vote.stakeAmount);
}
```

---

## Slashing Scenarios

### 1. Settlement-Based Slashing

Occurs automatically when a claim is settled. Verifiers on the losing side are slashed.

**Mechanism:**
- 20% of losing stake is slashed
- 80% of slashed amount distributed to winners as rewards
- 20% of slashed amount remains in protocol (treasury/burn)

**Flow:**
```
Claim Settlement
       │
       ▼
┌──────────────┐
│ Determine    │
│ Winner/Loser │
└──────────────┘
       │
       ▼
┌──────────────┐     ┌──────────────┐
│ Slash Losers │────▶│ 80% → Winners│
│   (20%)      │     │ 20% → Protocol│
└──────────────┘     └──────────────┘
```

### 2. Administrative Slashing (VerifierSlashing.sol)

Manual slashing by authorized resolvers for protocol violations.

**Parameters:**
| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `maxSlashPercentage` | 50% | 1-100% | Max slash per incident |
| `slashCooldown` | 1 hour | ≤ 7 days | Minimum time between slashes |

**Slashing Function:**
```solidity
function slash(
    address verifier,
    uint256 percentage,    // e.g., 25 for 25%
    string calldata reason
) external onlyRole(RESOLVER_ROLE)
```

**Requirements:**
- Caller has RESOLVER_ROLE
- Percentage ≤ maxSlashPercentage
- Cooldown period elapsed since last slash
- Verifier has stake to slash

### 3. Token Contract Slashing (TruthBountyToken.sol)

Legacy slashing mechanism with fixed percentage:

```solidity
function slashVerifier(address verifier, string calldata reason) external onlyResolver {
    uint256 slashedAmount = (verifierStake[verifier] * slashPercentage) / 100; // 10% default
    verifierStake[verifier] -= slashedAmount;
    _burn(address(this), slashedAmount);
}
```

### Slashing Records

All slashes are recorded for transparency:

```solidity
struct SlashRecord {
    uint256 timestamp;
    uint256 amount;
    uint256 percentage;
    string reason;
    address slashedBy;
}

mapping(address => SlashRecord[]) public slashHistory;
```

---

## Reward Formulas

### Core Formulas

#### 1. Outcome Determination
```
forPercent = (totalStakedFor × 100) / (totalStakedFor + totalStakedAgainst)
passed = forPercent >= 60
```

#### 2. Slashing Calculation
```
loserStake = passed ? totalStakedAgainst : totalStakedFor
slashedAmount = (loserStake × 20) / 100
rewardPool = (slashedAmount × 80) / 100
protocolFee = slashedAmount - rewardPool
```

#### 3. Individual Reward Calculation
```
winnerStake = passed ? totalStakedFor : totalStakedAgainst
individualReward = (userStake × rewardPool) / winnerStake

// Total received by winner:
totalReceived = userStake (returned) + individualReward
```

#### 4. Weighted Staking Formula (WeightedStaking.sol)
```
effectiveStake = rawStake × (reputationScore / 1e18)

Where reputationScore is bounded:
- Minimum: 0.1 × 1e18 (10% weight)
- Maximum: 10.0 × 1e18 (1000% weight)
- Default: 1.0 × 1e18 (100% weight)
```

### Example Calculations

**Scenario A: Simple Majority**
- Total staked FOR: 1000 BOUNTY
- Total staked AGAINST: 400 BOUNTY
- User staked FOR: 100 BOUNTY

```
forPercent = (1000 × 100) / 1400 = 71.4% >= 60% → PASSED

loserStake = 400
slashedAmount = (400 × 20) / 100 = 80 BOUNTY
rewardPool = (80 × 80) / 100 = 64 BOUNTY

userReward = (100 × 64) / 1000 = 6.4 BOUNTY
totalReceived = 100 + 6.4 = 106.4 BOUNTY
```

**Scenario B: Weighted Staking**
- User stake: 100 BOUNTY
- User reputation: 2.5

```
effectiveStake = 100 × (2.5 × 1e18 / 1e18) = 250 effective stake
```

---

## Example Scenarios

### Scenario 1: Successful Verification (Winner)

**Setup:**
- Claim created with 7-day verification window
- Verifier A stakes 500 BOUNTY and votes FOR
- Verifier B stakes 300 BOUNTY and votes FOR  
- Verifier C stakes 200 BOUNTY and votes AGAINST

**Settlement:**
- Total FOR: 800 BOUNTY (80%)
- Total AGAINST: 200 BOUNTY (20%)
- Outcome: PASSED (80% >= 60%)

**Calculations:**
```
Slashed = (200 × 20) / 100 = 40 BOUNTY
Reward Pool = (40 × 80) / 100 = 32 BOUNTY

Verifier A reward = (500 × 32) / 800 = 20 BOUNTY
Verifier B reward = (300 × 32) / 800 = 12 BOUNTY

Verifier A receives: 500 + 20 = 520 BOUNTY
Verifier B receives: 300 + 12 = 312 BOUNTY
Verifier C receives: 200 - 40 = 160 BOUNTY (20% slash)
```

### Scenario 2: Unsuccessful Verification (Loser)

Same setup as Scenario 1, but Verifier C votes FOR and A, B vote AGAINST:

- Total FOR: 200 BOUNTY (20%)
- Total AGAINST: 800 BOUNTY (80%)
- Outcome: FAILED (20% < 60%)

**Results:**
```
Verifier A (voted AGAINST, winner): 500 + 20 = 520 BOUNTY
Verifier B (voted AGAINST, winner): 300 + 12 = 312 BOUNTY  
Verifier C (voted FOR, loser): 200 - 40 = 160 BOUNTY
```

### Scenario 3: Tie Scenario

- Total FOR: 500 BOUNTY (50%)
- Total AGAINST: 500 BOUNTY (50%)
- Outcome: FAILED (50% < 60%)

The AGAINST side wins with 50% of the vote.

### Scenario 4: Weighted Reputation Impact

**Setup:**
- Verifier A: 100 BOUNTY stake, reputation 3.0 → 300 effective stake
- Verifier B: 200 BOUNTY stake, reputation 1.0 → 200 effective stake
- Verifier C: 150 BOUNTY stake, reputation 0.5 → 75 effective stake

Both A and B vote FOR, C votes AGAINST:
- Effective FOR: 500
- Effective AGAINST: 75
- Outcome: PASSED (87% >= 60%)

**Rewards based on raw stake:**
```
Slashed = (150 × 20) / 100 = 30 BOUNTY
Reward Pool = (30 × 80) / 100 = 24 BOUNTY

Verifier A reward = (100 × 24) / 300 = 8 BOUNTY
Verifier B reward = (200 × 24) / 300 = 16 BOUNTY
```

### Scenario 5: Administrative Slashing

**Violation:** Verifier D submits fraudulent evidence

**Action:**
```solidity
// Resolver calls
slash(D, 25, "Submitted fabricated evidence");
```

**Result:**
- Verifier D has 1000 BOUNTY staked
- 25% slashed = 250 BOUNTY removed from stake
- Slash recorded in history with timestamp and reason
- 1-hour cooldown begins before D can be slashed again

---

## Edge Cases

### 1. No Votes Cast

**Condition:** Settlement attempted with zero total stake

**Behavior:**
```solidity
require(claim.totalStakeAmount > 0, "No votes cast");
```

Claim cannot be settled until at least one vote is cast.

### 2. Single Verifier Scenario

**Condition:** Only one verifier votes on a claim

**Behavior:**
- If votes FOR with any amount → claim passes (100% >= 60%)
- Verifier receives their stake back but no rewards (no losers to slash)

### 3. Zero Reward Pool

**Condition:** Loser stake is very small or zero

**Behavior:**
```solidity
if (reward > 0) {
    bountyToken.transfer(msg.sender, reward);
}
```
Winners still receive their original stake back.

### 4. Insufficient Stake for Voting

**Condition:** Verifier attempts to vote with more than available

**Validation:**
```solidity
require(
    verifierStakes[msg.sender].totalStaked >= 
    verifierStakes[msg.sender].activeStakes + stakeAmount, 
    "Insufficient available stake"
);
```

### 5. Double Voting Prevention

**Condition:** Verifier attempts to vote twice on same claim

**Validation:**
```solidity
require(!votes[claimId][msg.sender].voted, "Already voted");
```

### 6. Reward Already Claimed

**Condition:** Winner attempts to claim rewards twice

**Validation:**
```solidity
require(!vote.rewardClaimed, "Rewards already claimed");
```

### 7. Cooldown Violation

**Condition:** Slashing attempted before cooldown expires

**Behavior:**
```solidity
if (block.timestamp < lastSlashTime[verifier] + slashCooldown) {
    revert SlashingTooFrequent();
}
```

### 8. Oracle Failure (Weighted Staking)

**Condition:** Reputation oracle is inactive or returns 0

**Fallback:**
```solidity
// Returns default reputation (1.0) if oracle fails
return defaultReputationScore; // 1e18
```

### 9. Emergency Pause

**Condition:** Protocol is paused due to emergency

**Impact:**
- `stake()`, `vote()`, `settleClaim()` are blocked
- `withdrawStake()` and `claimSettlementRewards()` remain available for user fund recovery

### 10. Batch Slashing Limits

**Condition:** Attempting to slash more than 50 verifiers at once

**Validation:**
```solidity
require(length > 0 && length <= 50, "Invalid batch size");
```

Prevents out-of-gas errors in batch operations.

---

## Summary

The TruthBounty protocol implements a robust staking and reward system with the following key characteristics:

1. **Proportional Rewards**: Winners receive rewards proportional to their stake contribution
2. **Deflationary Slashing**: 20% of slashed funds are removed from circulation
3. **Reputation Weighting**: High-reputation verifiers have amplified influence
4. **Cooldown Protection**: Prevents spam slashing and gives verifiers time to respond
5. **Multiple Safeguards**: Reentrancy protection, access control, and pause functionality

For integration details, see the [Protocol Specification](./protocol-spec.md).
