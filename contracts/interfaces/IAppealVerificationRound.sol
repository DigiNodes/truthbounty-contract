// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../VerificationAggregator.sol";

/**
 * @title IAppealVerificationRound
 * @notice Interface for the TruthBounty V2 Appeal Verification Round Manager (SC-017).
 * @dev Manages the opening, voting, custody, isolation, and closing of the single appeal round for disputed claims.
 */
interface IAppealVerificationRound is IVerificationSource {

    // =========================================================================
    // Enums & Structs
    // =========================================================================

    enum AppealRoundStatus {
        NONE,
        OPEN,
        CLOSED
    }

    struct AppealVote {
        bool voted;
        bool support;
        uint256 stakeAmount;
        uint256 effectiveStake;
        uint256 timestamp;
    }

    struct AppealRoundConfig {
        uint256 roundDuration;       // e.g. 3 days
        uint256 minStakeAmount;      // higher minimum stake for appeal
        uint256 stakeMultiplierBps;  // e.g. 15000 = 1.5x
        uint256 maxWeightCap;        // maximum weight cap per verifier
        uint256 parameterVersion;
    }

    struct AppealRound {
        uint256 claimId;
        AppealRoundStatus status;
        uint256 openedAt;
        uint256 deadline;
        uint256 minStakeAmount;
        uint256 stakeMultiplierBps;
        uint256 maxWeightCap;
        uint256 totalTrueStake;
        uint256 totalFalseStake;
        uint256 totalTrueWeight;
        uint256 totalFalseWeight;
        uint256 verifierCount;
    }

    // =========================================================================
    // Events
    // =========================================================================

    event AppealRoundOpened(
        uint256 indexed claimId,
        uint256 deadline,
        uint256 minStake,
        uint256 multiplierBps,
        address indexed openedBy
    );

    event AppealVoteSubmitted(
        uint256 indexed claimId,
        address indexed verifier,
        bool support,
        uint256 stakeAmount,
        uint256 effectiveWeight
    );

    event AppealRoundClosed(
        uint256 indexed claimId,
        uint256 totalTrueWeight,
        uint256 totalFalseWeight,
        uint256 verifierCount,
        address indexed closedBy
    );

    event DefaultAppealConfigUpdated(
        uint256 duration,
        uint256 minStake,
        uint256 multiplierBps,
        uint256 maxWeightCap
    );

    // =========================================================================
    // Functions
    // =========================================================================

    function openAppealRound(uint256 claimId) external;

    function submitAppealVote(uint256 claimId, bool support, uint256 stakeAmount) external;

    function closeAppealRound(uint256 claimId) external;

    function getAppealRound(uint256 claimId) external view returns (AppealRound memory);

    function getAppealVote(uint256 claimId, address verifier) external view returns (AppealVote memory);

    function isAppealOpen(uint256 claimId) external view returns (bool);
}
