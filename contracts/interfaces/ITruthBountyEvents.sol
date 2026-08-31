// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ITruthBountyEvents
/// @notice Canonical, versioned event surface for TruthBounty protocol indexers.
/// @dev Events are public protocol APIs. Implementations should emit events only
///      after the corresponding state transition succeeds. Schema version 1 is
///      represented by the literal value `1` in each event's `version` field.
interface ITruthBountyEvents {
    // Claims
    event ClaimCreatedV1(
        uint256 indexed claimId,
        address indexed actor,
        bytes32 indexed metadataHash,
        uint64 timestamp,
        uint16 version
    );
    event ClaimUpdatedV1(
        uint256 indexed claimId,
        address indexed actor,
        bytes32 indexed metadataHash,
        uint64 timestamp,
        uint16 version
    );
    event ClaimResolvedV1(
        uint256 indexed claimId,
        address indexed actor,
        bool outcome,
        uint64 timestamp,
        uint16 version
    );
    event ClaimFinalizedV1(
        uint256 indexed claimId,
        address indexed actor,
        uint64 timestamp,
        uint16 version
    );

    // Verification
    event VerificationSubmittedV1(
        uint256 indexed claimId,
        address indexed verifier,
        bool support,
        uint256 stakeAmount,
        uint64 timestamp,
        uint16 version
    );
    event VerificationChallengedV1(
        uint256 indexed claimId,
        address indexed challenger,
        bytes32 indexed reasonHash,
        uint64 timestamp,
        uint16 version
    );

    // Staking and slashing
    event StakeDepositedV1(
        address indexed verifier,
        uint256 amount,
        uint256 newBalance,
        uint64 timestamp,
        uint16 version
    );
    event StakeWithdrawnV1(
        address indexed verifier,
        uint256 amount,
        uint256 newBalance,
        uint64 timestamp,
        uint16 version
    );
    event SlashExecutedV1(
        uint256 indexed claimId,
        address indexed verifier,
        bytes32 indexed reason,
        uint256 amount,
        uint64 timestamp,
        uint16 version
    );

    // Rewards and treasury
    event RewardCalculatedV1(
        bytes32 indexed calculationId,
        address indexed recipient,
        uint256 amount,
        uint64 timestamp,
        uint16 version
    );
    event RewardEscrowedV1(
        uint256 indexed claimId,
        address indexed recipient,
        uint256 amount,
        uint64 timestamp,
        uint16 version
    );
    event RewardClaimedV1(
        uint256 indexed claimId,
        address indexed recipient,
        uint256 amount,
        uint64 timestamp,
        uint16 version
    );
    event TreasuryTransferV1(
        bytes32 indexed operationId,
        address indexed token,
        address indexed recipient,
        uint256 amount,
        uint64 timestamp,
        uint16 version
    );

    // Governance and emergency controls
    event GovernanceProposalCreatedV1(
        bytes32 indexed proposalId,
        address indexed proposer,
        bytes32 indexed metadataHash,
        uint64 timestamp,
        uint16 version
    );
    event GovernanceProposalExecutedV1(
        bytes32 indexed proposalId,
        address indexed executor,
        uint64 timestamp,
        uint16 version
    );
    event EmergencyPauseActivatedV1(
        address indexed actor,
        bytes32 indexed reason,
        uint64 timestamp,
        uint16 version
    );
    event EmergencyPauseRecoveredV1(
        address indexed actor,
        uint64 timestamp,
        uint16 version
    );

    // Disputes
    /**
     * @notice Emitted when a dispute is opened against a provisional outcome.
     * @param claimId            Claim under dispute.
     * @param disputeId          Monotonic dispute identifier.
     * @param challenger         Address that opened the dispute.
     * @param challengedOutcome  Provisional outcome contended (encoded: 0 = TRUE, 1 = FALSE).
     * @param challengedStatus   Registry status that was contested (VerifiedTrue/VerifiedFalse).
     * @param bondToken          Bond token locked through the vault.
     * @param bondAmount         Bond amount locked.
     * @param appealDeadline     Frozen deadline before which the appeal round must close.
     * @param appealRationaleHash Hash of the challenger's rationale/evidence.
     * @param timestamp          Opening block timestamp.
     * @param version            Event schema version (1).
     */
    event DisputeOpenedV1(
        uint256 indexed claimId,
        uint256 indexed disputeId,
        address indexed challenger,
        uint8 challengedOutcome,
        uint8 challengedStatus,
        address bondToken,
        uint256 bondAmount,
        uint64 appealDeadline,
        bytes32 appealRationaleHash,
        uint64 timestamp,
        uint16 version
    );
}
