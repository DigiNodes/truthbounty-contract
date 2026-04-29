# TruthBounty Protocol Specification

## 📚 Overview

TruthBounty is a decentralized protocol for fact verification that uses economic incentives and reputation-weighted voting to determine the truthfulness of claims.

This document is the **single authoritative reference** for the contract architecture. It defines which contracts are canonical, which are deprecated, and how all modules fit together.

---

## ⚠️ Canonical vs Deprecated Paths

This section must be read before integrating with any TruthBounty contract.

### Canonical Contracts (use these)

| Contract | Role | Notes |
|----------|------|-------|
| `TruthBountyWeighted` | **Primary protocol entry point** — claim lifecycle, staking, voting, settlement | Supersedes `TruthBounty` |
| `TruthBountyToken` | ERC20 token only | Do **not** call `stake`/`withdrawStake`/`slashVerifier` on this contract directly (see below) |
| `Staking` | Standalone lock-duration staking, used by `VerifierSlashing` | Only relevant for the admin-slash path |
| `VerifierSlashing` | Admin-initiated slashing with cooldown and history | Calls `Staking.forceSlash`; requires `RESOLVER_ROLE` |
| `WeightedStaking` | Reputation-weight calculator (pure utility, no token custody) | Called internally by `TruthBountyWeighted` |
| `TruthBountyClaims` | Treasury-controlled batch token payout | **Not** a claim lifecycle contract despite the name; used for off-chain-resolved reward disbursement only |

### Deprecated / Do Not Use

| Contract | Why deprecated | Migration |
|----------|---------------|-----------|
| `TruthBounty` | Superseded by `TruthBountyWeighted`; lacks reputation weighting, uses unweighted vote totals | Use `TruthBountyWeighted` for all new integrations |
| `TruthBountyToken.stake` / `TruthBountyToken.withdrawStake` / `TruthBountyToken.slashVerifier` | Inline staking on the token contract creates a parallel, untracked stake pool with no claim linkage | Call `TruthBountyWeighted.stake` / `TruthBountyWeighted.withdrawStake` instead |
| `ExampleSettlement` | Demo contract only; not audited for production use | Reference only |

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    CANONICAL FLOW                           │
│                                                             │
│  Verifier ──stake()──► TruthBountyWeighted ◄──token──► TruthBountyToken (ERC20)
│                              │                              │
│                         vote()                              │
│                              │                              │
│                    WeightedStaking ◄──── IReputationOracle  │
│                              │                              │
│                       settleClaim()                         │
│                              │                              │
│                  claimSettlementRewards()                   │
│                  withdrawSettledStake()                     │
│                                                             │
│  Admin ──slash()──► VerifierSlashing ──forceSlash()──► Staking
│                                                             │
│  Treasury ──settleClaimsBatch()──► TruthBountyClaims        │
└─────────────────────────────────────────────────────────────┘
```

### What each module owns

| Concern | Owned by | Notes |
|---------|----------|-------|
| Verifier staking (deposit/withdraw) | `TruthBountyWeighted` | Tracks `totalStaked` and `activeStakes` per verifier |
| Claim lifecycle (create/vote/settle) | `TruthBountyWeighted` | Single source of truth for claim state |
| Reputation-weighted vote power | `WeightedStaking` + `IReputationOracle` | Called during `vote()` |
| Automatic slashing on losing vote | `TruthBountyWeighted._calculateSettlement` | Applied at settlement, no external call needed |
| Admin-initiated slashing (out-of-band) | `VerifierSlashing` → `Staking` | For governance/dispute resolution outside normal flow |
| Batch reward disbursement (off-chain resolved) | `TruthBountyClaims` | Treasury-gated; independent of claim lifecycle |
| Token minting / ERC20 | `TruthBountyToken` | No staking logic should be called here |

---

## 🔄 Claim Lifecycle (Canonical)

All steps go through `TruthBountyWeighted`.

```
1. createClaim(content)
      └─ assigns claimId, opens 7-day verification window

2. stake(amount)                          ← deposit before voting
      └─ transfers tokens into TruthBountyWeighted
      └─ increments verifierStakes[msg.sender].totalStaked

3. vote(claimId, support, stakeAmount)
      └─ fetches reputationScore from oracle (fallback: 1.0)
      └─ effectiveStake = stakeAmount × reputationScore / 1e18
      └─ locks stakeAmount in activeStakes
      └─ updates claim.totalWeightedFor / totalWeightedAgainst

4. settleClaim(claimId)                   ← callable by anyone after window closes
      └─ outcome: totalWeightedFor / totalWeighted ≥ 60% → passed
      └─ assigns per-vote slashAmount to each loser (20% of raw stake)
      └─ stores SettlementResult

5a. claimSettlementRewards(claimId)       ← winners only
      └─ reward = effectiveStake / winnerWeightedStake × totalRewards
      └─ returns full raw stake + reward

5b. withdrawSettledStake(claimId)         ← losers only
      └─ returns rawStake − slashAmount
```

---

## 💰 Economic Parameters

| Parameter | Default | Governance-controlled |
|-----------|---------|----------------------|
| Verification window | 7 days | Yes |
| Minimum stake | 100 BOUNTY | Yes |
| Settlement threshold | 60% | Yes |
| Slash percentage | 20% | Yes |
| Reward percentage | 80% of slash | Yes |
| Reputation min/max | 0.1 / 10.0 | Yes |

Effective stake formula:
```
effectiveStake = rawStake × clampedReputationScore / 1e18
```

---

## 👥 Roles and Access Control

```
DEFAULT_ADMIN_ROLE
└── ADMIN_ROLE
    ├── RESOLVER_ROLE   — settlement, slashing
    ├── TREASURY_ROLE   — TruthBountyClaims payouts
    └── PAUSER_ROLE     — emergency pause
```

| Role | Granted to |
|------|-----------|
| `ADMIN_ROLE` | Protocol deployer / multisig |
| `RESOLVER_ROLE` | `VerifierSlashing` contract (for admin slash path) |
| `TREASURY_ROLE` | Protocol treasury (for `TruthBountyClaims`) |
| `PAUSER_ROLE` | Protocol administrators |

---

## 🔒 Security Invariants

1. `totalStaked ≥ activeStakes` for every verifier at all times
2. One vote per verifier per claim; no re-votes
3. Claims settle exactly once (`settled` flag)
4. Total rewards distributed ≤ `totalSlashed × rewardPercent / 100`
5. `VerifierSlashing` enforces a 1-hour cooldown between slashes per verifier
6. All state-changing functions use `nonReentrant`

---

## 🔗 Contract Interactions

### Normal verification flow
```
User → TruthBountyWeighted.createClaim()
Verifier → TruthBountyWeighted.stake()
Verifier → TruthBountyWeighted.vote() → WeightedStaking → IReputationOracle
Anyone → TruthBountyWeighted.settleClaim()
Winner → TruthBountyWeighted.claimSettlementRewards()
Loser → TruthBountyWeighted.withdrawSettledStake()
```

### Admin slash flow (out-of-band)
```
Admin/Resolver → VerifierSlashing.slash() → Staking.forceSlash()
```

### Off-chain resolved batch payouts
```
Treasury → TruthBountyClaims.settleClaimsBatch()
```

---

## ⚙️ Deployment

Deploy in this order:

1. `TruthBountyToken` (initialAdmin)
2. `IReputationOracle` implementation
3. `WeightedStaking` (reputationOracle, admin, governanceController)
4. `TruthBountyWeighted` (token, reputationOracle, admin, governanceController)
5. `Staking` (token, lockDuration, admin)
6. `VerifierSlashing` (staking, admin, governanceController)
   - Call `Staking.setSlashingContract(verifierSlashing)`
   - Grant `RESOLVER_ROLE` on `VerifierSlashing` to the settlement contract if needed
7. `TruthBountyClaims` (token, admin)
   - Fund with BOUNTY tokens for batch payouts

Do **not** deploy `TruthBounty` for new environments. It exists only for legacy compatibility.

---

## 📝 Glossary

| Term | Definition |
|------|-----------|
| Claim | A statement submitted for truth verification |
| Verifier | A participant who stakes tokens to vote on claims |
| Effective stake | Raw stake × reputation score |
| Settlement | Determining claim outcome after verification window |
| Slashing | Penalty applied to verifiers who voted against majority |
| Canonical contract | The authoritative implementation to use |
| Deprecated path | A code path that must not be used in new integrations |

---

*Last updated to reflect canonical architecture. `TruthBounty` (unweighted) and inline token staking are deprecated. All new integrations must use `TruthBountyWeighted`.*
