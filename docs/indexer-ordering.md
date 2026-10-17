# Deterministic event ordering

TruthBounty event consumers must process canonical logs using the following total order:

1. block number
2. transaction index
3. log index

Within one successful transaction, events are emitted only after the state mutation they describe. A consumer must not assume ordering across separate transactions beyond the canonical block ordering above.

Consumers should store the block hash with each event. When a reorganization replaces a block, all events associated with the orphaned block hash must be rolled back before events from the replacement branch are applied.

Duplicate delivery is expected in distributed systems. Consumers must make ingestion idempotent by using chain ID, transaction hash, and log index as the event identity.

Version upgrades do not change the ordering rule. Unsupported versions should be quarantined for later decoding rather than interpreted using an older schema.

## Intra-transaction event ordering

When a single call emits multiple events, the contract MUST emit them in the following canonical sequence. This order is part of the consumer interface and is regression-tested.

1. **Lifecycle** events (creation, sttate transitions).
2. **Custody** events (deposit, transfer, release) emitted after the corresponding custody mutation.
3. **Configuration** events (parameter updates).
4. **Role** events (grant, revoke, renounce).
5. **Pause** events (pause, unpause).
6. **Upgrade** events (implementation changes).
7. **Settlement** events (finalization, distribution).

Within a single category, events are ordered by the sequence in which their state mutations are applied. Events MUST NOT be emitted for a mutation that is subsequently reverted within the same transaction.

## Reverted calls and nested calls

- A reverted call emits no durable logs. Alm logs from the reverted call frame, including those emitted by nested calls, must be discarded by the EVM. Consumers MUST NOT observe them in the canonical log stream.
- Nested calls emit their events inline with the call stack. The canonical log index order reflects the depth-first execution order, so a parent event emitted after a nested call appears after the nested's events.
- Batch operations MUST emit one event per affected item, in item index order, and MUST NOT emit a redundant aggregate event that duplicates the semantic content of the per-item events.
- Repeated actions (e.g., repeated pause or role grant) MUST NOT emit a duplicate semantic event when the state is unchanged; the contract MUST either revert or no-op without emitting a second event.
- Proxy upgrades MUST emit the upgrade event after the implementation slot is written and MUST NOT emit any lifecycle or configuration events that would be interpreted as belonging to the new implementation within the same transaction.

## Replay without state reads

Indexers MUST be able to replay the canonical log stream without reading contract state. Every event MUST carry the data needed to reconstruct the observed transition, including the prior and new values where applicable. Events MUST NOT require a state read to determine what changed.

## Test coverage

The following regression tests enforce this document:

- Success and revert paths for each event category, asserting the exact emitted sequence.
- Nested call ordering, asserting depth-first log index order.
- Batch operations, asserting per-item events in index order and no redundant aggregate event.
- Repeated actions, asserting no duplicate semantic event and the expected revert or no-op behavior.
- Proxy upgrade sequencing, asserting the upgrade event is emitted after the implementation slot write.
- Fuzz ordering, asserting that for arbitrary inputs the emitted sequence is a total order consistent with this document and contains no duplicate semantic events.
