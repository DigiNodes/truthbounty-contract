# V2 Evidence Registry

`contracts/v2/EvidenceRegistry.sol` is the V2 content-addressed evidence commitment path.
It stores only immutable digests and deterministic identifiers; raw content, mutable URLs,
CIDs, signatures, and private data remain off-chain and non-authoritative.

## Commitment Identity

Evidence IDs are derived from:

- Chain ID
- Evidence registry address
- Claim ID
- Contributor address
- Content digest
- Metadata digest
- Contributor nonce

The contributor nonce is enforced in order and advances after each accepted commitment.
The duplicate guard rejects a repeated claim, contributor, content digest, and metadata
digest tuple even if a later nonce is supplied.

## Claim And Timing Checks

The registry validates claim existence through `IClaimRegistry.claimExists(uint256)` and
loads the claim deadline/status through `IClaimRegistry.getClaim(uint256)`.
Commitments are accepted only while the claim status is `Pending` or `UnderVerification`
and while `block.timestamp <= verificationDeadline`.

## Events And Replay

Each accepted commitment emits:

- `EvidenceSubmitted`, the canonical V2 interface event
- `EvidenceSubmittedV1`, the protocol event-catalogue event
- `EvidenceCommitted`, the digest-complete reconstruction event

Consumers can reconstruct a claim evidence set by paging through `claimEvidence` and
retrieving full digest records with `getEvidenceCommitment`.

## Legacy Path

`contracts/EvidenceManager.sol` remains the legacy CID-string manager. The V2 registry
does not rely on upload services or CID strings as authority.
