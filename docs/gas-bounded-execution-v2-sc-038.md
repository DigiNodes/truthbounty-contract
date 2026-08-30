# Gas, Bounded Execution, and DoS Limits (V2-SC-038)

## Overview

V2-SC-038 establishes canonical execution bounds, critical-path gas budgets, pull-based
settlement, and a loop catalog so permissionless finalization remains executable at
maximum configured participation.

## New Components

| Path | Role |
|------|------|
| `contracts/performance/ProtocolExecutionBounds.sol` | Canonical max participant/page constants |
| `contracts/performance/GasBudgetRegistry.sol` | Published gas budgets for 9 critical operations |
| `contracts/performance/PullSettlementLedger.sol` | Pull-based credits/withdrawals (no push batch dependency) |
| `contracts/performance/LoopBoundsCatalog.sol` | On-chain loop inventory with defensible bounds |
| `config/gas-budgets.json` | CI regression threshold source of truth |

## Critical-Path Gas Budgets

| Operation | Budget (gas) | Max-config bound |
|-----------|-------------|------------------|
| Claim creation | 350,000 | Max statement + CID |
| Evidence attachment | 180,000 | `MAX_CID_LENGTH` |
| Verification vote | 350,000 | Reputation snapshot path |
| Aggregation | 600,000 | 200 verifiers |
| Provisional settlement | 250,000 | Single pull credit |
| Challenge open | 120,000 | Lifecycle transition |
| Appeal settlement | 650,000 | Appeal aggregation path |
| Finalization | 200,000 | Status finalization |
| Withdrawal | 120,000 | Pull payout |

Budgets must remain below `RECOMMENDED_TX_GAS_CEILING` (12M) and reference block limit (30M).

## DoS Mitigations

- **Pull settlement**: `PullSettlementLedger` credits off-chain finalization; token transfer
  occurs only on recipient-initiated `withdraw()`. Hostile recipients cannot block others.
- **Evidence cap**: `EvidenceManager.MAX_EVIDENCE_PER_CLAIM = 100` bounds storage growth per claim.
- **Batch caps**: Settlement, reward, tokenomics, and insurance modules retain hard batch limits
  aligned with `ProtocolExecutionBounds`.

## Loop Inventory (summary)

All unbounded iteration paths either have a hard `MAX_*` cap or paginated pull semantics.
See `LoopBoundsCatalog` for the canonical on-chain catalog (12 entries).

## Reuse / Replace / Deprecate

| Path | Status |
|------|--------|
| `TruthBountyClaims.settleClaimsBatch` | **Legacy push** — bounded but push-based; prefer `PullSettlementLedger` for V2 |
| `VerificationAggregation.sol` | **Reused** — aggregation loop bounded by `MAX_VERIFICATION_COUNT` |
| `EvidenceManager.sol` | **Enhanced** — added `MAX_EVIDENCE_PER_CLAIM` |
| `contracts/performance/*` | **New canonical V2-SC-038** |

## CI Regression

- `config/gas-budgets.json` mirrors on-chain `GasBudgetRegistry` defaults.
- `test/GasBoundedExecution.t.sol` validates batch bounds, pull isolation, and withdrawal budget.
- Existing `.github/workflows/gas-check.yml` continues Hardhat gas snapshot comparison.

## Security Notes

- No accounting or authorization weakened for gas savings.
- Storage growth bounded per claim for evidence and verifications.
- Griefing cost for evidence spam: O(n) storage at attacker expense up to cap.
