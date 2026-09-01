// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IVerificationRoundEvents.sol";

/**
 * @title IVerificationRoundManager
 * @notice Interface for the TruthBounty V2 Verification Round Manager.
 *
 * @dev Governs the creation, closure, and querying of verification rounds.
 *      A round snapshot is immutable after it is opened; any subsequent
 *      configuration changes in the protocol registry do NOT affect an open
 *      round. This guarantees deterministic settlement regardless of when
 *      aggregation is executed.
 *
 *      Round types:
 *      - FIRST  (0) — initial verification pass for a claim.
 *      - APPEAL (1) — secondary pass opened after a disputed FIRST round.
 *
 *      Invariants enforced by implementations:
 *      1. At most one active (non-closed) round of each type per claim.
 *      2. An appeal round may only be created after the first round is closed.
 *      3. Submissions are rejected once a round is closed.
 *      4. Participant arrays are bounded by MAX_PARTICIPANTS to cap gas usage.
 *      5. Round parameters are write-once; no mutator exists after open.
 */
interface IVerificationRoundManager is IVerificationRoundEvents {
    // =========================================================================
    // Enums
    // =========================================================================

    /// @notice Distinguishes between the two round types in the protocol.
    enum RoundType { FIRST, APPEAL }

    /// @notice Lifecycle state of a round.
    enum RoundState { OPEN, CLOSED }

    // =========================================================================
    // Structs
    // =========================================================================

    /**
     * @notice Immutable parameter snapshot frozen at round-open time.
     * @dev Packed to fit in as few storage slots as possible.
     *      - claimId (uint256)          : slot 0
     *      - roundType + state (uint8×2): packed
     *      - startedAt + deadline (uint64×2): packed
     *      - minStake (uint256)         : slot 2
     *      - maxStake (uint256)         : slot 3
     *      - weightCap (uint256)        : slot 4
     *      - passingThreshold (uint16)
     *        + paramVersion (uint32)    : packed in slot 5
     */
    struct RoundParams {
        uint256 claimId;
        RoundType roundType;
        RoundState state;
        uint64  startedAt;
        uint64  deadline;
        uint256 minStake;
        uint256 maxStake;
        uint256 weightCap;
        uint16  passingThreshold;   // basis points (0–10 000)
        uint32  paramVersion;
    }

    /**
     * @notice Frozen record of a single participant's submission in a round.
     * @dev Written once when the participant joins; never mutated thereafter.
     */
    struct ParticipantRecord {
        address participant;
        uint256 stake;
        uint64  submittedAt;
    }

    // =========================================================================
    // Custom errors
    // =========================================================================

    /// @notice The provided deadline is not strictly after block.timestamp.
    error DeadlineMustBeFuture();

    /// @notice An active round of the same type already exists for this claim.
    error OverlappingActiveRound(uint256 claimId, RoundType roundType);

    /// @notice An appeal round was requested but the first round is not closed.
    error FirstRoundNotClosed(uint256 claimId);

    /// @notice The round does not exist.
    error RoundNotFound(uint256 roundId);

    /// @notice The round is already closed.
    error RoundAlreadyClosed(uint256 roundId);

    /// @notice The round deadline has not yet passed; cannot close early.
    error DeadlineNotReached(uint256 roundId);

    /// @notice The participant has already been recorded in this round.
    error AlreadyParticipated(uint256 roundId, address participant);

    /// @notice The round is closed and no further submissions are accepted.
    error RoundClosed_Submissions(uint256 roundId);

    /// @notice The participant index is out of bounds.
    error ParticipantIndexOutOfBounds(uint256 roundId, uint256 index);

    /// @notice minStake exceeds maxStake.
    error InvalidStakeBounds();

    /// @notice passingThreshold exceeds 10 000 basis points.
    error InvalidThreshold();

    // =========================================================================
    // Write functions
    // =========================================================================

    /**
     * @notice Opens a new verification round for `claimId`, freezing all
     *         protocol parameters at the current configuration version.
     *
     * @param claimId           Claim this round belongs to (must exist in registry).
     * @param roundType         FIRST or APPEAL.
     * @param deadline          Unix timestamp after which the round accepts no more
     *                          submissions; must be strictly > block.timestamp.
     * @param minStake          Minimum stake per participant (base units).
     * @param maxStake          Maximum stake per participant (base units); must be >= minStake.
     * @param weightCap         Maximum weight units any single participant may contribute.
     * @param passingThreshold  Basis points (0–10 000) required for a TRUE outcome.
     * @param paramVersion      Configuration registry version being snapshotted.
     *
     * @return roundId   The newly assigned, globally unique round identifier.
     *
     * @dev Emits {RoundOpened}.
     *      Reverts with {OverlappingActiveRound} if an open round of the same type
     *      already exists for this claim.
     *      Reverts with {FirstRoundNotClosed} if roundType == APPEAL and the claim's
     *      first round has not been closed.
     *      Access: caller must hold ROUND_MANAGER_ROLE or be the contract owner.
     */
    function openRound(
        uint256 claimId,
        RoundType roundType,
        uint64 deadline,
        uint256 minStake,
        uint256 maxStake,
        uint256 weightCap,
        uint16 passingThreshold,
        uint32 paramVersion
    ) external returns (uint256 roundId);

    /**
     * @notice Closes a round permissionlessly once its deadline has passed.
     *         Rejected if the deadline has not yet been reached.
     *
     * @param roundId  The round to close.
     *
     * @dev Emits {RoundClosed}.
     *      No loop over participants is performed; closure is O(1).
     *      Reverts with {RoundNotFound} if the round does not exist.
     *      Reverts with {RoundAlreadyClosed} if the round is already closed.
     *      Reverts with {DeadlineNotReached} if block.timestamp <= deadline.
     */
    function closeRound(uint256 roundId) external;

    /**
     * @notice Records a participant's submission against an open round.
     *         Enforces stake bounds, duplicate prevention, and closed-round rejection.
     *
     * @param roundId     The round to record the submission against.
     * @param participant The verifier address being recorded.
     * @param stake       The stake amount committed by the participant.
     *
     * @dev Caller must hold ROUND_MANAGER_ROLE (typically the Verification
     *      Submission contract).
     *      Reverts with {RoundClosed_Submissions} if the round is closed.
     *      Reverts with {AlreadyParticipated} if the participant is already recorded.
     *      Reverts with {InsufficientStake} / {ExceedsMaxStake} if stake is out of bounds.
     */
    function recordParticipant(
        uint256 roundId,
        address participant,
        uint256 stake
    ) external;

    // =========================================================================
    // View functions
    // =========================================================================

    /**
     * @notice Returns the full immutable parameter snapshot for a round.
     * @param roundId  The round to query.
     * @return params  A copy of the {RoundParams} struct from storage.
     * @dev Reverts with {RoundNotFound} if the round does not exist.
     */
    function getRound(uint256 roundId) external view returns (RoundParams memory params);

    /**
     * @notice Returns the current state (OPEN / CLOSED) of a round.
     * @param roundId  The round to query.
     * @return state   The {RoundState} enum value.
     * @dev Reverts with {RoundNotFound} if the round does not exist.
     */
    function getRoundState(uint256 roundId) external view returns (RoundState state);

    /**
     * @notice Returns the active (non-closed) round ID of a given type for a claim,
     *         or 0 if no such round exists.
     * @param claimId   The claim to query.
     * @param roundType FIRST or APPEAL.
     * @return roundId  The active round ID, or 0 if none is active.
     */
    function getActiveRound(uint256 claimId, RoundType roundType) external view returns (uint256 roundId);

    /**
     * @notice Returns the total number of participants recorded in a round.
     * @param roundId  The round to query.
     * @return count   Participant count.
     * @dev Reverts with {RoundNotFound} if the round does not exist.
     */
    function getParticipantCount(uint256 roundId) external view returns (uint256 count);

    /**
     * @notice Returns a bounded slice of participant records from a round.
     *         Designed for gas-safe iteration by off-chain aggregators.
     *
     * @param roundId  The round to query.
     * @param offset   Zero-based start index.
     * @param limit    Maximum number of records to return.
     * @return records Array of {ParticipantRecord} structs (may be shorter than limit).
     *
     * @dev Reverts with {RoundNotFound} if the round does not exist.
     *      Returns an empty array if offset >= participant count.
     *      A limit of 0 is treated as "return all from offset".
     */
    function getParticipants(
        uint256 roundId,
        uint256 offset,
        uint256 limit
    ) external view returns (ParticipantRecord[] memory records);

    /**
     * @notice Returns whether a specific address has already been recorded in a round.
     * @param roundId     The round to query.
     * @param participant The address to check.
     * @return recorded   True if the participant is already recorded.
     */
    function hasParticipated(uint256 roundId, address participant) external view returns (bool recorded);

    /**
     * @notice Returns the total number of rounds ever opened.
     * @return total  Monotonically increasing count; never decrements.
     */
    function totalRounds() external view returns (uint256 total);
}
