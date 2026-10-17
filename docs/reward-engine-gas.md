# Reward Engine Gas Benchmarks

SC-011 introduces deterministic reward allocation, Treasury-backed funding, immediate payouts, claimable rewards, batched allocation, batched claiming, duplicate settlement protection, and auditable distribution records.

## Accounting invariants

Engine token balance + total distributed = total funded

Available reward balance + total reserved = engine token balance

Total allocated = total distributed + total reserved

Claiming moves value from totalReserved to totalDistributed without changing totalAllocated.

## Safety properties

- Rewards cannot exceed the available reward pool.
- A settlement reward cannot be allocated twice.
- Only authorized distributors may allocate rewards.
- Only the intended recipient may claim a reward.
- State changes occur before external token transfers.
- Failed transfers revert atomically.
- Batch sizes are capped to prevent unbounded gas consumption.

## Gas measurements

allocateReward: 353,893 gas
claimReward: 103,287 gas

Measured using:

npx hardhat test test/RewardEngine.fuzz.test.ts
