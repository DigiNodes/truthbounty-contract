# Stale Reputation Fix - Quick Reference

## What Was Fixed

The `previewEffectiveStake()` function could return incorrect reputation-weighted voting power if the reputation oracle updated between the preview call and the actual vote.

## Files Modified

### 1. [contracts/TruthBountyWeighted.sol](contracts/TruthBountyWeighted.sol)
Added reputation staleness tracking and validation:

- **New Constant**: `MAX_REPUTATION_STALENESS` (1 hour)
- **New Struct**: `ReputationSnapshot` (reputationScore, timestamp)
- **New Mapping**: `reputationSnapshots` (tracks last vote reputation per user)
- **New Functions**:
  - `voteWithValidation()` - Vote with optional staleness validation
  - `previewEffectiveStakeWithTimestamp()` - Preview with block timestamp
  - `checkReputationStaleness()` - Check if reputation is stale
  - `getLastReputationSnapshot()` - Get last recorded reputation
  - `_validateReputationFreshness()` - Internal validation logic
- **New Events**:
  - `ReputationSnapshotRecorded` - Emitted when reputation recorded
  - `ReputationStalenessValidated` - Emitted during validation

**Breaking Changes**: ❌ None - Fully backward compatible

### 2. [test/StaleReputation.test.ts](test/StaleReputation.test.ts)
Comprehensive test suite with 18 test cases:

- ✅ Preview timestamp functionality
- ✅ Reputation snapshot tracking
- ✅ Staleness detection by time
- ✅ Staleness detection by reputation change
- ✅ Validation acceptance/rejection logic
- ✅ Integration tests
- ✅ Backward compatibility

### 3. [STALE_REPUTATION_FIX.md](STALE_REPUTATION_FIX.md)
Complete implementation documentation.

## How to Use

### Option 1: Safe Voting (Recommended for UIs)

```solidity
// Get preview with timestamp
(uint256 effectiveStake, uint256 reputation, uint256 timestamp) = 
  truthBounty.previewEffectiveStakeWithTimestamp(user, stakeAmount);

// Later, when voting, use voteWithValidation()
truthBounty.voteWithValidation(
  claimId,
  true,           // support
  stakeAmount,
  reputation,     // expected (from preview)
  1000            // max drift: 10% (in basis points: 0-10000)
);
```

### Option 2: Backward Compatible (Legacy)

```solidity
// Original vote() function still works exactly the same
truthBounty.vote(claimId, true, stakeAmount);
// Reputation snapshot is recorded automatically
```

### Option 3: Manual Staleness Check

```solidity
// Check if reputation has changed or timed out
(bool hasChanged, uint256 currentRep, uint256 timeSince) = 
  truthBounty.checkReputationStaleness(user, expectedReputation);

if (!hasChanged) {
  // Safe to proceed with expected reputation
} else {
  // Get new preview or abort
}
```

## Key Parameters

### `MAX_REPUTATION_STALENESS`
- **Value**: 1 hour
- **Purpose**: Maximum time between snapshot and vote
- **Action**: Vote reverts if time exceeded during validation

### `maxReputationDrift` (in basis points)
- **Range**: 0 to 10000
- **Calculation**: `10000 = 100% = no limit`
- **Example**: 
  - `1000` = Allow 10% drift
  - `500` = Allow 5% drift
  - `0` = Only check timestamp (any reputation change OK)

## Reputation Change Detection

### Formula
```
driftPercent = (|current - expected| / expected) * 10000
```

### Example 1: 5% Drift
```
Expected: 2.0
Current:  1.9
Drift:    (0.1 / 2.0) * 10000 = 500 (5%)
MaxDrift: 1000 (10%)
Result:   ✅ PASS (500 < 1000)
```

### Example 2: 25% Drift
```
Expected: 2.0
Current:  1.5
Drift:    (0.5 / 2.0) * 10000 = 2500 (25%)
MaxDrift: 1000 (10%)
Result:   ❌ FAIL (2500 > 1000)
```

## Events Emitted

### `ReputationSnapshotRecorded(address user, uint256 reputationScore, uint256 timestamp)`
- **When**: On any vote (regular or with validation)
- **Purpose**: Track off-chain for monitoring/UI updates

### `ReputationStalenessValidated(address user, uint256 expectedReputation, uint256 actualReputation, uint256 maxDrift)`
- **When**: On `voteWithValidation()` call (after validation passes)
- **Purpose**: Audit trail for validation checks

## Protocol Invariants Maintained

✅ Effective stake calculation: `effectiveStake = stakeAmount * reputation / 1e18`  
✅ Settlement based on weighted stakes  
✅ Reward distribution proportional to effective stakes  
✅ Slashing based on raw stakes  
✅ All voting power calculations unchanged

## Testing

Run the new test suite:
```bash
npm test -- test/StaleReputation.test.ts
```

Verify no regressions:
```bash
npm test
```

## Deployment

- ✅ No contract migration needed
- ✅ No storage reorganization  
- ✅ Can be deployed as-is to existing contracts
- ✅ No governance changes required

## Backward Compatibility

- Original `vote()` function unchanged
- Existing tests pass without modification
- New functionality is opt-in via `voteWithValidation()`
- No breaking changes to any interfaces

## References

- **Issue**: CO-172 - Stale Reputation in previewEffectiveStake
- **Branch**: `fix/preview-effective-stake-stale-reputation`
- **Type**: Bug Fix / Enhancement
- **Complexity**: Medium
