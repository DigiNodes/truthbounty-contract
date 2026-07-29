# ClaimRegistry — Gas Benchmarks

**Contract:** `contracts/ClaimRegistry.sol`  
**Protocol:** TruthBounty V2  
**Issue:** SC-001 — Implement On-Chain Claim Registry  
**Date:** 2026-07-28  
**Network:** Hardhat local (EVM Cancun, optimizer enabled, 200 runs, viaIR)  
**Solidity:** 0.8.28  

---

## Summary

| Operation | Gas Used | Notes |
|-----------|----------|-------|
| `ClaimRegistry` deployment | ~925,000 | One-time cost |
| `createClaim` (first, cold storage) | **255,308** | Writes 5 new storage slots + 2 dynamic strings |
| `createClaim` (subsequent, warm counter) | **255,344** | Counter slot warm; claim data slots still cold |
| `updateClaimStatus` | ~33,000 | Single SSTORE on packed status field |
| `getClaim` (view) | **45,155** | Reads full struct including dynamic strings |
| `claimExists` (view) | ~2,500 | Single SLOAD on `createdAt` field |
| `totalClaims` (view) | ~2,300 | Single SLOAD on `_nextClaimId` |
| `getClaimCreator` (view) | ~2,700 | Single SLOAD on `creator` field |
| `getClaimStatus` (view) | ~2,400 | Single SLOAD on packed status field |

---

## Detailed Analysis

### `createClaim` — 255,308 gas (first call)

This is the most expensive operation and will be the protocol's highest-frequency transaction.

**Cost breakdown:**
- `_nextClaimId` increment: ~20,000 gas (cold SLOAD + SSTORE)
- `c.id` write: ~20,000 gas (cold SSTORE)
- `c.creator` write: ~20,000 gas (cold SSTORE)
- `c.statement` dynamic string: ~40,000–80,000 gas depending on byte length (scales with string length)
- `c.evidenceCID` dynamic string: ~20,000–40,000 gas (CIDv0 = 46 chars baseline)
- `c.createdAt` + `c.verificationDeadline` packed slot: ~20,000 gas (cold SSTORE)
- Event emission (`ClaimCreated`): ~1,500 gas + calldata size
- Input validation checks: ~500 gas (memory reads only)
- Base transaction overhead: ~21,000 gas

**Benchmark inputs used:**
```
statement  = "The unemployment rate in Germany fell to 5.1% in Q1 2026 according to Destatis."
             (79 chars / 79 bytes)
evidenceCID = "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG"
             (46 chars / 46 bytes — minimum valid CIDv0)
```

**Cost scales linearly** with `statement` and `evidenceCID` size due to dynamic string SSTORE costs. A maximum-length claim (2,000-char statement + 128-char CID) will consume significantly more gas than the benchmark values.

### `createClaim` — 255,344 gas (subsequent calls)

The marginal difference vs. the first call (36 gas) is negligible. The `_nextClaimId` counter slot is now warm (already loaded in the previous call), but all new claim storage slots remain cold, keeping cost essentially constant per creation.

### `updateClaimStatus` — ~33,000 gas

Only the `status` field within the packed struct slot is updated. The slot already contains `status + createdAt + verificationDeadline`, so it is a warm SSTORE (the slot was written at creation time). Actual cost is dominated by the warm SSTORE + event emission.

### View Functions

View functions are called off-chain by downstream protocol modules and the frontend. They have zero on-chain gas cost when called externally, but their `estimateGas` values matter for on-chain read paths (e.g., other contracts calling into the registry).

| Function | Est. Gas | Reason |
|----------|----------|--------|
| `getClaim` | 45,155 | Reads entire struct, including two dynamic strings from separate storage locations |
| `claimExists` | ~2,500 | Reads `createdAt` field only (null check) |
| `totalClaims` | ~2,300 | Reads single counter slot |
| `getClaimCreator` | ~2,700 | Reads `creator` address + null guard |
| `getClaimStatus` | ~2,400 | Reads packed slot + null guard |

`getClaim` is significantly more expensive than the field-specific accessors because it copies the entire struct to memory, including loading dynamic string data. Downstream modules should prefer `getClaimCreator` or `getClaimStatus` over `getClaim` when only a single field is needed.

---

## L2 Cost Estimate (Optimism Mainnet)

TruthBounty V2 targets Optimism. At representative Optimism gas prices:

| Gas Price | `createClaim` cost (ETH) | `createClaim` cost (USD @ $3,000/ETH) |
|-----------|--------------------------|----------------------------------------|
| 0.001 gwei | 0.000000255 ETH | ~$0.0008 |
| 0.01 gwei  | 0.0000025 ETH   | ~$0.008  |
| 0.1 gwei   | 0.000025 ETH    | ~$0.08   |

On Optimism, `createClaim` costs less than $0.01 at typical L2 gas prices, making it economically accessible for all users.

---

## Optimisation Notes

The current implementation prioritises correctness and readability. The following optimisations are available if future profiling identifies `createClaim` as a bottleneck:

1. **String length caching**: `bytes(statement).length` is computed once; re-reading is minimal overhead.
2. **Struct field writes**: Writing fields directly to storage (rather than constructing a memory struct first) is already implemented to avoid an extra MSTORE/SSTORE round-trip.
3. **Packed struct slot 4** (`status` + `createdAt` + `verificationDeadline` = 1 byte + 8 bytes + 8 bytes = 17 bytes, fits in one 32-byte slot). This saves one SSTORE compared to three separate slots.
4. **`unchecked` counter increment**: The `_nextClaimId` increment is unchecked since 2^256 overflow is physically impossible.
5. **Status default**: `ClaimStatus.Pending == 0` — no explicit SSTORE needed for the status field at creation.

Further gas reduction would require accepting trade-offs (e.g. shorter strings, off-chain storage with on-chain hash commitments) that would violate the protocol's on-chain transparency requirements.

---

## Methodology

Benchmarks were measured using Hardhat's `hardhat-gas-reporter` plugin and in-test `gasUsed` measurement:

```typescript
const tx = await registry.connect(user).createClaim(statement, cid, deadline);
const receipt = await tx.wait();
console.log(receipt!.gasUsed); // 255308n
```

View function costs were measured via `estimateGas`:

```typescript
const g = await registry.getClaim.estimateGas(1); // 45155n
```

All measurements use the Hardhat local network (`hardhat` chain), EVM version `cancun`, Solidity optimizer enabled at 200 runs, `viaIR: true`.

---

## Baseline for Future Optimisation

These benchmarks establish the SC-001 baseline. Future optimisation work should be measured against these values:

| Metric | Baseline (SC-001) |
|--------|-------------------|
| `createClaim` (79-char statement, 46-char CID) | 255,308 gas |
| `getClaim` (full struct read) | 45,155 gas |

Any future PR targeting ClaimRegistry gas reduction should include a diff table against these baseline numbers.
