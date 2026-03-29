# TruthBounty Protocol Threat Model

**Version:** 1.0  
**Date:** March 2026  
**Status:** Active Development  

---

## 📋 Executive Summary

This document provides a comprehensive threat analysis of the TruthBounty protocol, identifying potential attack vectors, their impact, probability, and mitigation strategies. The protocol manages incentivized claim verification with stake-based voting, reputation weighting, and automated slashing mechanisms.

**Key Risk Areas:**
- Reentrancy and state consistency violations
- Sybil attacks through stake multiplication
- Economic attacks via price manipulation
- Front-running and information asymmetry
- Oracle manipulation and single points of failure
- Governance risks and centralization vectors

---

## 🎯 Risk Classification Framework

| Severity | Impact | Probability | Priority |
|----------|--------|-------------|----------|
| **Critical** | Protocol loss, fund theft | Low-High | Immediate |
| **High** | Significant fund loss, DoS | Medium-High | Very Soon |
| **Medium** | Limited fund loss, data corruption | Medium | Soon |
| **Low** | Minimal loss, UX issues | Medium-High | Standard |
| **Info** | Best practices, optimization | N/A | Documentation |

---

## 🔴 Critical Risks

### 1. Reentrancy Attacks

#### 1.1 Cross-Contract Reentrancy in Stake Withdrawal

**Location:** `Staking.sol:unstake()`, `TruthBountyToken.sol:withdrawStake()`

**Description:**
The staking mechanism performs external calls before updating internal state:
```solidity
// State AFTER external call
stakingToken.transfer(msg.sender, amount);
info.amount -= amount;  // State update happens after
```

**Attack Scenario:**
1. Attacker stakes 1000 tokens with a malicious ERC20 receiver
2. Calls `unstake()` with 1000 tokens
3. Malicious receiver's `onTransfer()` hook re-enters the contract
4. The attacker can re-call `unstake()` since `info.amount` hasn't been decremented yet
5. Multiple token transfers drain the contract

**Impact:** Complete loss of all staked tokens in the Staking contract

**Probability:** High (if receiver is attacker-controlled)

**Mitigation:**
- ✅ **Already Implemented:** `ReentrancyGuard` is used in `Staking.sol`
- ✅ **Already Implemented:** State updates precede external calls in most functions
- ⚠️ **Verify:** Ensure all stake withdrawal paths follow checks-effects-interactions pattern
- 📋 **Action Items:**
  - Add `nonReentrant` modifier to all token transfer functions
  - Audit all external calls for state consistency
  - Implement pull-over-push pattern where possible

**Risk Level:** 🟡 **MEDIUM** (Partially Mitigated)

---

### 1.2 Reentrancy in Claim Settlement

**Location:** `TruthBountyWeighted.sol:settleClaim()`, `TruthBountyClaims.sol:settleClaim()`

**Description:**
Reward distribution involves external token transfers that could trigger reentrancy:
```solidity
// Potential reentrancy window
bountyToken.transfer(verifier, rewardAmount);
// State updates for rewards
rewardClaimed[claimId][verifier] = true;
```

**Attack Scenario:**
1. Attacker submits claim and votes with large stake
2. Claim settles in attacker's favor
3. During reward distribution, attacker's contract intercepts the transfer
4. Reenters settlement function to claim additional rewards
5. Votes are flagged as not yet claimed due to state not being updated

**Impact:** Multiple reward claims for single vote, token draining

**Probability:** Medium-High

**Mitigation:**
- ✅ **Already Implemented:** `nonReentrant` in `TruthBountyClaims.sol:settleClaim()`
- ✅ **Already Implemented:** `nonReentrant` in `TruthBountyWeighted.sol`
- 📋 **Recommendations:**
  - Use indexed state flags (not boolean) to prevent partial state updates
  - Implement separation of claim settlement and reward distribution
  - Add explicit checks before each transfer operation

**Risk Level:** 🟢 **LOW** (Well Mitigated)

---

### 1.3 Reentrancy in Batch Operations

**Location:** `TruthBountyClaims.sol:settleClaimsBatch()`

**Description:**
Batch settlement processes multiple transfers in a loop without per-item state updates:
```solidity
for (uint256 i = 0; i < length; ) {
    _settle(beneficiaries[i], amounts[i]);  // Transfer happens here
    unchecked { ++i; }
}
```

**Attack Scenario:**
1. Attacker is positioned at index 0 in batch settlement
2. First iteration calls `_settle()`, triggering attacker's receiver
3. Attacker views current loop state (i=0)
4. Potential to manipulate subsequent iterations

**Impact:** Skipped settlements, double settlements, batch integrity violation

**Probability:** Medium

**Mitigation:**
- ✅ **Already Implemented:** `nonReentrant` modifier on `settleClaimsBatch()`
- ✅ **Already Implemented:** `MAX_BATCH_SIZE = 200` prevents out-of-gas
- 📋 **Recommendations:**
  - Add per-item settlement flags
  - Use pull-based reward claims instead of push-based batch distribution
  - Implement settlement confirmation logs

**Risk Level:** 🟢 **LOW** (Mitigated)

---

## 🟠 High-Priority Risks

### 2. Sybil Attacks

#### 2.1 Stake Multiplication via Multiple Accounts

**Location:** `TruthBountyWeighted.sol`, `WeightedStaking.sol`

**Description:**
An attacker can create multiple accounts with minimum stake to influence voting:
- Each account needs only MIN_STAKE_AMOUNT (100 tokens)
- With 10,000 tokens, attacker can create 100 identities
- Each identity votes independently in claim settlement

**Attack Scenario:**
1. Attacker obtains 10,000 tokens (possibly through airdrops or token purchase)
2. Creates 100 externally owned accounts (EOAs) or contract wallets
3. Stakes 100 tokens in each account
4. All 100 accounts vote on a favorable claim
5. Even with reputation weighting, the overall weight can dominate

**Impact:** Manipulation of claim outcomes, creation of false consensus

**Probability:** High (depends on token distribution and cost of account creation)

**Mitigation:**
- ⚠️ **Partial:** Reputation weighting provides some protection
  - Reputation scores can vary between accounts
  - Default reputation is 1e18 (neutral), so new accounts start equal
  - Only oracles that properly score individual identities prevent this
- 📋 **Recommendations:**
  - Implement Sybil resistance mechanisms:
    - On-chain identity verification (e.g., ENS, NounsDAO)
    - Proof of humanity integration
    - Time-lock requirements (newer accounts have reduced weight)
  - Enforce minimum reputation for voting eligibility
  - Implement daily voting caps per account
  - Add delegation restrictions
  - Cross-chain identity correlation

**Risk Level:** 🟠 **HIGH** (Requires External Mitigation)

---

#### 2.2 Rep-Weighted Sybil Attacks

**Location:** `IReputationOracle.sol` interface implementations

**Description:**
If the reputation oracle is poorly designed, attackers can game reputation scores:
- Oracle returns same score for all users by default
- No distinction between old and new accounts
- No historical verification of behavior

**Attack Scenario:**
1. Malicious oracle implementation returns high rep for all addresses
2. All sybil accounts get same high reputation multiplier
3. Effective stake becomes: 100 tokens × 10 accounts × high reputation = manipulated voting power

**Impact:** Negation of reputation-weighting defense against Sybil attacks

**Probability:** Medium (depends on oracle implementation quality)

**Mitigation:**
- 📋 **Critical Recommendations:**
  - Mandatory oracle audits before deployment
  - Implement oracle diversity (multiple reputation sources)
  - Add oracle health monitoring and alerts
  - Implement reputation score validation bounds
  - Create fallback oracle mechanism
  - Whitelist trusted oracle implementations

**Risk Level:** 🟠 **HIGH** (Oracle-Dependent)

---

### 2.3 Account Linkage via Shared Resources

**Location:** All contracts with `msg.sender` tracking

**Description:**
Attackers may use shared infrastructure (same IP, same node, same secret key manager) that links supposedly independent accounts.

**Mitigation:**
- 📋 **Recommendations:**
  - Encourage validators to verify account diversity off-chain
  - Implement IP address logging (privacy considerations)
  - Use decentralized identity networks
  - Require staking time locks to accumulate reputation cost

**Risk Level:** 🟡 **MEDIUM** (Mitigated by Reputation Scoring)

---

### 3. Economic Manipulation

#### 3.1 Token Price Manipulation

**Location:** `TruthBountyToken.sol` (staking decisions)

**Description:**
Attacker manipulates token price to affect staking economics:
- Buys tokens to manipulate fork of protocol
- Dumps tokens to reduce staking incentives
- Creates false scarcity narratives

**Attack Scenario:**
1. Attacker controls 30% of circulating supply
2. Threatens to dump tokens, reducing incentive value
3. Validators are forced to reduce stakes due to low ROI
4. Protocol security degrades (lower honest stake participation)
5. Attacker can now influence claims with less competition

**Impact:** Reduced security, manipulation of incentive mechanisms

**Probability:** High (derivative of market conditions, not technical bug)

**Mitigation:**
- 📋 **Recommendations:**
  - Implement slashing cooldown periods to prevent rapid response changes
  - Use time-weighted average price (TWAP) for oracle values
  - Diversify token distribution (not held by few addresses)
  - Implement dynamic reward adjustment based on stake composition
  - Maintain minimum threshold of diverse stakers
  - Consider reputation-locked rewards

**Risk Level:** 🟠 **HIGH** (Economic, Not Technical)

---

#### 3.2 Hyper-Inflation Attack

**Location:** `TruthBountyToken.sol:_mint()`

**Description:**
If the initial admin key is compromised, attacker can mint unlimited tokens:
```solidity
constructor(address initialAdmin) {
    _mint(initialAdmin, 10_000_000 * 10 ** decimals());
}
```

Only initial minting is present, but if governance is added (planned), minting rights must be controlled.

**Attack Scenario:**
1. Attacker obtains admin private key
2. Calls `_mint()` to create 1 billion additional tokens
3. Sells tokens to deplete value
4. Or uses inflated supply to stake with minimal cost

**Impact:** Complete devaluation of protocol token, loss of all staked assets

**Probability:** Low (depends on key security)

**Mitigation:**
- ✅ **Already Implemented:** Minting only in constructor
- 📋 **Recommendations:**
  - Implement DAO-based minting governance
  - Use multi-signature control for admin functions
  - Implement time-locks on sensitive operations
  - Add supply cap in token contract
  - Require community approval for new minting

**Risk Level:** 🔴 **CRITICAL** (If Key is Compromised)

---

#### 3.3 Reward Rate Manipulation

**Location:** `TruthBountyWeighted.sol` (REWARD_PERCENT, SLASH_PERCENT constants)

**Description:**
Current implementation uses hardcoded constants for reward rates. If admin can change these, rewards can be manipulated.

**Attack Scenario:**
1. Admin reduces REWARD_PERCENT from 80% to 10%
2. Participating verifiers receive minimal rewards
3. Validators leave the protocol
4. Admin changes SLASH_PERCENT to 0%
5. Can now create false claims without penalty for underperforming verifiers

**Impact:** Incentive structure collapsed, protocol abandoned

**Probability:** Low (requires admin misbehavior)

**Mitigation:**
- 📋 **Recommendations:**
  - Remove hardcoded constants, implement configurable parameters
  - Add governance delays (timelock) for parameter changes
  - Implement bounds checking (e.g., REWARD_PERCENT must be 50-90%)
  - Emit events for ALL parameter changes
  - Require multi-signature for critical parameters
  - Implement gradual parameter updates (no sudden changes)

**Risk Level:** 🟠 **HIGH** (Governance Risk)

---

### 4. Front-Running Attacks

#### 4.1 Mempool Manipulation in Vote Casting

**Location:** `TruthBountyWeighted.sol:castVote()`

**Description:**
An attacker observes another user's vote in the mempool and front-runs it:

**Attack Scenario:**
1. Validator A creates transaction to vote FOR with 1000 token stake
2. Transaction sits in mempool
3. Attacker observes transaction and creates competing transaction
4. Attacker sets same vote but with higher gas price
5. Attacker's vote is included first, with updated claim totals
6. When Validator A's vote executes, claim outcome is already determined
7. Validator A's vote becomes wasted or ineffective

**Impact:** Voting power loss, manipulation of vote ordering

**Probability:** Medium (depends on network congestion)

**Mitigation:**
- 📋 **Recommendations:**
  - Implement meta-transaction support (relayers sign off-chain)
  - Use Flashbots or MEV-resistant sequencing (L2)
  - Add voting commits with timed reveals (commit-reveal scheme)
  - Implement batch voting windows with finality
  - Use Optimism sequencer protection (if deployed on L2)
  - Set minimum stake amounts to make MEV non-profitable

**Risk Level:** 🟡 **MEDIUM** (Layer 2 Dependent)

---

#### 4.2 Claim Settlement Front-Running

**Location:** `TruthBountyWeighted.sol:settleClaim()`

**Description:**
Attacker front-runs claim settlement to affect reward distribution:

**Attack Scenario:**
1. Claim is about to settle with attacker's vote in losing position
2. Attacker sees settlement transaction in mempool
3. Attacker adds final vote with higher gas price before settlement
4. Settlement now includes attacker's vote (which may swing outcome)
5. Rewards distributed based on manipulated vote count

**Impact:** Vote manipulation, unearned rewards

**Probability:** Medium-High (direct financial incentive)

**Mitigation:**
- 📋 **Recommendations:**
  - Lock voting windows before settlement (no votes after window ends)
  - Implement settlement delays (e.g., settlement settles 1 block after window)
  - Use threshold-based settlement (triggered automatically when conditions met)
  - Implement randomized settlement times (not predictable)
  - Add nonce-based vote tracking to prevent old votes

**Risk Level:** 🟠 **HIGH** (Direct Attack Vector)

---

#### 4.3 Stake Withdrawal Ordering

**Location:** `Staking.sol:unstake()`

**Description:**
Attacker observes slashing transaction in mempool and front-runs withdrawal:

**Attack Scenario:**
1. Protocol detects attacker should be slashed for 50% of stake
2. Slashing tx is submitted to blockchain
3. Attacker sees pending slashing tx in mempool
4. Attacker immediately submits `unstake()` with higher gas price
5. `unstake()` executes first, removing funds before slashing
6. Slashing transaction finds `info.amount = 0`, nothing to slash

**Impact:** Evading slashing penalties, undermining protocol security

**Probability:** High (if attacker monitors own address)

**Mitigation:**
- 📋 **Recommendations:**
  - Implement forced stake locks during dispute windows
  - Add cooldown periods between unstake and actual withdrawal
  - Require withdrawal approval before funds are released
  - Implement batched withdrawal processing
  - Use commit-reveal for unstaking
  - Add dispute windows (e.g., 3-day delay before withdrawal completes)

**Risk Level:** 🔴 **CRITICAL** (Protocol Integrity Risk)

---

## 🟡 Medium-Priority Risks

### 5. Oracle Manipulation

#### 5.1 Reputation Oracle Takeover

**Location:** `IReputationOracle.sol`, `WeightedStaking.sol`, `TruthBountyWeighted.sol`

**Description:**
The reputation oracle is a critical component. If compromised, it can manipulate voting weights:

**Attack Scenario:**
1. Attacker compromises the reputation oracle contract
2. Modifies `getReputationScore()` to return high scores for sybil accounts
3. Modifies `isActive()` to always return true even when data is stale
4. Attacker's multiple accounts now have 10x reputation multiplier
5. Attacker can dominate any vote unfairly

**Impact:** Complete protocol takeover, all claims manipulated

**Probability:** Medium (depends on oracle security)

**Mitigation:**
- ✅ **Already Implemented:** Oracle is passed as parameter, not hardcoded
- 📋 **Recommendations:**
  - Require multi-signature control of oracle updates
  - Implement time-locks before oracle changes (48-72 hours)
  - Add oracle health monitoring (stale price detection)
  - Implement fallback oracle mechanisms
  - Create oracle diversity (multiple sources for reputation)
  - Add circuit breaker if reputation scores change dramatically
  - Implement reputation score history and allow rollback

**Risk Level:** 🔴 **CRITICAL** (If Oracle Fails)

---

#### 5.2 Stale Reputation Data

**Location:** `IReputationOracle.isActive()`

**Description:**
The interface requires `isActive()` but doesn't specify what "active" means:
- Oracle could return stale data weeks old
- Validators could vote based on outdated reputation
- No timestamp validation in interface

**Attack Scenario:**
1. Oracle goes offline or becomes unmaintained
2. Interface still returns `isActive() = true` (hardcoded)
3. All new votes use old, potentially incorrect reputation data
4. Voting patterns become predictable based on stale information

**Impact:** Degraded voting accuracy, manipulation via stale data

**Probability:** Medium-High

**Mitigation:**
- 📋 **Recommendations:**
  - Add timestamp to oracle responses
  - Implement maximum staleness threshold (e.g., 1 day)
  - Reject votes if oracle data is stale
  - Emit warnings if oracle hasn't updated in X time
  - Implement automatic oracle deactivation after timeout
  - Add fallback to default reputation if oracle is stale

**Risk Level:** 🟠 **HIGH**

---

#### 5.3 Oracle Data Format Manipulation

**Location:** `WeightedStaking.sol:calculateWeightedStake()`

**Description:**
The oracle returns uint256 scores, but values are unbounded:

**Attack Scenario:**
1. Attacker creates custom oracle with extreme values
2. Returns maxReputationScore = 1000 * 1e18 (1000x multiplier)
3. Attacker with 100-token stake gets 100,000-token effective stake
4. Attacker controls all voting

**Impact:** Effective stake inflation, voting dominance

**Probability:** High

**Mitigation:**
- ✅ **Already Implemented:** `minReputationScore` and `maxReputationScore` bounds
- 📋 **Recommendations:**
  - Add oracle response validation in contract
  - Implement whitelist of trusted oracle addresses
  - Add reputation score sanity checks (e.g., must be between 0.1 and 10)
  - Implement gradual reputation transitions (no jumps > 20%)
  - Add events for all oracle updates
  - Create oracle audit trail

**Risk Level:** 🟢 **LOW** (Well Mitigated)

---

### 5.4 Oracle Latency Attacks

**Location:** `IReputationOracle.getReputationScore()`

**Description:**
If the oracle takes time to respond, attackers can exploit latency:

**Attack Scenario:**
1. Oracle call is queued but slow to respond
2. Attacker rapidly polls oracle multiple times
3. Gets inconsistent or delayed results
4. Can exploit timing windows

**Impact:** Race conditions in reputation calculations

**Probability:** Low (if oracle responses are atomic)

**Mitigation:**
- 📋 **Recommendations:**
  - Cache oracle results with TTL
  - Implement request batching
  - Add rate limiting on oracle calls
  - Use off-chain computation with commit-reveal

**Risk Level:** 🟡 **MEDIUM**

---

### 6. Governance Risks

#### 6.1 Admin Key Compromise

**Location:** All contracts using `onlyRole(ADMIN_ROLE)`

**Description:**
A single compromised admin key can damage the entire protocol:
- Change oracle addresses
- Update slashing percentages
- Pause contracts
- Update configuration parameters

**Attack Scenario:**
1. Admin private key is leaked or stolen
2. Attacker calls `setReputationOracle()` with malicious oracle
3. Attacker calls `setSlashPercentage(0)` to disable penalties
4. Attacker creates winning claims for all known addresses
5. Distributes rewards to sybil accounts

**Impact:** Complete protocol compromise

**Probability:** Low-Medium (depends on key security practices)

**Mitigation:**
- 📋 **Recommendations:**
  - Implement multi-signature control (3-of-5 or similar)
  - Use hardware wallets for admin keys
  - Implement Gnosis Safe or similar multisig contract
  - Add time-locks before parameters become effective
  - Implement emergency contracts that can revert changes
  - Require community voting for critical changes
  - Add admin key rotation policies

**Risk Level:** 🔴 **CRITICAL** (If Key is Compromised)

---

#### 6.2 Role Creep and Privilege Escalation

**Location:** `AccessControl` role definitions

**Description:**
New roles are added over time without clear bounds:
- Multiple roles with overlapping permissions
- Unclear role hierarchy
- Potential for accidental privilege escalation

**Attack Scenario:**
1. New READER_ROLE is added for auditors
2. By mistake, READER_ROLE inherits from RESOLVER_ROLE
3. Auditors can now settle claims and slash verifiers
4. Malicious "auditor" abuses privileges

**Impact:** Unintended privilege escalation

**Probability:** Medium (common mistake in governance)

**Mitigation:**
- 📋 **Recommendations:**
  - Document all roles and permissions clearly
  - Implement role hierarchy audits
  - Add tests verifying role boundaries
  - Freeze role definitions after mainnet deploy
  - Implement role separation of duties
  - Use role-to-action mapping

**Risk Level:** 🟡 **MEDIUM**

---

#### 6.3 Governance Voter Apathy

**Location:** Governance mechanisms (planned)

**Description:**
If governance is added, insufficient participation enables manipulation:

**Attack Scenario:**
1. Governance proposal to increase reward rates
2. Quorum is 20% of all token holders
3. Only 5% of holders participate in voting
4. Small malicious group votes YES with 100% participation
5. Proposal passes because their 5% wins among 5% voters

**Impact:** Minority control of protocol parameters

**Probability:** High (common in DAO governance)

**Mitigation:**
- 📋 **Recommendations:**
  - Set quorum to 50%+ to prevent minority control
  - Implement delegation to encourage participation
  - Add voting incentives (reward for voting)
  - Implement tiered governance (smaller changes need less quorum)
  - Use reputation weighting in governance votes
  - Add voting veto periods before implementation

**Risk Level:** 🟠 **HIGH** (Governance-Dependent)

---

#### 6.4 Centralization of Resolver Role

**Location:** `RESOLVER_ROLE` in all contracts

**Description:**
The `RESOLVER_ROLE` (settlement) is highly centralized. A single resolver can:
- Settle claims arbitrarily
- Slash verifiers without dispute
- Approve reward distributions

**Impact:** Protocol outcome depend on single actor

**Probability:** High (architectural risk)

**Mitigation:**
- 📋 **Recommendations:**
  - Implement decentralized resolution (committee > 3 signers)
  - Add resolution disputes and appeals
  - Require transparency in settlement decisions
  - Implement automatic settlements for clear majorities (>80%)
  - Add resolver accountability logs
  - Implement resolver rotation policy

**Risk Level:** 🟠 **HIGH** (Architectural)

---

## 🟢 Low-Priority Risks

### 7. Reputation Decay Manipulation

**Location:** `ReputationDecay.sol`

**Description:**
Reputation decay parameters can be exploited if the contract is misconfigured:

**Attack Scenario:**
1. Admin sets `decayRatePerEpoch = 0` (no decay)
2. Attacker's low reputation never decreases
3. Old sybil accounts keep high voting power indefinitely

**Impact:** Sybil accounts persist longer, reputation system degrades

**Probability:** Low (requires admin misconfiguration)

**Mitigation:**
- 📋 **Recommendations:**
  - Set decay parameters to sensible defaults
  - Add validation bounds
  - Implement parameter change notifications
  - Add automatic decay resets
  - Implement historical reputation tracking

**Risk Level:** 🟡 **MEDIUM** (Configuration Risk)

---

### 8. Snapshot Bridge Attack

**Location:** `ReputationSnapshot.sol`

**Description:**
Cross-chain reputation bridges can be exploited if not secured properly:

**Attack Scenario:**
1. Attacker creates snapshot with inflated reputation scores
2. Bridges snapshot to other chains
3. Other chains accept snapshot without verification
4. Attacker votes with high reputation on multiple chains

**Impact:** Cross-chain voting manipulation

**Probability:** Medium (if bridge not audited)

**Mitigation:**
- 📋 **Recommendations:**
  - Require multi-signature for snapshot creation
  - Implement snapshot verification on destination chains
  - Add time-lock before snapshot applicability
  - Require oracle confirmation of snapshot validity
  - Implement snapshot history and audits

**Risk Level:** 🟡 **MEDIUM**

---

### 9. Gas Exhaustion DoS

**Location:** `TruthBountyClaims.sol:settleClaimsBatch()`

**Description:**
Batch operations could cause out-of-gas errors if batch size isn't limited:

**Attack Scenario:**
1. Attacker submits settlement with 10,000 beneficiaries
2. Batch operation runs out of gas mid-execution
3. Transaction reverts, partial state updates occur
4. Claims are left in inconsistent state

**Impact:** Denial of service, state corruption

**Probability:** Low

**Mitigation:**
- ✅ **Already Implemented:** `MAX_BATCH_SIZE = 200`
- 📋 **Recommendations:**
  - Test max batch sizes with actual gas estimates
  - Implement fallback to individual settlements
  - Add pagination support for large settlement lists
  - Monitor gas usage in batch operations

**Risk Level:** 🟢 **LOW** (Mitigated)

---

### 10. Claim Content Manipulation

**Location:** `TruthBountyWeighted.sol:createClaim()`

**Description:**
Claim content is stored as string reference (IPFS hash), but could be tampered if:
- IPFS node is compromised
- Hash collision occurs
- Content-addressed storage fails

**Attack Scenario:**
1. Attacker creates claim with IPFS hash "QmXYZ"
2. Original content is "The sky is blue"
3. Later, attacker modifies IPFS node to return "The sky is green"
4. Verifiers unknowingly vote on modified content

**Impact:** Voting on different content than intended

**Probability:** Low (IPFS is content-addressed)

**Mitigation:**
- 📋 **Recommendations:**
  - Store content hash on-chain (e.g., SHA-256)
  - Implement content verification in voting
  - Use immutable storage (Arweave, etc.)
  - Add content timestamping
  - Implement dispute mechanism for content changes

**Risk Level:** 🟡 **MEDIUM**

---

### 11. Integer Overflow/Underflow

**Location:** All arithmetic operations

**Description:**
Solidity 0.8.20+ has built-in overflow/underflow protection, but unchecked blocks can bypass it:

**Attack Scenario:**
1. Code uses `unchecked` block for optimization
2. Attacker finds a sequence that causes underflow
3. Large negative numbers wrap to huge positive numbers
4. Token balances become corrupted

**Impact:** Token balance corruption, fund theft

**Probability:** Low (if unchecked blocks are audited)

**Mitigation:**
- ✅ **Already Implemented:** Solidity 0.8+ protection
- ✅ **Already Implemented:** Limited `unchecked` usage (gas optimization in loops)
- 📋 **Recommendations:**
  - Audit all `unchecked` blocks
  - Implement SafeMath library for critical operations
  - Do not use `unchecked` unless absolutely necessary for gas optimization
  - Test edge cases (zero, max values)

**Risk Level:** 🟢 **LOW**

---

## 📊 Risk Summary Matrix

| Risk Category | Severity | Probability | Status |
|---------------|----------|-------------|--------|
| Reentrancy | Critical | Low | Mitigated ✅ |
| Sybil (Stake Mult.) | High | High | Requires External Control |
| Sybil (Rep-Based) | High | Medium | Requires External Control |
| Token Price Manip. | High | High | Economic Risk |
| Front-Running (Settlements) | High | Medium-High | Requires L2/Mitigation |
| Front-Running (Withdrawals) | Critical | High | Requires Implementation |
| Oracle Takeover | Critical | Medium | Critical Control |
| Admin Key Compromise | Critical | Low | Requires Multi-Sig |
| Governance Centralization | High | High | Architectural |
| Reputation Decay Manip. | Medium | Low | Configuration Risk |
| Snapshot Bridge | Medium | Medium | Bridge Risk |
| Gas DoS | Low | Low | Mitigated ✅ |
| Claim Content Manip. | Medium | Low | Storage Risk |

---

## ✅ Implemented Mitigations

### Security Features Already in Place

1. **Reentrancy Protection**
   - ✅ `ReentrancyGuard` used in `Staking`, `TruthBountyClaims`, `TruthBountyWeighted`
   - ✅ `nonReentrant` modifiers on critical functions

2. **Reputation Weighting**
   - ✅ `WeightedStaking.sol` implements reputation-scaled voting
   - ✅ Min/max reputation bounds to prevent extreme weights
   - ✅ Default reputation fallback for new users

3. **Batch Size Limits**
   - ✅ `MAX_BATCH_SIZE = 200` prevents out-of-gas in batch settlements

4. **Role-Based Access Control**
   - ✅ `AccessControl` implemented across all contracts
   - ✅ Separate roles for admin, resolver, treasury, pauser

5. **Overflow/Underflow Protection**
   - ✅ Solidity 0.8.20+ automatic protection
   - ✅ Careful use of `unchecked` only in optimization loops

6. **Slashing Mechanisms**
   - ✅ `VerifierSlashing.sol` for advanced penalty handling
   - ✅ Cooldown periods between slashes
   - ✅ Max slash percentage caps

---

## 🚨 Critical Action Items

### Before Mainnet Deployment

**Priority 1 (Blocking):**
1. [ ] Implement multi-signature control for ADMIN_ROLE
   - Minimum 3-of-5 multisig required
   - No admin actions without quorum
2. [ ] Add settlement withdrawal cooldown periods
   - Implement 3-day withdrawal delay
   - Prevent front-running of slashing
3. [ ] Implement oracle diversity
   - Support multiple oracle sources
   - Fallback mechanisms if one oracle fails
4. [ ] Add oracle staleness checks
   - Track oracle update times
   - Reject votes if oracle data is stale

**Priority 2 (Very Important):**
5. [ ] Implement commit-reveal voting
   - Phase 1: Users commit to vote without revealing choice
   - Phase 2: Users reveal vote after all commits are done
   - Prevents front-running and order manipulation
6. [ ] Add governance delays (timelock)
   - All parameter changes require 48-72 hour delay
   - Community can react to malicious parameter changes
7. [ ] Implement Sybil resistance
   - Require on-chain identity (ENS, etc.)
   - Time-lock new accounts (reduce voting power for 30 days)
   - Daily voting caps per account
8. [ ] Add resolver committee
   - Require 3+ signatures for claim settlement
   - Implement resolution disputes

**Priority 3 (Important):**
9. [ ] Implement automated testing for edge cases
   - Integer overflow/underflow tests
   - Role permission tests
   - Batch operation tests
10. [ ] Add comprehensive event logging
    - Log all critical operations
    - Enable off-chain verification and auditing

---

## 🔍 Recommended Audit Checklist

### Pre-Audit Preparation

- [ ] All contracts reviewed for reentrancy patterns
- [ ] All external calls follow checks-effects-interactions pattern
- [ ] All state-changing functions have appropriate guards
- [ ] All role-based functions have proper authorization
- [ ] All loops have appropriate gas limits
- [ ] All arithmetic is protected from overflow/underflow
- [ ] All oracle interactions are validated
- [ ] All token transfers are wrapped in try-catch
- [ ] All critical functions emit events
- [ ] All events include all relevant data

### Audit Scope

1. **Contract Security**
   - Reentrancy vulnerability scans
   - Access control validation
   - Integer arithmetic safety
   - State consistency checks

2. **Economic Security**
   - Incentive structure analysis
   - Sybil attack feasibility
   - Economic manipulation scenarios

3. **Oracle Security**
   - Oracle design review
   - Reputation score validation
   - Staleness detection
   - Fallback mechanisms

4. **Governance Security**
   - Admin function audit
   - Role permission review
   - Parameter change procedures
   - Emergency pause mechanisms

---

## 📋 Deployment Checklist

### Before Mainnet Launch

- [ ] Security audit completed and approved
- [ ] All critical items from "Action Items" section implemented
- [ ] Multi-signature setup configured and tested
- [ ] Oracle selection and whitelisting completed
- [ ] Reputation system initialized with seed data
- [ ] Token distribution verified
- [ ] Initial staking parameters configured
- [ ] Settlement thresholds calibrated
- [ ] Monitoring and alerting systems deployed
- [ ] Incident response plan documented
- [ ] Community communication about risks prepared

---

## 🔐 Operational Guidelines

### For Protocol Maintainers

1. **Monthly Security Reviews**
   - Review slashing incidents for patterns
   - Monitor reputation score distributions
   - Check oracle performance metrics
   - Analyze claim resolution patterns

2. **Quarterly Audits**
   - External security audit
   - Reputation system audit
   - Economic analysis
   - Governance efficiency review

3. **Emergency Procedures**
   - Pause mechanisms for critical issues
   - Settlement emergency replacement
   - Oracle replacement procedures
   - Admin key rotation process

---

## 📚 Resources & References

- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [OWASP Smart Contract Top 10](https://owasp.org/www-project-smart-contract-top-10/)
- [Ethereum.org Security Guidelines](https://ethereum.org/en/developers/docs/security/)
- [The Defiant: Smart Contract Vulnerabilities](https://thedefiant.io/)

---

## 📝 Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | March 2026 | Initial threat model creation |

---

## 🤝 Feedback & Updates

This threat model should be updated as:
- New functionality is added
- Security audits reveal new findings
- Economic attacks emerge in the wild
- Governance structure is finalized

Submit threat model updates via: [process TBD]

---

**Classification:** Public  
**Audience:** Developers, Auditors, Governance  
**Review Cadence:** Quarterly or when material changes occur
