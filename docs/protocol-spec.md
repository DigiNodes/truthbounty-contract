# TruthBounty Protocol Specification

## 📚 Overview

TruthBounty is a decentralized protocol for fact verification that uses economic incentives and reputation-weighted voting to determine the truthfulness of claims. The protocol consists of smart contracts that handle claim submission, verifier staking, weighted voting, reward distribution, and slashing mechanisms.

This document serves as the canonical reference for contributors, auditors, and developers working with the TruthBounty protocol.

---

## 🏗️ Architecture Overview

### Core Contracts

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| **TruthBounty** | Main protocol contract | Claim lifecycle, basic voting, settlement |
| **TruthBountyWeighted** | Enhanced version with reputation | Reputation-weighted voting, oracle integration |
| **TruthBountyToken** | ERC20 token + staking | Native token, staking, basic slashing |
| **VerifierSlashing** | Advanced slashing mechanism | Cooldown periods, batch operations |
| **WeightedStaking** | Reputation-weighted calculations | Oracle integration, bounds checking |
| **IReputationOracle** | Interface for reputation data | Standardized reputation access |

### Supporting Contracts

| Contract | Purpose |
|----------|---------|
| **ReputationDecay** | Time-based reputation decay |
| **ReputationSnapshot** | Reputation state snapshots |
| **ReputationReceiver** | Handles reputation updates |
| **ExampleSettlement** | Settlement logic examples |

---

## 👥 Roles and Access Control

### Role Hierarchy

```
DEFAULT_ADMIN_ROLE
├── ADMIN_ROLE
│   ├── RESOLVER_ROLE (Settlement)
│   └── TREASURY_ROLE
└── PAUSER_ROLE
```

### Role Responsibilities

| Role | Responsibilities | Granted To |
|------|------------------|-------------|
| **DEFAULT_ADMIN_ROLE** | Protocol governance, role management | Protocol deployer |
| **ADMIN_ROLE** | Contract configuration, oracle updates | Protocol administrators |
| **RESOLVER_ROLE** | Claim settlement, verifier slashing | Settlement contracts |
| **TREASURY_ROLE** | Treasury management (future) | Protocol treasury |
| **PAUSER_ROLE** | Emergency pause/unpause | Protocol administrators |

### Access Control Patterns

- **Only Admin**: Configuration updates, oracle changes
- **Only Resolver**: Claim settlement, slashing operations
- **Only Pauser**: Emergency pause functionality
- **Public**: Claim creation, staking, voting (when not paused)

---

## 🔄 Claim Lifecycle

### 1. Claim Creation

```solidity
function createClaim(string memory content) external returns (uint256)
```

**Process:**
1. User submits claim with content reference (IPFS hash)
2. Protocol assigns unique `claimId`
3. Verification window set to 7 days from creation
4. Claim stored in `claims[claimId]` mapping

**State Changes:**
- `claimCounter` incremented
- New `Claim` struct created
- `ClaimCreated` event emitted

**Validation:**
- Protocol not paused
- Content string non-empty
- Caller valid address

### 2. Verifier Staking

```solidity
function stake(uint256 amount) external
```

**Process:**
1. Verifier transfers tokens to contract
2. Stake amount added to `verifierStakes[verifier].totalStaked`
3. Tokens locked until withdrawal

**State Changes:**
- `verifierStakes[verifier].totalStaked` increased
- Tokens transferred from verifier to contract
- `StakeDeposited` event emitted

**Validation:**
- Amount ≥ `MIN_STAKE_AMOUNT` (100 tokens)
- Sufficient token balance
- Token transfer successful

### 3. Reputation-Weighted Voting

```solidity
function vote(uint256 claimId, bool support, uint256 stakeAmount) external
```

**Process:**
1. Verifier selects claim and voting direction
2. Reputation score fetched from oracle
3. Effective stake calculated: `rawStake × reputationScore`
4. Vote recorded with both raw and effective stakes
5. Claim totals updated with weighted values

**State Changes:**
- `votes[claimId][verifier]` populated
- `claim.totalWeightedFor/Against` updated
- `verifierStakes[verifier].activeStakes` increased
- `VoteCast` event emitted

**Validation:**
- Claim exists and not settled
- Verification window open
- Verifier hasn't voted already
- Sufficient available stake
- Stake amount ≥ minimum

### 4. Claim Settlement

```solidity
function settleClaim(uint256 claimId) external
```

**Process:**
1. Verification window must be closed
2. Outcome determined by weighted vote percentage
3. Winner side receives rewards, loser side slashed
4. Settlement calculated and stored

**Outcome Determination:**
```solidity
uint256 forPercent = (totalWeightedFor * 100) / totalWeightedStake;
bool passed = forPercent >= SETTLEMENT_THRESHOLD_PERCENT; // 60%
```

**Reward Calculation:**
```solidity
uint256 loserRawStake = calculateLoserRawStake(claimId, passed);
uint256 slashedAmount = (loserRawStake * SLASH_PERCENT) / 100; // 20%
uint256 rewardAmount = (slashedAmount * REWARD_PERCENT) / 100; // 80% of slash
```

**State Changes:**
- `claim.settled = true`
- `settlementResults[claimId]` populated
- `totalSlashed` and `totalRewarded` updated
- `ClaimSettled` event emitted

### 5. Reward Distribution

```solidity
function claimSettlementRewards(uint256 claimId) external
```

**Process:**
1. Winner verifiers claim proportional rewards
2. Rewards calculated based on effective stake contribution
3. Raw stake returned to winners
4. Losers receive remaining stake minus slash

**Reward Calculation:**
```solidity
uint256 reward = (vote.effectiveStake * settlement.totalRewards) / settlement.winnerWeightedStake;
```

**State Changes:**
- `vote.rewardClaimed = true`
- `vote.stakeReturned = true`
- `verifierStakes[verifier].activeStakes` decreased
- Tokens transferred to verifier
- `RewardsDistributed` event emitted

---

## 💰 Economic Model

### Token Economics

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Initial Supply** | 10,000,000 BOUNTY | Minted to deployer |
| **Minimum Stake** | 100 BOUNTY | Minimum participation amount |
| **Verification Window** | 7 days | Voting period duration |
| **Settlement Threshold** | 60% | Minimum for claim to pass |
| **Slash Percentage** | 20% | Percentage of loser stake slashed |
| **Reward Percentage** | 80% | Percentage of slash distributed to winners |

### Reputation Weighting

**Reputation Score Bounds:**
- **Minimum**: 0.1 (10% weight)
- **Default**: 1.0 (100% weight)  
- **Maximum**: 10.0 (1000% weight)

**Effective Stake Formula:**
```
effectiveStake = rawStake × (reputationScore / 1e18)
```

**Example Calculations:**
- 100 BOUNTY stake × 1.0 reputation = 100 effective stake
- 100 BOUNTY stake × 2.5 reputation = 250 effective stake  
- 100 BOUNTY stake × 0.5 reputation = 50 effective stake

### Slashing Mechanism

**Slashing Conditions:**
- Voting against majority outcome
- Protocol violations (admin slashing)
- Cooldown period: 1 hour between slashes

**Slashing Protection:**
- Maximum 50% slash per incident
- Cooldown prevents spam slashing
- Batch operations for efficiency

---

## 🔒 Security and Invariants

### Core Invariants

1. **Token Conservation**: Total supply never increases except minting
2. **Stake Accounting**: `totalStaked ≥ activeStakes` always holds
3. **Vote Uniqueness**: One vote per verifier per claim
4. **Settlement Finality**: Claims settled once and only once
5. **Reward Bounds**: Total rewards ≤ total slashed × reward percentage

### Critical Security Properties

**Reentrancy Protection:**
- All state-changing functions use `nonReentrant`
- External calls made after state updates
- OpenZeppelin ReentrancyGuard implementation

**Access Control:**
- Role-based permissions for all admin functions
- Separate roles for different operations
- Role admin hierarchy prevents privilege escalation

**Integer Safety:**
- SafeMath patterns for arithmetic operations
- Overflow checks in all calculations
- Proper scaling for reputation calculations

**Oracle Safety:**
- Try-catch patterns for oracle calls
- Fallback to default reputation on failures
- Bounds checking for reputation scores

### Attack Vectors and Mitigations

| Attack Vector | Description | Mitigation |
|---------------|-------------|------------|
| **Oracle Manipulation** | Malicious reputation oracle | Oracle can be updated by admin, fallback to default |
| **Flash Loan Attacks** | Temporary stake manipulation | Staking has cooldown, voting window limits |
| **Front-running** | Transaction ordering manipulation | Use of timestamps, not block numbers |
| **Sybil Attacks** | Multiple verifier identities | Economic cost of staking deters sybils |
| **Governance Attacks** | Admin key compromise | Multi-sig recommended for admin roles |

---

## 🔗 Contract Interactions

### Protocol Flow Diagram

```
User → TruthBounty.createClaim()
        ↓
Verifier → TruthBounty.stake()
        ↓
Verifier → TruthBountyWeighted.vote() → WeightedStaking.calculateWeightedStake() → ReputationOracle
        ↓
Resolver → TruthBountyWeighted.settleClaim()
        ↓
Winner → TruthBountyWeighted.claimSettlementRewards()
        ↓
Admin → VerifierSlashing.slash() (if needed)
```

### Cross-Contract Dependencies

**TruthBountyWeighted Dependencies:**
- `IERC20` (bountyToken) - for staking and rewards
- `IReputationOracle` - for reputation scores
- `WeightedStaking` - for stake calculations

**VerifierSlashing Dependencies:**
- `IStaking` - for stake access and slashing

**WeightedStaking Dependencies:**
- `IReputationOracle` - for reputation data

### Event-Driven Architecture

**Key Events:**
- `ClaimCreated` - New claim submitted
- `VoteCast` - Verifier voted on claim
- `ClaimSettled` - Claim resolution determined
- `RewardsDistributed` - Rewards paid to winners
- `StakeSlashed` - Verifier stake slashed
- `ReputationOracleUpdated` - Oracle configuration changed

---

## 🧮 Reputation System

### Reputation Oracle Interface

```solidity
interface IReputationOracle {
    function getReputationScore(address user) external view returns (uint256 score);
    function isActive() external view returns (bool isActive);
}
```

### Reputation Integration

**Score Retrieval Flow:**
1. Check if oracle is active
2. Fetch reputation score for user
3. Apply min/max bounds (0.1 to 10.0)
4. Use default (1.0) if oracle returns 0 or fails
5. Calculate effective stake with bounded score

**Bounds Checking:**
```solidity
if (score < minReputationScore) return minReputationScore; // 0.1
if (score > maxReputationScore) return maxReputationScore; // 10.0
return score;
```

### Reputation Decay (Future)

The `ReputationDecay` contract implements time-based reputation decay to prevent reputation accumulation and encourage ongoing participation.

---

## ⚙️ Configuration Parameters

### Protocol Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `VERIFICATION_WINDOW_DURATION` | 7 days | Voting period length |
| `MIN_STAKE_AMOUNT` | 100 × 10¹⁸ | Minimum stake (100 tokens) |
| `SETTLEMENT_THRESHOLD_PERCENT` | 60 | Pass threshold percentage |
| `REWARD_PERCENT` | 80 | Percentage of slash given as rewards |
| `SLASH_PERCENT` | 20 | Percentage of loser stake slashed |
| `BASE_MULTIPLIER` | 1e18 | Precision base for calculations |

### Configurable Parameters

| Parameter | Default | Range | Set By |
|-----------|---------|-------|--------|
| `minReputationScore` | 1e17 (0.1) | > 0 | Admin |
| `maxReputationScore` | 10e18 (10.0) | > min | Admin |
| `defaultReputationScore` | 1e18 (1.0) | > 0 | Admin |
| `weightedStakingEnabled` | true | boolean | Admin |
| `maxSlashPercentage` | 50 | 1-100 | Admin |
| `slashCooldown` | 1 hour | ≤ 7 days | Admin |

---

## 🚀 Deployment Architecture

### Multi-Chain Strategy

**Ethereum (L1):**
- High-value settlements
- Final dispute resolution
- Cross-chain bridge anchors

**Optimism (L2):**
- Primary verification operations
- Low-cost reward distribution
- High-frequency claim processing

**Stellar (Future):**
- Micro-rewards distribution
- Emerging market accessibility
- Cross-chain verification proofs

### Contract Upgradeability

**Proxy Pattern:**
- UUPS upgradeable proxies recommended
- Admin controls upgrade permissions
- Storage layout compatibility required

**Migration Strategy:**
- State migration functions for major upgrades
- Graceful deprecation of old versions
- Cross-chain contract synchronization

---

## 🔍 Integration Guide

### Backend API Integration

**Required Event Monitoring:**
- `ClaimCreated` - Trigger verification workflow
- `VoteCast` - Update vote tallies
- `ClaimSettled` - Calculate final outcomes
- `RewardsDistributed` - Update user balances

**API Endpoints Needed:**
```javascript
// Claim submission
POST /api/claims
{
  "content": "ipfs://QmHash...",
  "submitter": "0x..."
}

// Vote submission  
POST /api/votes
{
  "claimId": 123,
  "support": true,
  "stakeAmount": "100000000000000000000"
}

// Settlement trigger
POST /api/claims/:claimId/settle

// Reward claiming
POST /api/rewards/:claimId/claim
```

### Frontend Integration

**Key UI Components:**
- Claim submission form
- Active claims dashboard
- Voting interface with reputation display
- Stake management panel
- Reward claiming interface

**Real-time Updates:**
- WebSocket connection for live events
- Claim status updates
- Vote count displays
- Reward notifications

---

## 📊 Monitoring and Analytics

### Key Metrics

**Protocol Health:**
- Total claims created/settled
- Average verification time
- Participation rate (verifiers per claim)
- Settlement accuracy (if external ground truth available)

**Economic Metrics:**
- Total value staked
- Reward distribution volume
- Slashing frequency and amounts
- Token velocity and circulation

**Reputation Metrics:**
- Reputation score distribution
- Reputation decay rates
- Oracle availability and accuracy
- Weighted vs unweighted voting outcomes

### Event Monitoring

**Critical Events:**
- `ClaimCreated` - New claim activity
- `ClaimSettled` - Settlement outcomes
- `StakeSlashed` - Security incidents
- `ReputationOracleUpdated` - Configuration changes

**Alerting Thresholds:**
- High slashing rates (>5% of claims)
- Oracle downtime (>1 hour)
- Unusual stake concentration
- Settlement failures

---

## 🛡️ Auditing Considerations

### Critical Audit Areas

1. **Access Control**: Role permissions and escalation
2. **Economic Logic**: Reward/slash calculations
3. **Reputation System**: Oracle integration and bounds
4. **State Management**: Claim lifecycle transitions
5. **Token Safety**: Transfer and balance operations

### Test Coverage Requirements

**Unit Tests:**
- All public/external functions
- Edge cases and error conditions
- Access control permissions
- Mathematical calculations

**Integration Tests:**
- Full claim lifecycle
- Cross-contract interactions
- Oracle failure scenarios
- Emergency procedures

**Property Tests:**
- Invariant preservation
- Economic model consistency
- Reputation bounds adherence
- Token conservation

### Security Checklist

- [ ] Reentrancy protection on all external calls
- [ ] Integer overflow/underflow protection
- [ ] Access control on all admin functions
- [ ] Proper event emission for state changes
- [ ] Safe external call patterns
- [ ] Input validation on all parameters
- [ ] Emergency pause functionality
- [ ] Upgrade safety (if using proxies)

---

## 🔮 Future Enhancements

### Protocol V2 Features

**Advanced Reputation:**
- Multi-dimensional reputation scores
- Context-specific reputation
- Reputation delegation mechanisms

**Economic Improvements:**
- Dynamic reward mechanisms
- Insurance pools for verifiers
- Yield generation on staked tokens

**Governance:**
- DAO-based parameter updates
- Community dispute resolution
- Protocol treasury management

### Cross-Chain Expansion

**Bridge Integration:**
- Ethereum ↔ Optimism bridge
- Stellar integration via Soroban
- Cross-chain reputation sharing

**Multi-Asset Support:**
- Multiple staking tokens
- Stablecoin rewards
- NFT-based reputation systems

---

## 📝 Glossary

| Term | Definition |
|------|------------|
| **Claim** | A statement submitted for truth verification |
| **Verifier** | A participant who stakes tokens to vote on claims |
| **Effective Stake** | Raw stake amount multiplied by reputation score |
| **Settlement** | The process of determining claim outcome |
| **Slashing** | Penalty applied to verifiers who vote against majority |
| **Reputation Oracle** | External contract providing reputation scores |
| **Verification Window** | Time period during which verifiers can vote |
| **Settlement Threshold** | Minimum percentage required for claim to pass |

---

## 📞 Support and Resources

### Documentation

- **Smart Contract Code**: `/contracts` directory
- **Test Suites**: `/test` directory  
- **Deployment Scripts**: `/scripts` directory
- **Configuration Examples**: `/ignition` directory

### Community

- **GitHub Issues**: Bug reports and feature requests
- **Discord**: Community discussion and support
- **Technical Blog**: Protocol updates and analysis

### Professional Services

- **Security Audits**: Available through reputable firms
- **Integration Support**: Technical assistance for integrators
- **Consulting**: Protocol design and optimization

---

*This specification is a living document and will be updated as the TruthBounty protocol evolves. Last updated: March 2026*
