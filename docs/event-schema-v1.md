# TruthBounty event schema v1

The canonical event declarations are defined in `contracts/interfaces/ITruthBountyEvents.sol`. Every event carries a `uint16 version` value of `1` and a block-context `uint64 timestamp`.

## Claims

- `ClaimCreated`: claim ID, actor, metadata hash, timestamp, version.
- `ClaimUpdated`: claim ID, actor, metadata hash, timestamp, version.
- `ClaimResolved`: claim ID, actor, outcome, timestamp, version.
- `ClaimFinalized`: claim ID, actor, timestamp, version.

## Verification

- `VerificationSubmitted`: claim ID, verifier, support flag, stake amount, timestamp, version.
- `VerificationChallenged`: claim ID, challenger, reason hash, timestamp, version.

## Staking and slashing

- `StakeDeposited`: verifier, amount, resulting balance, timestamp, version.
- `StakeWithdrawn`: verifier, amount, resulting balance, timestamp, version.
- `SlashExecuted`: claim ID, verifier, reason hash, amount, timestamp, version.

## Rewards and treasury

- `RewardCalculated`: claim ID, recipient, amount, timestamp, version.
- `RewardEscrowed`: claim ID, recipient, amount, timestamp, version.
- `RewardClaimed`: claim ID, recipient, amount, timestamp, version.
- `TreasuryTransfer`: operation ID, token, recipient, amount, timestamp, version.

## Governance and emergency

- `GovernanceProposalCreated`: proposal ID, proposer, metadata hash, timestamp, version.
- `GovernanceProposalExecuted`: proposal ID, executor, timestamp, version.
- `EmergencyPauseActivated`: actor, reason hash, timestamp, version.
- `EmergencyPauseRecovered`: actor, timestamp, version.

The first three indexed parameters are chosen for entity, actor, and reason or metadata filtering where applicable. Consumers must use the complete event signature because event names may coexist with legacy signatures during migration.