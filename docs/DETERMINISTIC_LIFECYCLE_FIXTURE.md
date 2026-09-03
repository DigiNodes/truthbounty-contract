# Deterministic Local End-to-End Lifecycle Fixture (`SC-035`)

## 1. Overview

The **Deterministic Local End-to-End Lifecycle Fixture** provides a reusable testing environment for executing and verifying complete protocol claim lifecycles across canonical TruthBounty V2 modules.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       Canonical Lifecycle Journeys                      │
│                                                                         │
│  [1. Claim Creation]  ──►  [2. Verification Voting]                     │
│                                   │                                     │
│                                   ▼                                     │
│                           [3. Provisional Settlement]                   │
│                                   │                                     │
│                  ┌────────────────┴────────────────┐                    │
│                  ▼                                 ▼                    │
│     [Undisputed Path]                    [Dispute / Appeal Path]        │
│    Challenge Window Expires               Appeal Round Opened           │
│           │                                       │                     │
│           ▼                                       ▼                     │
│     Finalized Consensus                   Second-Round Voting           │
│                                                   │                     │
│                                                   ▼                     │
│                                           Appeal Aggregated             │
│                                                   │                     │
│                                                   ▼                     │
│                                           Final Dispute Resolution      │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Supported Journeys

1. **Journey 1: Undisputed True Claim**:
   - Claim creation -> First-round voting (True) -> Verification deadline -> Provisional settlement (True) -> Challenge window expires -> Finalized True.
2. **Journey 2: Undisputed False Claim**:
   - Claim creation -> First-round voting (False) -> Verification deadline -> Provisional settlement (False) -> Challenge window expires -> Finalized False.
3. **Journey 3: Inconclusive Consensus**:
   - Zero verifier votes or tied weights -> Inconclusive settlement.
4. **Journey 4: Successful Challenge & Appeal Overturn (False -> True)**:
   - Provisional False outcome -> Disputed by challenger -> Appeal round opened with 1.5x multiplier -> Appellants vote True with higher stake -> Appeal deadline expires -> Aggregation overturns outcome to True.
5. **Journey 5: Failed Challenge & Appeal Affirmation (True -> True)**:
   - Provisional True outcome -> Disputed -> Appeal votes confirm True.

---

## 3. Usage

```typescript
import { deployLifecycleFixture } from "./test/fixtures/lifecycleFixture";

const env = await deployLifecycleFixture();
const { claimId } = await env.helpers.createClaim("Decentralized claim statement");
await env.helpers.stakeAndVote(claimId, env.accounts.verifier1, true, env.constants.MIN_STAKE);
await env.helpers.executeProvisionalSettlement(claimId);
```
