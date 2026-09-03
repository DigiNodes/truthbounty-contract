// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IClaimRegistry
 * @notice Interface for the TruthBounty V2 On-Chain Claim Registry.
 * @dev All downstream protocol modules (Verification Engine, Settlement Engine,
 *      Reward Distribution, Reputation Engine, Dispute Resolution) depend on
 *      this interface. Interact exclusively through IClaimRegistry rather than
 *      the concrete implementation to maintain separation of concerns.
 *
 * Trust assumptions:
 * - Claims are immutable after creation (creator, statement, evidenceCID, createdAt).
 * - Only status transitions are permitted post-creation, and only by authorised modules.
 * - Every claim ID is monotonically increasing and never reused.
 */
interface IClaimRegistry {
    // =========================================================================
    // Enums
    // =========================================================================

    /**
     * @notice Canonical lifecycle states of a claim.
     * @dev Pending        — newly created, awaiting verifier participation.
     *      UnderVerification — verification window is open and votes are being cast.
     *      VerifiedTrue   — consensus outcome is TRUE.
     *      VerifiedFalse  — consensus outcome is FALSE.
     *      Disputed       — outcome is contested and routed to dispute resolution.
     *      Cancelled      — claim was withdrawn or invalidated before resolution.
     */
    enum ClaimStatus {
        Pending,
        UnderVerification,
        VerifiedTrue,
        VerifiedFalse,
        Disputed,
        Cancelled
    }

    // =========================================================================
    // Structs
    // =========================================================================

    /**
     * @notice Canonical on-chain representation of a claim.
     * @dev Storage layout notes:
     *      - `id` (uint256, slot 0): unique monotonic identifier.
     *      - `creator` (address, slot 1): immutable after creation.
     *      - `statement` (string, slot 2): dynamic, stored in a separate slot cluster.
     *      - `evidenceCID` (string, slot 3): IPFS CID, dynamic, separate slot cluster.
     *      - `status` (ClaimStatus enum = uint8) + `createdAt` (uint64) +
     *        `verificationDeadline` (uint64) are packed together in slot 4 (< 32 bytes).
     *
     *      Future extensibility:
     *      Additional fields (category, jurisdiction, rewardPool, reputationSnapshot,
     *      metadataHash) can be appended as new struct members without breaking existing
     *      storage layout, provided packing considerations are respected.
     */
    struct Claim {
        uint256 id;
        address creator;
        string statement;
        string evidenceCID;
        ClaimStatus status;
        uint64 createdAt;
        uint64 verificationDeadline;
    }

    // =========================================================================
    // Events
    // =========================================================================

    /**
     * @notice Emitted when a new claim is created on-chain.
     * @param claimId      Unique, monotonically increasing claim identifier.
     * @param creator      Address of the claim submitter (msg.sender at creation).
     * @param evidenceCID  IPFS CID referencing supporting evidence.
     * @dev The full claim (statement, deadline, timestamps) is recoverable via
     *      {getClaim}. Off-chain indexers can reconstruct all protocol state
     *      from this event combined with the storage query.
     */
    event ClaimCreated(
        uint256 indexed claimId,
        address indexed creator,
        string evidenceCID
    );

    /**
     * @notice Emitted when a claim transitions to a new status.
     * @param claimId   The affected claim.
     * @param oldStatus Previous status.
     * @param newStatus New status.
     */
    event ClaimStatusUpdated(
        uint256 indexed claimId,
        ClaimStatus indexed oldStatus,
        ClaimStatus indexed newStatus
    );

    // =========================================================================
    // Custom Errors
    // =========================================================================

    /// @notice Thrown when `statement` is empty or outside the allowed length bounds.
    error InvalidStatement();

    /// @notice Thrown when `evidenceCID` is empty or outside the allowed length bounds.
    error InvalidCID();

    /// @notice Thrown when `verificationDeadline` is in the past or exceeds the protocol maximum.
    error InvalidDeadline();

    /// @notice Thrown when the requested claim ID does not exist.
    error ClaimNotFound(uint256 claimId);

    /// @notice Thrown when an unauthorised caller attempts a status transition.
    error UnauthorisedStatusTransition();

    /// @notice Thrown when a status transition is logically invalid for the current state.
    error InvalidStatusTransition(ClaimStatus current, ClaimStatus requested);

    // =========================================================================
    // Write Functions
    // =========================================================================

    /**
     * @notice Creates a new claim on-chain, returning its unique identifier.
     * @param statement           Human-readable claim text (10–2,000 chars).
     * @param evidenceCID         IPFS CID of supporting evidence (46–128 chars).
     * @param verificationDeadline Unix timestamp by which verification must complete.
     *                            Must be strictly greater than block.timestamp and
     *                            not exceed the protocol maximum horizon.
     * @return claimId  The newly assigned, monotonically increasing claim ID.
     *
     * @dev Emits {ClaimCreated}.
     *      No external calls are made inside this function.
     *      The claim is permanently stored and cannot be overwritten.
     */
    function createClaim(
        string calldata statement,
        string calldata evidenceCID,
        uint64 verificationDeadline
    ) external returns (uint256 claimId);

    /**
     * @notice Transitions a claim to a new status.
     * @dev Only callable by authorised downstream modules (e.g. Verification Engine).
     *      Emits {ClaimStatusUpdated}.
     * @param claimId   The claim to update.
     * @param newStatus The target status.
     */
    function updateClaimStatus(uint256 claimId, ClaimStatus newStatus) external;

    // =========================================================================
    // View Functions
    // =========================================================================

    /**
     * @notice Returns the full Claim struct for the given ID.
     * @param claimId  The claim to retrieve.
     * @return claim   A copy of the Claim struct from storage.
     * @dev Reverts with {ClaimNotFound} if the claim does not exist.
     */
    function getClaim(uint256 claimId) external view returns (Claim memory claim);

    /**
     * @notice Returns whether a claim with the given ID has been created.
     * @param claimId  The claim to check.
     * @return exists  True if the claim exists, false otherwise.
     */
    function claimExists(uint256 claimId) external view returns (bool exists);

    /**
     * @notice Returns the total number of claims ever created.
     * @dev Equal to (nextClaimId - 1) once at least one claim has been created.
     *      Monotonically increasing; never decrements.
     */
    function totalClaims() external view returns (uint256 total);

    /**
     * @notice Returns the creator address permanently recorded for a claim.
     * @param claimId  The claim to query.
     * @return creator The address that called {createClaim}.
     * @dev Reverts with {ClaimNotFound} if the claim does not exist.
     */
    function getClaimCreator(uint256 claimId) external view returns (address creator);

    /**
     * @notice Returns the current lifecycle status of a claim.
     * @param claimId  The claim to query.
     * @return status  The current {ClaimStatus} value.
     * @dev Reverts with {ClaimNotFound} if the claim does not exist.
     */
    function getClaimStatus(uint256 claimId) external view returns (ClaimStatus status);
}
