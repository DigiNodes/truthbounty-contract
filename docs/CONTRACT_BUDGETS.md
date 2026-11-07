# Contract Size, Gas and Calldata Budgets (PREWAVE-SC-009)

Reviewed budgets for the canonical V2 operations: `claim`, `commit`, `reveal`,
`dispute`, `appeal`, `settlement`, `rewards`, `governance`, `pause`.

| File | Purpose |
|------|---------|
| `config/contract-budgets.json` | Per-operation gas ceiling, calldata model, worst case, and reviewed `overrides` |
| `config/contract-budget-baseline.json` | Last reviewed values; increases over it are regressions |
| `config/gas-budgets.json` | Shared gas budgets and batch bounds (a ceiling here can never exceed these) |
| `config/deployment-size-budgets.json` | Deployment size limits (must stay within EIP-170) |
| `scripts/check-contract-budgets.mjs` | The gate; run with `npm run check:contract-budgets` |

## What the gate enforces

- Every required operation has a gas ceiling and calldata ceiling; a missing or unknown operation fails closed.
- `maxGas` is at most the matching `gas-budgets.json` budget and the transaction gas ceiling.
- Worst-case calldata is derived, not guessed:
  `selector + (fixedWords + dynamicArrays * 2 + perItemWords * bound) * 32`, using the
  bounds in `gas-budgets.json`. It must fit the reviewed `maxBytes` and the policy cap.
- Deployment size hard limits stay within the network limit.
- Evidence (git commit, SHA-256 of every input, derived values, toolchain pins) is written to
  `deployments/releases/contract-budget-evidence.json` and uploaded by CI.

## Changing a budget

1. Raise the value in `config/contract-budgets.json`.
2. Add an `overrides` entry: `{ operation, field, from, to, rationale, reviewer }` where `field` is
   `maxGas` or `maxCalldataBytes`, `from` is the baseline value and `to` the new one. The rationale
   must be at least 20 characters and a reviewer is required.
3. After review merges, refresh the baseline with `npm run check:contract-budgets:baseline` and clear the override.

Overrides that match no regression fail the gate, so stale rationale cannot linger.

## Optimism fee context

Execution gas is charged at the L2 gas price; calldata also drives the L1 data fee. These budgets make no
price promises. Consumers must read live fee parameters and must not estimate canonical outcomes from them.

## Scope

This gate checks reviewed configuration and derived bounds offline. It does not change storage layout, roles,
pause, upgrade or economics. Measured gas for each operation is still produced by the Foundry scenario
snapshots (`npm run check:gas:sc064`).
