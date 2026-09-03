// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title V2Errors
/// @notice Shared error definitions for the TruthBounty V2 protocol.
/// @dev This library centralizes all protocol-level errors to ensure consistency
///      across all V2 modules and improve maintainability.
library V2Errors {
    // =========================================================================
    // Authorization & Access Control Errors
    // =========================================================================

    /// @notice Attempted action by unauthorized caller.
    error Unauthorized();

    /// @notice Attempted action by address(0).
    error ZeroAddress();

    /// @notice Attempted action with zero amount.
    error ZeroAmount();

    /// @notice Attempted action by an unregistered or unauthorized module.
    error UnauthorizedModule(address caller);

    // =========================================================================
    // Claim-Related Errors
    // =========================================================================

    /// @notice Claim not found.
    error ClaimNotFound(uint256 claimId);

    /// @notice Canonical claim not found.
    error CanonicalClaimNotFound(bytes32 claimId);

    /// @notice Invalid claim state transition.
    error InvalidClaimStateTransition(uint256 claimId);

    /// @notice Claim already exists.
    error ClaimAlreadyExists(uint256 claimId);

    /// @notice Canonical claim already exists.
    error CanonicalClaimAlreadyExists(bytes32 claimId);

    /// @notice Invalid claim subject.
    error InvalidClaimSubject();

    /// @notice Invalid claim reward amount.
    error InvalidReward();

    // =========================================================================
    // Evidence-Related Errors
    // =========================================================================

    /// @notice Evidence not found.
    error EvidenceNotFound(uint256 evidenceId);

    /// @notice Invalid evidence content hash.
    error InvalidEvidenceHash();

    /// @notice Evidence submission window closed.
    error EvidenceWindowClosed();

    /// @notice Duplicate evidence submission.
    error DuplicateEvidence();

    // =========================================================================
    // Verification-Related Errors
    // =========================================================================

    /// @notice Verification not found.
    error VerificationNotFound(uint256 verificationId);

    /// @notice Verification window closed.
    error VerificationWindowClosed();

    /// @notice Verifier already submitted verification for this claim.
    error AlreadyVerified();

    /// @notice Insufficient stake amount.
    error InsufficientStake();

    /// @notice Invalid verification verdict.
    error InvalidVerdict();

    // =========================================================================
    // Settlement-Related Errors
    // =========================================================================

    /// @notice Settlement not found.
    error SettlementNotFound(uint256 claimId);

    /// @notice Settlement not executable yet.
    error SettlementNotExecutable(uint64 executeAfter);

    /// @notice Settlement execution failed.
    error SettlementExecutionFailed();

    /// @notice Invalid settlement amount.
    error InvalidSettlementAmount();

    // =========================================================================
    // Dispute-Related Errors
    // =========================================================================

    /// @notice Dispute not found.
    error DisputeNotFound(uint256 disputeId);

    /// @notice Dispute window closed.
    error DisputeWindowClosed();

    /// @notice Dispute already opened.
    error DisputeAlreadyExists();

    /// @notice Invalid dispute reason.
    error InvalidDisputeReason();

    // =========================================================================
    // Stake & Custody-Related Errors
    // =========================================================================

    /// @notice Insufficient stake balance.
    error InsufficientStakeBalance();

    /// @notice Stake withdrawal not permitted.
    error StakeWithdrawalNotPermitted();

    /// @notice Invalid custody reference.
    error InvalidCustodyReference();

    /// @notice Asset is not supported by the custody vault.
    error UnsupportedAsset(address asset);

    /// @notice Insufficient claimable balance for the requested operation.
    error InsufficientClaimable(address account, uint256 requested, uint256 available);

    /// @notice Insufficient locked balance for the requested operation.
    error InsufficientLocked(uint256 requested, uint256 available);

    /// @notice Insufficient protocol allocation for the requested operation.
    error InsufficientProtocolAllocation(uint256 requested, uint256 available);

    /// @notice Token transfer amount does not match the expected value.
    error TransferAmountMismatch(uint256 expected, uint256 received);

    /// @notice Recorded obligations exceed on-chain custody for an asset.
    error ObligationsExceedCustody(address asset, uint256 custody, uint256 obligations);

    /// @notice Settlement outcome already recorded for this claim-round; repeated or conflicting instructions revert.
    error SettlementAlreadyFinalized(uint256 claimId, uint256 round);

    /// @notice Invalid settlement outcome requested for this claim-round.
    error InvalidSettlementOutcome(uint256 claimId, uint256 round);

    // =========================================================================
    // Aggregation & Reputation Errors
    // =========================================================================

    /// @notice Invalid aggregation result.
    error InvalidAggregationResult();

    /// @notice Reputation update failed.
    error ReputationUpdateFailed();

    /// @notice Invalid reputation score.
    error InvalidReputationScore();

    // =========================================================================
    // Configuration & Governance Errors
    // =========================================================================

    /// @notice Configuration not found.
    error ConfigurationNotFound();

    /// @notice Invalid parameter version.
    error InvalidParameterVersion();

    /// @notice Parameter update not authorized.
    error ParameterUpdateNotAuthorized();

    // =========================================================================
    // Slashing Errors
    // =========================================================================

    /// @notice Slash amount exceeds stake.
    error SlashAmountExceedsStake();

    /// @notice Slashing not permitted for this verifier.
    error SlashingNotPermitted();

    // =========================================================================
    // Emergency Control Errors
    // =========================================================================

    /// @notice Protocol is paused.
    error ProtocolPaused();

    /// @notice Operation requires emergency authority.
    error EmergencyAuthorityRequired();

    // =========================================================================
    // Generic Validation Errors
    // =========================================================================

    /// @notice Invalid function argument.
    /// @param reason Description of what was invalid.
    error InvalidArgument(string reason);

    /// @notice Operation not supported.
    error NotSupported();

    /// @notice Reentrancy guard detected.
    error ReentrancyDetected();
}
