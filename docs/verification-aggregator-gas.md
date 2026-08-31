# VerificationAggregator Gas Benchmarks

Gas measurements for the SC-005 weighted verification aggregation engine.

Measured with `REPORT_GAS=true npx hardhat test test/VerificationAggregator.test.ts`
(Solidity 0.8.28, viaIR optimizer, 200 runs, EDR).

## Results

| Function | Min | Max | Avg | Calls |
|----------|-----|-----|-----|-------|
| `aggregateClaim` (incl. full weight loop) | 90,474 | 252,392 | 157,992 | 40 |
| `setThresholds` | – | – | 75,081 | 2 |
| `setVerificationSource` | – | – | 30,832 | 2 |

## Notes

- `aggregateClaim` gas scales linearly with the number of verifications because
  it iterates the claim's voter list once (`calculateWeights`). The variance is
  driven by the stress test with 10 voters (upper bound).
- `calculateWeights` / `calculateConfidence` / `getAggregation` are view
  functions and therefore free for external callers.
- Determinism: the loop only accumulates `trueWeight` / `falseWeight` — output
  is independent of voter iteration order, so gas and results are reproducible
  across all nodes.
