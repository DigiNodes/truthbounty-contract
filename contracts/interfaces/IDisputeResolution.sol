// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IClaimRegistry.sol";

/**
 * @title IDisputeResolution
 * @notice Interface for the TruthBounty V2 Dispute Opening & Challenge Bond
 *         Custody engine (V2-SC-016).
 *
 * @dev Scope (matching issue #367):
 *   - Exactly ONE valid challenge may open per claim (the "one appeal path").
 *   - A challenge is only accepted during the ChallengeWindow and strictly
 *     before the frozen (appeal) deadline.
 *   - The configured bond asset and amount are locked through the StakeVault
 *     before any dispute state is committed.
 *   - The dispute records the challenger, challenged outcome, bond lock,
 *     appeal parameters, and a durable dispute identifier.
 *   - Recursive and duplicate challenges are rejected; opening emits
 *     `DisputeOpenedV1` and transitions the claim to {Disputed} atomically.
 *
 * The provisional-result flow this module challenges is modeled on the
 * registry's `VerifiedTrue` / `VerifiedFalse` terminal outcomes. Settling an
 * appeal (honouring the bond, resolving the dispute) is explicitly OUT of scope
 * (V2-SC-016 non-goals).
 */
interface IDisputeResolution {
    // =========================================================================
    // Enums
    // =========================================================================

    /**
     * @notice Which provisional outcome a challenger is contesting.
     * @dev Mirrors the provisional `VerifiedTrue`/`VerifiedFalse` verdict space;
     *      a challenge targets the outcome recorded against the claim.
     */
    enum ChallengedOutcome {
        TRUE,
        FALSE
    }

    // =========================================================================
    // Structs
    // =========================================================================

    /**
     * @notice Canonical on-chain representation of an opened dispute.
     * @param id                  Monotonic dispute identifier (== StakeVault lockId).
     * @param claimId             Claim under dispute.
     * @param challenger          Address that opened (and bonded) the dispute.
     * @param challengedOutcome   Which provisional outcome is being contested.
     * @param challengedStatus    Registry status challenged (VerifiedTrue/VerifiedFalse).
     * @param bondToken           ERC20 token used for the bond.
     * @param bondAmount          Amount locked through the StakeVault.
     * @param openedAt            Unix timestamp the dispute opened.
     * @param appealDeadline      Frozen deadline: disputes must open before this.
     * @param appealRationaleHash keccak256 hash of the challenger's rationale/evidence.
     * @param settled             Whether the dispute has been resolved (out of scope here).
     */
    struct Dispute {
        uint256 id;
        uint256 claimId;
        address challenger;
        ChallengedOutcome challengedOutcome;
        IClaimRegistry.ClaimStatus challengedStatus;
        address bondToken;
        uint256 bondAmount;
        uint64 openedAt;
        uint64 appealDeadline;
        bytes32 appealRationaleHash;
        bool settled;
    }

    // =========================================================================
    // Events
    // =========================================================================

    /**
     * @notice Emitted when a dispute is opened.
     * @dev Captures every appeal-round initialization input so indexers can
     *      reconstruct the full opening state without extra calls.
     * @param claimId             Claim under dispute.
     * @param disputeId           Monotonic dispute identifier.
     * @param challenger          Address that opened the dispute.
     * @param challengedOutcome   Provisional outcome contested (TRUE/FALSE).
     * @param challengedStatus    Registry status that was contested.
     * @param bondToken           Bond token locked.
     * @param bondAmount          Bond amount locked.
     * @param appealDeadline      Frozen deadline for this dispute.
     * @param appealRationaleHash Rationale hash (appeal initialization input).
     * @param openedAt            Opening timestamp.
     * @param version             Event schema version (1).
     */
    event DisputeOpenedV1(
        uint256 indexed claimId,
        uint256 indexed disputeId,
        address indexed challenger,
        ChallengedOutcome challengedOutcome,
        IClaimRegistry.ClaimStatus challengedStatus,
        address bondToken,
        uint256 bondAmount,
        uint64 appealDeadline,
        bytes32 appealRationaleHash,
        uint64 openedAt,
        uint16 version
    );

    // =========================================================================
    // Custom Errors
    // =========================================================================

    /// @notice Zero-address provided where forbidden.
    error ZeroAddress();

    /// @notice The bond amount or token is not configured to an accepted value.
    error BondNotConfigured();

    /// @notice The caller has not approved / lacks sufficient bond tokens.
    error InsufficientBondAllowance();

    /// @notice The claim is not in a challengeable provisional state.
    error ClaimNotChallengeable(IClaimRegistry.ClaimStatus status);

    /// @notice The claim does not exist.
    error ClaimNotFound(uint256 claimId);

    /// @notice Another dispute is already open for this claim (one appeal path per claim).
    error DisputeAlreadyOpen(uint256 claimId);

    /// @notice The challenge is outside the ChallengeWindow (too early).
    error ChallengeWindowNotOpen();

    /// @notice The challenge is past the frozen/appeal deadline (too late).
    error FrozenDeadlinePassed();

    /// @notice The claim cannot currently be challenged (e.g. window ended).
    error ChallengeClosed();

    /// @notice The internal call to the registry or vault reverted inline.
    error CustodyTransitionFailed();

    // =========================================================================
    // Write Functions
    // =========================================================================

    /**
     * @notice Opens one dispute for `claimId`, locking the challenge bond.
     * @param claimId             Claim whose provisional outcome is contested.
     * @param challengedOutcome   Which provisional outcome is being challenged.
     * @param appealRationaleHash Hash of the challenger's rationale/evidence.
     * @return disputeId          The newly created dispute identifier.
     *
     * @dev Permissionless, but bond-gated: any caller may challenge a claim that
     *      holds a provisional outcome *provided* they post the configured bond.
     *      No governance/guardian/treasury role may open or waive a dispute
     *      without posting the bond through {ISTakeVault.lockBond}.
     *
     *      Ordering (atomic):
     *        1. Validate timing (ChallengeWindow, before the frozen deadline),
     *           claim state, and one-challenge-per-claim.
     *        2. Lock the bond through the StakeVault.
     *        3. Only after the lock succeeds, write the dispute record and
     *           transition the claim to {Disputed} via the registry.
     *
     * @custom:emits DisputeOpenedV1
     */
    function openDispute(
        uint256 claimId,
        ChallengedOutcome challengedOutcome,
        bytes32 appealRationaleHash
    ) external returns (uint256 disputeId);

    // =========================================================================
    // View Functions
    // =========================================================================

    /**
     * @notice Returns a single dispute record.
     * @param disputeId Dispute identifier.
     * @return dispute  The Dispute struct.
     * @dev Returns all-zero struct for an unknown id (never reverts).
     */
    function getDispute(uint256 disputeId) external view returns (Dispute memory dispute);

    /**
     * @notice Returns whether a dispute exists for a dispute id.
     * @param disputeId Dispute identifier.
     * @return exists   True if a dispute was opened under this id.
     */
    function disputeExists(uint256 disputeId) external view returns (bool exists);

    /**
     * @notice Returns the dispute id open for a claim (0 if none).
     * @param claimId Claim identifier.
     * @return disputeId The dispute id, or 0 if the claim has no open dispute.
     */
    function getDisputeByClaim(uint256 claimId) external view returns (uint256 disputeId);

    /**
     * @notice Total number of disputes ever opened.
     * @return total Monotonically increasing count of opened disputes.
     */
    function totalDisputes() external view returns (uint256 total);
}
