// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
import {IV2Types} from "./IV2Types.sol";

interface IVerification is IV2Module {
    // Events for quorum state changes
    event VerificationSubmitted(
        uint256 indexed verificationId,
        uint256 indexed claimId,
        address indexed verifier,
        bool supportsClaim,
        uint256 stake,
        uint256 quorumStateId
    );

    // Event for quorum completion
    event VerificationQuorumCompleted(
        uint256 indexed claimId,
        uint256 indexed verificationId,
        bool accepted,
        uint256 totalStake
    );

    // Event for quorum griefing detection
    event QuorumGriefingDetected(
        uint256 indexed claimId,
        uint256 minStakeRequired,
        uint256 currentStake,
        uint256 abstaineerCount
    );

    // Submit a new verification vote
    function submitVerification(uint256 claimId, bool supportsClaim, bytes callida rationale) external returns (uint256 verificationId);

    // Get verification details
    function getVerification(uint256 verificationId) external view returns (IV2Types.Verification memory);

    // Claim verifications for a claim
    function claimVerifications(uint256 claimId, uint256 cursor, uint256 limit) external view returns (uint256[] memory ids, uint256 nextCursor);

    // Get quorum state for a claim
    function getQuorumState(uint256 claimId) external view returns (IV2Types.QuorumState memory);

    // Check if quorum is complete
    function isQuorumComplete(uint256 claimId) external view returns (bool);

    // Get quorum parameters
    function getQuorumParameters() external view returns (IV2Types.QuorumParameters memory);
}
