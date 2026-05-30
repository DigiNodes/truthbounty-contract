# Grace Period for Reputation Updates - Implementation Guide

## 📋 Overview

The Grace Period for Reputation Updates feature prevents users from gaming the TruthBounty verification system by making last-minute reputation boosts right before voting. This ensures that reputation-weighted voting power reflects a user's legitimate standing, not artificially inflated scores set moments before participation.

## 🎯 Problem Statement

**Security Issue**: Users could update their reputation score just before voting on a claim, artificially inflating their voting weight to manipulate claim outcomes in their favor.

**Example Scenario**:
1. User has 1x reputation (baseline)
2. Claim is created
3. User immediately updates reputation to 10x
4. User votes with artificially boosted 10x reputation
5. Outcome unfairly influenced

## ✅ Solution: Grace Period Window

A reputation update is considered "within grace period" if it occurred within `reputationUpdateGracePeriod` time window relative to a claim's creation.

**Formula**:
```
timeSinceUpdate = |lastReputationUpdateTime - claimCreatedAt|
withinGracePeriod = timeSinceUpdate <= reputationUpdateGracePeriod
```

**Default grace period**: 2 days

**Grace period window**: Symmetric around claim creation time
- Updates made up to 2 days BEFORE claim creation → restricted
- Updates made up to 2 days AFTER claim creation → restricted

## 🔧 Technical Implementation

### 1. Interface Enhancement (`IReputationOracle`)

```solidity
/**
 * @notice Get the timestamp of the last reputation update for a user
 * @param user The address to query
 * @return timestamp The Unix timestamp of the last update (0 if never updated)
 */
function getLastReputationUpdate(address user) external view returns (uint256 timestamp);
```

### 2. Oracle Implementation (`MockReputationOracle`)

- Tracks `lastUpdateTimestamp` for each user
- Updates timestamp whenever reputation is set/modified
- Implements `getLastReputationUpdate()` method
- Provides backward compatibility (graceful degradation)

### 3. Core Logic (`TruthBountyWeighted`)

#### New Function: `_getReputationScoreWithGracePeriod()`

```solidity
function _getReputationScoreWithGracePeriod(
    address user,
    uint256 claimCreatedAt
) internal view returns (uint256 score)
```

**Logic Flow**:
1. Get user's last reputation update timestamp from oracle
2. Calculate time difference from claim creation
3. If difference ≤ grace period: return **default reputation** (1x)
4. If difference > grace period: return **actual reputation**

#### Modified: `vote()` Function

Changed from:
```solidity
uint256 reputationScore = _getReputationScore(msg.sender);
```

To:
```solidity
uint256 reputationScore = _getReputationScoreWithGracePeriod(msg.sender, claim.createdAt);
```

### 4. Governance Control

#### New State Variable
```solidity
uint256 public reputationUpdateGracePeriod = DEFAULT_REPUTATION_UPDATE_GRACE_PERIOD; // 2 days
```

#### Bounds
- **Minimum**: 1 hour
- **Maximum**: 30 days
- **Default**: 2 days

#### Governance Function
```solidity
function setReputationUpdateGracePeriod(uint256 newGracePeriod) external onlyGovernanceOrAdmin
```

## 📊 Behavior Examples

### Example 1: Last-Minute Boost (Prevented ✓)

```
Time 0: Reputation set to 1x
Time 0 + 6 hours: Claim created
Time 0 + 7 hours: User updates reputation to 10x
Time 0 + 8 hours: User votes

Result: Vote uses 1x (default) because update was 2 hours after claim creation
        (within 2-day grace period)
```

### Example 2: Legitimate Old Reputation (Allowed ✓)

```
Time 0: Reputation set to 10x
Time 0 + 3 days: Claim created (now outside 2-day grace period)
Time 0 + 3.5 days: User votes

Result: Vote uses 10x because reputation was updated 3 days ago
        (outside 2-day grace period window)
```

### Example 3: Multiple Voters (Independent Evaluation ✓)

```
Verifier A: Updated reputation 4 days ago
Verifier B: Updated reputation 1 hour ago

Claim created at Time X

Vote A: Uses actual reputation (4 days > 2-day grace period)
Vote B: Uses default reputation (1 hour < 2-day grace period)
```

## 🧪 Testing Strategy

### Unit Tests (`ReputationGracePeriod.test.ts`)

1. **Configuration Tests**
   - Default grace period set correctly
   - Grace period updates work
   - Bounds are enforced

2. **Core Functionality Tests**
   - Last-minute boosts prevented
   - Old reputation allowed
   - Grace period window calculations correct

3. **Integration Tests**
   - Multiple voters with different timings
   - Claim settlement calculations correct
   - Effective stake calculations correct

4. **Edge Cases**
   - Never-updated users
   - Oracle compatibility (backward compatibility)
   - Boundary conditions

### Invariant Tests (`ReputationGracePeriodInvariant.t.sol`)

Foundry-based invariants ensuring:
- Grace period always enforced
- Outside grace period uses actual reputation
- Grace period window is symmetric
- Effective stake not manipulated
- Bounds enforced
- Independent voter evaluation

## 🔒 Security Properties

### Invariant 1: Reputation Boost Prevention
**Property**: A user cannot artificially increase their voting weight by updating reputation within the grace period.

**Verification**: Any reputation update within grace period → default reputation used → voting weight capped.

### Invariant 2: Legitimate Reputation Honored
**Property**: Users with longstanding high reputation can still use it for voting.

**Verification**: Reputation updates outside grace period → actual reputation used → legitimate weight applied.

### Invariant 3: Independent Voter Evaluation
**Property**: Each voter's grace period is evaluated independently based on their own update timing.

**Verification**: Multiple voters can have different reputation scores for same claim based on their individual update histories.

### Invariant 4: Deterministic Enforcement
**Property**: Grace period enforcement is deterministic and cannot be bypassed.

**Verification**: Governance can adjust grace period bounds, but cannot disable enforcement; try-catch handles oracle compatibility issues.

## 📈 Impact Analysis

### Protection Against Attacks

| Attack | Before | After |
|--------|--------|-------|
| Last-minute reputation boost | ✗ Vulnerable | ✓ Prevented |
| Coordinated timing attacks | ✗ Vulnerable | ✓ Mitigated |
| Oracle manipulation | ⚠️ Possible | ✓ Tracked |

### Performance Impact

- **On-chain Gas**: Minimal additional reads (1-2 extra oracle calls)
- **Storage**: Single mapping addition per oracle update
- **Backward Compatibility**: Full (try-catch handles missing method)

## 🛠️ Deployment Checklist

- [ ] Deploy updated `TruthBountyWeighted` contract
- [ ] Update oracle implementations to track timestamps
- [ ] Set grace period via governance (or use default 2 days)
- [ ] Run comprehensive test suite
- [ ] Deploy invariant test checks
- [ ] Monitor grace period adherence in production
- [ ] Document parameter in governance guide

## 📝 Configuration Guide

### Setting Grace Period

```typescript
// Via governance
const tx = await truthBounty.setReputationUpdateGracePeriod(
  3 * 24 * 60 * 60  // 3 days
);
await tx.wait();

// Verify
const gracePeriod = await truthBounty.reputationUpdateGracePeriod();
console.log(`Grace period: ${gracePeriod / (24 * 60 * 60)} days`);
```

### Recommended Values

- **Conservative**: 2-3 days (current default)
- **Moderate**: 1-2 days
- **Aggressive**: 1 day
- **Minimum**: 1 hour

## 🔄 Future Enhancements

1. **Per-claim grace period override**: Allow governance to set different grace periods for different claim types
2. **Graduated grace period**: Different periods based on reputation score magnitude
3. **Whitelisting**: Allow certain high-reputation users to bypass grace period (requires governance)
4. **Analytics**: Track grace period enforcement statistics
5. **Integration with ReputationDecay**: Combine with existing decay mechanism for comprehensive reputation management

## 📚 Related Documentation

- [TruthBounty Protocol Specification](./docs/protocol-spec.md)
- [Reputation System Design](./docs/reputation-system.md)
- [Staking and Rewards](./docs/staking-rewards.md)

## ✨ Summary

The Grace Period for Reputation Updates provides a critical security layer preventing last-minute voting manipulation while preserving legitimate reputation-weighted participation. It ensures the TruthBounty system's integrity through deterministic, governable enforcement of reputation timing rules.

---

**Implementation Date**: May 2026  
**Issue Reference**: #CO-173  
**Status**: ✅ Production Ready
