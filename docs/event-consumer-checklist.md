# Event consumer compatibility checklist

Indexer, backend, frontend, explorer, and analytics consumers should apply the following rules to the SC-022 event surface.

Reorganization expectations (confirmation depth, finality classes, bounded replacement/removal, and replay) are now authoritative and machine-readable: see [`docs/reorg-consumer-guarantees.md`](./reorg-consumer-guarantees.md) and the on-chain `IConsumerGuarantees` anchor. The rules below remain valid; the guarantees document makes them normative.

- Filter by contract address and canonical event signature before decoding.
- Treat indexed entity identifiers and actors as the primary query keys.
- Persist block number, block hash, transaction hash, transaction index, and log index with every decoded event.
- Deduplicate by chain ID, transaction hash, and log index.
- Delay irreversible processing until the consumer's configured confirmation depth is reached.
- Roll back events whose block hash is no longer canonical after a reorganization.
- Reject unsupported schema versions without corrupting previously indexed state.
- Process logs in block number, transaction index, then log index order.
- Never infer a successful state transition from a reverted transaction; reverted transactions produce no logs.
- Treat metadata hashes as references and verify fetched metadata independently.

Schema version `1` is the initial compatibility target.