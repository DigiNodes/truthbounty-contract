// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IV2Module} from "./IV2Module.sol";
import {IV2Types} from "./IV2Types.sol";

/// @notice Content-addressed evidence commitment and status interface.
/// @dev The contract stores digests, not raw evidence. Content availability and cryptographic interpretation are external assumptions.
interface IEvidence is IV2Module {
    /// @notice Emitted when an evidence commitment is accepted.
    /// @param evidenceId Deterministically derived evidence identifier.
    /// @param claimId Claim receiving the evidence.
    /// @param submitter Account that supplied the commitment.
    /// @param contentHash Digest of off-chain content.
    /// @param timestamp Block timestamp the commitment was accepted.
    /// @param version Event schema version.
    event EvidenceSubmitted(uint256 indexed evidenceId, uint256 indexed claimId, address indexed submitter, bytes32 contentHash, uint64 timestamp, uint16 version);

    /// @notice Emitted when an evidence administrator changes acceptance status.
    /// @param evidenceId Evidence whose status changed.
    /// @param previousStatus Status before the change.
    /// @param newStatus Status after the change.
    /// @param actor Authorized administrator.
    /// @param timestamp Block timestamp the status change was applied.
    /// @param version Event schema version.
    event EvidenceStatusChanged(uint256 indexed evidenceId, IV2Types.EvidenceStatus previousStatus, IV2Types.EvidenceStatus newStatus, address indexed actor, uint64 timestamp, uint16 version);

    /// @notice Submits an evidence commitment for an active claim.
    /// @dev Must reject zero digests, duplicate commitments, closed windows, finalized claims, and invalid nonces. Metadata is treated as opaque and should be stored off-chain.
    /// @param claimId Existing claim receiving evidence.
    /// @param contentHash Digest of off-chain content.
    /// @param metadata Opaque metadata bytes whose interpretation is outside the EVM contract.
    /// @return evidenceId Deterministically derived identifier.
    function submitEvidence(uint256 claimId, bytes32 contentHash, bytes calldata metadata) external returns (uint256 evidenceId);

    /// @notice Sets the evidence acceptance status under the evidence administrator authority.
    /// @dev The current implementation requires the evidence record to exist but does not enforce a state-transition matrix; an authorized administrator can assign any status, including `NONE`, to an existing record.
    /// @param evidenceId Evidence to update.
    /// @param status New evidence status.
    function setEvidenceStatus(uint256 evidenceId, IV2Types.EvidenceStatus status) external;

    /// @notice Reads the public evidence record.
    /// @param evidenceId Evidence to read.
    /// @return evidence Evidence fields, excluding private metadata digest storage details.
    function getEvidence(uint256 evidenceId) external view returns (IV2Types.Evidence memory evidence);

    /// @notice Returns a bounded page of evidence IDs for a claim.
    /// @dev Pagination is deterministic insertion order. An out-of-range cursor returns an empty page; limit must be bounded by the implementation.
    /// @param claimId Claim whose evidence IDs are read.
    /// @param cursor Zero-based index at which to start.
    /// @param limit Maximum number of IDs to return; must be positive and within the configured bound.
    /// @return evidenceIds Ordered page of evidence identifiers.
    /// @return nextCursor Cursor for the next page, equal to the claim's count when exhausted.
    function claimEvidence(uint256 claimId, uint256 cursor, uint256 limit) external view returns (uint256[] memory evidenceIds, uint256 nextCursor);
}
