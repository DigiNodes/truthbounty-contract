# Provisional Settlement Engine (`SC-015`)

## 1. Overview

The **ProvisionalSettlementEngine** provides the canonical implementation for TruthBounty V2 permissionless first-round consensus settlement, deterministic outcome storage, and dispute challenge window initiation.

```
┌─────────────────────────────────────────────────────────────┐
│                 Claim Lifecycle Transition                  │
│                                                             │
│   ┌───────────────────────┐                                 │
│   │   UnderVerification   │                                 │
│   └──────────┬────────────┘                                 │
│              │ block.timestamp >= verificationDeadline      │
│              ▼                                              │
│   ┌───────────────────────┐   Reads Consensus   ┌───────┐   │
│   │   provisionalSettle   ├────────────────────►│  Agg  │   │
│   └──────────┬────────────┘                     └───────┘   │
│              │                                              │
│              ▼                                              │
│   ┌───────────────────────┐                                 │
│   │    ChallengeWindow    │ (challengeDeadline set)         │
│   │  (Funds remain locked)│                                 │
│   └───────────────────────┘                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Protocol Invariants & Safety

1. **Zero Caller Data**:
   - The aggregation outcome is computed strictly on-chain by invoking the canonical `VerificationAggregator`. The caller cannot inject or alter consensus outcomes.
2. **Deterministic Time Gating**:
   - Reverts with `VerificationWindowStillOpen` if invoked before `claim.verificationDeadline`.
3. **Single Transition**:
   - Reverts with `AlreadyProvisionallySettled` if provisional settlement has already been executed for the given `claimId`.
4. **Fund Freezing & Vault Custody**:
   - Does not release winner rewards or slash verifier stakes. All funds remain locked until the dispute window expires or an appeal round finalizes.
5. **Emergency Pause**:
   - Governed by `PAUSER_ROLE` and `GovernanceOwnable`.

---

## 3. Interfaces & Storage

### Struct: `ProvisionalOutcome`

```solidity
struct ProvisionalOutcome {
    Outcome outcome;           // VERIFIED_TRUE, VERIFIED_FALSE, INCONCLUSIVE
    uint256 confidence;        // Basis points (0 - 10,000)
    uint256 trueWeight;        // Aggregate weight supporting TRUE
    uint256 falseWeight;       // Aggregate weight supporting FALSE
    uint256 totalWeight;       // Total participating weight
    uint256 verifierCount;     // Number of unique verifiers
    uint256 challengeDeadline; // block.timestamp + challengeWindowDuration
    uint256 settledAt;         // Timestamp of provisional settlement
    uint256 parameterVersion;  // Parameter version active at settlement
    bool settled;              // Settlement flag
}
```

### Events Emitted

- `RoundAggregated(uint256 indexed claimId, Outcome outcome, uint256 confidence, uint256 trueWeight, uint256 falseWeight, uint256 totalWeight, uint256 verifierCount)`
- `ProvisionalOutcomeCreated(uint256 indexed claimId, Outcome outcome, uint256 challengeDeadline, uint256 confidence, address indexed triggeredBy)`
- `ChallengeWindowDurationUpdated(uint256 oldDuration, uint256 newDuration)`
- `AggregatorUpdated(address indexed oldAggregator, address indexed newAggregator)`
- `ParameterVersionUpdated(uint256 oldVersion, uint256 newVersion)`
