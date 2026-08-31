// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IVerificationSubmission
 * @notice Interface for TruthBounty V2 Verification Submission Engine.
 */
interface IVerificationSubmission {
    
    // =========================================================================
    // Enums
    // =========================================================================

    /**
     * @notice Possible verdicts submitted by a verifier.
     */
    enum VerificationVerdict {
        TRUE,
        FALSE
    }

    // =========================================================================
    // Structs
    // =========================================================================

    /**
     * @notice Canonical on-chain representation of a verification.
     */
    struct Verification {
        uint256 id;
        uint256 claimId;
        address verifier;
        VerificationVerdict verdict;
        uint256 stake;
        uint64 submittedAt;
    }

    // =========================================================================
    // Events
    // =========================================================================

    /**
     * @notice Emitted when a verification is successfully submitted.
     */
    event VerificationSubmitted(
        uint256 indexed claimId,
        uint256 indexed verificationId,
        address indexed verifier,
        VerificationVerdict verdict,
        uint256 stake
    );

    // =========================================================================
    // Custom Errors
    // =========================================================================

    error AlreadyVerified();
    error VerificationWindowClosed();
    error InvalidClaimState();
    error InsufficientStake();
    error ZeroAddress();

    // =========================================================================
    // Functions
    // =========================================================================

    /**
     * @notice Submits a verification for a claim.
     * @param claimId The ID of the claim being verified.
     * @param verdict The verifier's verdict (TRUE or FALSE).
     * @param stakeAmount The amount of stake committed (must be >= minimum required).
     */
    function submitVerification(
        uint256 claimId,
        VerificationVerdict verdict,
        uint256 stakeAmount
    ) external;

    /**
     * @notice Retrieves a verification by its ID.
     */
    function getVerification(uint256 verificationId) external view returns (Verification memory);

    /**
     * @notice Retrieves all verification IDs associated with a specific claim.
     */
    function getClaimVerifications(uint256 claimId) external view returns (uint256[] memory);

    /**
     * @notice Retrieves the total number of verifications submitted across all claims.
     */
    function getVerificationCount() external view returns (uint256);

    /**
     * @notice Checks if a specific address has already verified a given claim.
     */
    function hasVerified(uint256 claimId, address verifier) external view returns (bool);

    /**
     * @notice Retrieves the stake locked by a specific verifier on a specific claim.
     */
    function getVerifierStake(uint256 claimId, address verifier) external view returns (uint256);
}
