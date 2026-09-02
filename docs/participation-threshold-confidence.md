# Participation Threshold and Confidence Rules (V2-SC-014)

## Overview

V2-SC-014 adds deterministic participation-threshold and confidence evaluation on top of
the weighted aggregation outputs from V2-SC-013. Thresholds are read from each round's
**frozen configuration** so governance cannot retroactively change an open round.

## Components

| Path | Role |
|------|------|
| `contracts/verification/ParticipationThresholdTypes.sol` | Shared enums, frozen config, evaluation structs |
| `contracts/verification/ParticipationConfidenceRules.sol` | Pure library implementing threshold + confidence math |
| `contracts/verification/FrozenRoundConfigStore.sol` | Immutable per-round config registry |
| `contracts/verification/ParticipationThresholdEngine.sol` | On-chain evaluator emitting reason-coded results |

## Confidence Formula

For conclusive outcomes only:

```
confidenceBps = winningWeight * 10_000 / totalWeight   // floor division
```

Inconclusive outcomes always expose `confidenceBps = 0`.

## Inconclusive Reason Codes

| Code | Meaning |
|------|---------|
| `ZERO_PARTICIPATION` | No effective weight or verifiers |
| `INSUFFICIENT_VERIFIER_COUNT` | Below frozen minimum count |
| `INSUFFICIENT_TOTAL_WEIGHT` | Below frozen minimum total weight |
| `INSUFFICIENT_CONFIDENCE` | Winning side below confidence threshold |
| `TIE` | Equal true/false weights after participation gates |

## Appeal Multiplier

Appeal rounds scale **minimum verifier count** and **minimum total weight** using the
frozen `appealMultiplierBps` with ceiling rounding (stricter thresholds). Confidence
minimum is not scaled.

## Reuse / Replace / Deprecate

| Path | Status |
|------|--------|
| `contracts/VerificationAggregation.sol` | **Legacy** — global thresholds, no reason codes |
| `contracts/VerificationAggregator.sol` | **Legacy** — reverts instead of reason-coded inconclusive |
| `contracts/verification/*` (this issue) | **Canonical V2-SC-014** |

## Security Notes

- Basis-point bounds validated at freeze time (`minConfidenceBps <= 10_000`).
- Multiplication order: `winningWeight * 10_000` before division by `totalWeight`.
- Rounding direction documented: floor for confidence, ceiling for scaled minimums.
- Frozen configs cannot be overwritten once a round is open.
