# Reputation Engine Documentation

## Overview

The Reputation Engine is a foundational component of the TruthBounty V2 protocol that quantifies the historical trustworthiness and expertise of each verifier. It provides on-chain, deterministic reputation data that enables weighted verification, reward distribution, and governance eligibility.

## Architecture

### Core Components

1. **Reputation Registry**: Maps verifier addresses to reputation records
2. **Reputation Structure**: Extensible storage for reputation data
3. **Initialization System**: Lazy initialization for new verifiers
4. **Retrieval API**: View functions for reputation queries
5. **Weight Calculation**: Deterministic reputation multiplier calculation
6. **Statistics Tracking**: Protocol-wide and per-verifier statistics
7. **Event System**: Immutable reputation history through events

### Storage Layout

```solidity
struct Reputation {
    uint256 score;                    // Current reputation score (scaled by 1e18)
    uint256 successfulVerifications;  // Total successful verifications
    uint256 failedVerifications;      // Total failed/incorrect verifications
    uint256 disputedVerifications;    // Total disputed claims
    uint256 totalStake;               // Total stake participated (cumulative)
    uint256 lastUpdated;              // Timestamp of last update
    bool exists;                      // Whether reputation record exists
}

struct ProtocolStatistics {
    uint256 totalVerifiers;           // Total number of verifiers
    uint256 totalSuccessfulVerifications; // Cumulative successful verifications
    uint256 totalFailedVerifications; // Cumulative failed verifications
    uint256 totalDisputedClaims;      // Cumulative disputed claims
    uint256 totalRewardsEarned;       // Total rewards earned by verifiers
    uint256 totalStakeParticipated;   // Total stake participated across protocol
}
```

## Key Features

### 1. Reputation Initialization

**Standard Initialization**:
```solidity
function initializeReputation(address verifier) external
```
- Creates reputation record with default score (1e18 = 100%)
- Increments protocol verifier count
- Emits `ReputationCreated` and `ReputationInitialized` events
- Prevents duplicate creation

**Custom Initialization** (UPDATE_ROLE only):
```solidity
function initializeReputationWithScore(address verifier, uint256 initialScore) external
```
- Allows setting custom initial score for special cases (e.g., migration)
- Validates score bounds
- Restricted to UPDATE_ROLE for security

### 2. Reputation Retrieval

**Full Reputation Record**:
```solidity
function getReputation(address verifier) external view returns (Reputation memory)
```

**Reputation Score**:
```solidity
function getReputationScore(address verifier) external view returns (uint256)
```

**Existence Check**:
```solidity
function reputationExists(address verifier) external view returns (bool)
```

### 3. Weight Calculation

**Reputation Multiplier**:
```solidity
function calculateReputationMultiplier(address verifier) external view returns (uint256)
```
- Formula: `multiplier = reputationScore` (scaled by 1e18)
- Capped at 10x to prevent excessive dominance

**Verification Weight**:
```solidity
function calculateWeight(uint256 stakeAmount, address verifier) external view returns (uint256)
```
- Formula: `weight = stakeAmount * reputationMultiplier`
- Used for weighted verification in TruthBountyWeighted

### 4. Protocol Integration Functions

**Reputation Score Update** (UPDATE_ROLE only):
```solidity
function updateReputationScore(address verifier, uint256 newScore) external
```
- Called by Reputation Update Engine after verification settlement
- Validates score bounds
- Emits `ReputationScoreUpdated` event

**Verification Recording** (UPDATE_ROLE only):
```solidity
function recordSuccessfulVerification(address verifier, uint256 stakeAmount) external
function recordFailedVerification(address verifier, uint256 stakeAmount) external
function recordDisputedClaim(address verifier, uint256 stakeAmount) external
```
- Updates verifier statistics
- Updates protocol statistics
- Emits `VerificationStatsUpdated` and `ProtocolStatisticsUpdated` events

**Reward Recording** (UPDATE_ROLE only):
```solidity
function recordRewardEarned(address verifier, uint256 rewardAmount) external
```
- Updates protocol reward statistics
- Called by Reward Engine after reward distribution

**Batch Update** (UPDATE_ROLE only):
```solidity
function batchUpdateVerificationStats(
    address[] calldata verifiers,
    uint256[] calldata successCount,
    uint256[] calldata failCount,
    uint256[] calldata disputeCount
) external
```
- Efficient batch update for multiple verifiers
- Reduces gas costs for bulk operations

### 5. View Helpers

**Eligibility Check**:
```solidity
function isEligibleVerifier(address verifier) external view returns (bool)
```

**Protocol Statistics**:
```solidity
function getStatistics() external view returns (ProtocolStatistics memory)
```

**Verifier Statistics**:
```solidity
function getVerifierStatistics(address verifier) external view returns (
    uint256 successfulVerifications,
    uint256 failedVerifications,
    uint256 disputedVerifications,
    uint256 totalStake
)
```

## Security Considerations

### Access Control

- **ADMIN_ROLE**: Can grant/revoke roles, set initialization restriction
- **UPDATE_ROLE**: Can update reputation scores, record verifications
- **PAUSER_ROLE**: Can pause/unpause contract
- **Governance**: Can update reputation bounds and default scores

### Protection Mechanisms

1. **Unauthorized Modification Prevention**: All write operations require UPDATE_ROLE
2. **Duplicate Profile Prevention**: Reverts on duplicate initialization
3. **Reputation Bounds Validation**: Scores must be within min/max bounds
4. **Address Validation**: Zero address checks on initialization
5. **Initialization Restriction**: Can restrict initialization to UPDATE_ROLE only

### Storage Safety

- **Upgrade-Safe Layout**: Includes storage gap for future upgrades
- **No Arbitrary Writes**: Reputation modifications only through approved functions
- **Deterministic Updates**: All changes are reproducible from protocol events

## Gas Benchmarks

### Core Operations

| Operation | Gas Cost (approx) | Notes |
|-----------|------------------|-------|
| `initializeReputation` | ~80,000 | Creates new reputation record |
| `initializeReputationWithScore` | ~85,000 | Custom score initialization |
| `getReputation` | ~3,000 | View function, minimal gas |
| `getReputationScore` | ~2,500 | View function, minimal gas |
| `calculateReputationMultiplier` | ~2,000 | View function, minimal gas |
| `calculateWeight` | ~2,500 | View function, minimal gas |
| `updateReputationScore` | ~45,000 | UPDATE_ROLE only |
| `recordSuccessfulVerification` | ~60,000 | Updates stats + protocol stats |
| `recordFailedVerification` | ~60,000 | Updates stats + protocol stats |
| `recordDisputedClaim` | ~60,000 | Updates stats + protocol stats |
| `recordRewardEarned` | ~50,000 | Updates protocol stats only |
| `batchUpdateVerificationStats` | ~30,000 per verifier | Efficient bulk operations |

### Optimization Strategies

1. **Lazy Initialization**: Reputation records created only when needed
2. **Batch Operations**: Reduced gas for multiple updates
3. **View Function Optimization**: Minimal storage reads
4. **Event Emission**: Only essential events emitted
5. **Storage Layout**: Optimized for efficient access

## Integration Points

### Verification Aggregation

The Reputation Engine integrates with Verification Aggregation through:
- `recordSuccessfulVerification()` - Called after successful verification
- `recordFailedVerification()` - Called after failed verification
- `recordDisputedClaim()` - Called when claim is disputed

### Reward Engine

The Reputation Engine integrates with Reward Engine through:
- `recordRewardEarned()` - Called after reward distribution
- Reputation score used for reward multiplier calculation

### Slashing Engine

The Reputation Engine integrates with Slashing Engine through:
- Reputation score considered in slashing calculations
- Failed verifications tracked for slashing eligibility

### Governance

The Reputation Engine integrates with Governance through:
- Reputation score used for governance eligibility
- Governance can update reputation bounds and default scores
- Reputation-weighted voting in governance proposals

### Staking

The Reputation Engine integrates with Staking through:
- Reputation multiplier used for effective stake calculation
- Total stake tracked for staking statistics

## Events

### Reputation Lifecycle Events

```solidity
event ReputationCreated(address indexed verifier);
event ReputationInitialized(address indexed verifier, uint256 initialScore, uint256 timestamp);
```

### Update Events

```solidity
event ReputationScoreUpdated(address indexed verifier, uint256 oldScore, uint256 newScore, uint256 timestamp);
event VerificationStatsUpdated(address indexed verifier, uint256 successfulVerifications, uint256 failedVerifications, uint256 disputedVerifications, uint256 timestamp);
event StakeParticipationUpdated(address indexed verifier, uint256 totalStake, uint256 timestamp);
```

### Protocol Statistics Events

```solidity
event ProtocolStatisticsUpdated(
    uint256 totalVerifiers,
    uint256 totalSuccessfulVerifications,
    uint256 totalFailedVerifications,
    uint256 totalDisputedClaims,
    uint256 totalRewardsEarned,
    uint256 totalStakeParticipated
);
```

### Configuration Events

```solidity
event ReputationBoundsUpdated(uint256 oldMinScore, uint256 oldMaxScore, uint256 newMinScore, uint256 newMaxScore);
event DefaultInitialScoreUpdated(uint256 oldScore, uint256 newScore);
event InitializationRestrictionToggled(bool restricted);
```

## Testing

### Unit Tests

Comprehensive unit tests cover:
- Reputation initialization (standard and custom)
- Reputation retrieval functions
- Weight calculation
- View helpers
- Governance functions
- Pause functionality
- Security validations

### Integration Tests

Integration tests verify compatibility with:
- Staking module
- Governance module
- Reward Engine
- Verification Aggregation
- Slashing Engine

### Fuzz Tests

Fuzz tests ensure:
- Deterministic reputation calculations
- Edge case handling (min/max scores, large amounts)
- Array length validation
- Address validation
- Statistical consistency

## Future Extensibility

The storage layout is designed to support future additions:

### Potential Extensions

1. **Expertise Domains**: Category-specific reputation
2. **Verifier Levels**: Tiered reputation system
3. **Decay Metadata**: Support for reputation decay
4. **Governance Trust Score**: Separate governance reputation
5. **Sybil Resistance Score**: Anti-Sybil reputation metric

### Storage Gap

The contract includes a 50-slot storage gap for future upgrades:
```solidity
uint256[50] private __gap;
```

## Deployment

### Prerequisites

1. Deploy MockGovernanceController (or actual governance controller)
2. Deploy ReputationEngine with admin and governance controller addresses
3. Grant UPDATE_ROLE to authorized addresses (e.g., Verification Aggregation)
4. Grant PAUSER_ROLE to authorized addresses
5. Configure reputation bounds and default initial score via governance

### Configuration Parameters

- `defaultInitialScore`: Default reputation for new verifiers (default: 1e18)
- `minReputationScore`: Minimum allowed reputation score (default: 1e17)
- `maxReputationScore`: Maximum allowed reputation score (default: 10e18)
- `restrictedInitialization`: Whether initialization is restricted (default: false)

## Maintenance

### Regular Tasks

1. Monitor protocol statistics for anomalies
2. Review reputation distribution for fairness
3. Update reputation bounds if needed via governance
4. Audit reputation update events for consistency

### Emergency Procedures

1. **Pause Contract**: Use PAUSER_ROLE to pause operations
2. **Restrict Initialization**: Enable initialization restriction
3. **Revoke Compromised Roles**: Revoke UPDATE_ROLE if compromised
4. **Emergency Governance**: Use governance to update parameters

## References

- [TruthBounty Protocol V2 Specification](./PROTOCOL_SPEC.md)
- [Reputation Model](./REPUTATION_MODEL.md)
- [Verification Aggregation Specification](./VERIFICATION_AGGREGATION.md)
- [Governance Specification](./GOVERNANCE.md)
- [OpenZeppelin Upgradeable Storage Guidelines](https://docs.openzeppelin.com/contracts/4.x/api/proxy#upgradeable-storage)

## License

MIT License - See LICENSE file for details.
