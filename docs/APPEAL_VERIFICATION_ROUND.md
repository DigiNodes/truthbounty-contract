# Appeal Verification Round (`SC-017`)

## 1. Overview

The **AppealVerificationRound** contract manages the second-round verification lifecycle for claims undergoing disputes. When a provisional consensus outcome is disputed, an appeal round is opened with heightened economic security parameters (higher minimum stake, multiplier, and weight caps).

```
┌─────────────────────────────────────────────────────────────┐
│                 Appeal Round Lifecycle                      │
│                                                             │
│   ┌───────────────────────┐                                 │
│   │   Provisional Dispute │                                 │
│   └──────────┬────────────┘                                 │
│              │ openAppealRound(claimId)                     │
│              ▼                                              │
│   ┌───────────────────────┐   submitAppealVote(...)         │
│   │   Appeal Round OPEN   │◄─────────────────────────────┐  │
│   └──────────┬────────────┘ (Heightened Stake & Custody) │  │
│              │ block.timestamp >= round.deadline         │  │
│              ▼                                              │
│   ┌───────────────────────┐   closeAppealRound(claimId)     │
│   │  Appeal Round CLOSED  ├──────────────────────────────►  │
│   └──────────┬────────────┘                                 │
│              │ implements IVerificationSource               │
│              ▼                                              │
│   ┌───────────────────────┐                                 │
│   │VerificationAggregator │ (Computes Final Appeal Consensus│
│   └───────────────────────┘                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Core Protocol Invariants

1. **Single Appeal Guarantee**:
   - At most one appeal round can be opened per disputed claim (`AppealRoundAlreadyExists`).
2. **Storage Isolation**:
   - First-round verifier stakes and voting states are completely separated from appeal round voting mappings.
3. **Immutable Frozen Round Parameters**:
   - Parameters (`minStakeAmount`, `stakeMultiplierBps`, `maxWeightCap`, `deadline`) are snapshotted when the round is opened. Subsequent global config changes do not retroactively alter active appeal rounds.
4. **One Address One Position**:
   - Verifiers may cast at most one position in the appeal round.
5. **Stake Custody**:
   - Verifier stakes are safely transferred into the contract vault via `SafeERC20.safeTransferFrom`.
6. **Aggregation Ready**:
   - Fully implements `IVerificationSource` (`getClaimVoterCount`, `getClaimVoterAt`, `getVoteData`) for direct aggregation via `VerificationAggregator`.

---

## 3. Interfaces & Storage

### Structs

```solidity
struct AppealRound {
    uint256 claimId;
    AppealRoundStatus status;     // NONE, OPEN, CLOSED
    uint256 openedAt;
    uint256 deadline;
    uint256 minStakeAmount;
    uint256 stakeMultiplierBps;
    uint256 maxWeightCap;
    uint256 totalTrueStake;
    uint256 totalFalseStake;
    uint256 totalTrueWeight;
    uint256 totalFalseWeight;
    uint256 verifierCount;
}

struct AppealVote {
    bool voted;
    bool support;
    uint256 stakeAmount;
    uint256 effectiveStake;
    uint256 timestamp;
}
```

### Events

- `AppealRoundOpened(uint256 indexed claimId, uint256 deadline, uint256 minStake, uint256 multiplierBps, address indexed openedBy)`
- `AppealVoteSubmitted(uint256 indexed claimId, address indexed verifier, bool support, uint256 stakeAmount, uint256 effectiveWeight)`
- `AppealRoundClosed(uint256 indexed claimId, uint256 totalTrueWeight, uint256 totalFalseWeight, uint256 verifierCount, address indexed closedBy)`
- `DefaultAppealConfigUpdated(uint256 duration, uint256 minStake, uint256 multiplierBps, uint256 maxWeightCap)`
