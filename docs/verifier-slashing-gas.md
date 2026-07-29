# Verifier Slashing Gas Benchmarks

Benchmarks were measured with the Hardhat local network using the SC-015 claim-aware slashing implementation.

## Results

| Operation | Gas Used |
|---|---:|
| Partial slash, 25% | 410,025 |
| Full slash, 100% | 400,389 |

## Covered Properties

- Deterministic partial-slash calculations
- Full collateral confiscation
- Treasury settlement
- Duplicate-offence prevention
- Reputation notification
- Locked-stake accounting invariant
- Invalid percentage boundaries

## Accounting Invariant

For each verifier:

Initial Locked Stake
=
Remaining Locked Stake
+
Total Slashed

Treasury token increases must equal the total confiscated collateral.
