// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IClaimRegistry.sol";
import "../VerificationAggregator.sol";

/**
 * @title IProvisionalSettlementEngine
 * @notice Interface for the TruthBounty V2 Provisional Settlement Engine (SC-015).
 * @dev Manages permissionless post-verification consensus aggregation, provisional outcome
 *      recording, challenge window initiation, and fund lock enforcement.
 */
interface IProvisionalSettlementEngine {

    // =========================================================================
    // Enums & Structs
    // =========================================================================

    enum Outcome {
        UNRESOLVED,
        VERIFIED_TRUE,
        VERIFIED_FALSE,
        INCONCLUSIVE
    }

    struct ProvisionalOutcome {
        Outcome outcome;
        uint256 confidence;         // in basis points (0 - 10000)
        uint256 trueWeight;
        uint256 falseWeight;
        uint256 totalWeight;
        uint256 verifierCount;
        uint256 challengeDeadline;  // block.timestamp + challengeWindowDuration
        uint256 settledAt;          // timestamp when provisional settlement occurred
        uint256 parameterVersion;   // governance parameter version active at settlement
        bool settled;
    }

    // =========================================================================
    // Events
    // =========================================================================

    event RoundAggregated(
        uint256 indexed claimId,
        Outcome outcome,
        uint256 confidence,
        uint256 trueWeight,
        uint256 falseWeight,
        uint256 totalWeight,
        uint256 verifierCount
    );

    event ProvisionalOutcomeCreated(
        uint256 indexed claimId,
        Outcome outcome,
        uint256 challengeDeadline,
        uint256 confidence,
        address indexed triggeredBy
    );

    event ChallengeWindowDurationUpdated(
        uint256 oldDuration,
        uint256 newDuration
    );

    event AggregatorUpdated(
        address indexed oldAggregator,
        address indexed newAggregator
    );

    event ParameterVersionUpdated(
        uint256 oldVersion,
        uint256 newVersion
    );

    // =========================================================================
    // External Functions
    // =========================================================================

    /**
     * @notice Permissionlessly execute provisional settlement for an expired verification round.
     * @param claimId The unique ID of the claim to settle.
     * @return outcome The stored provisional outcome record.
     */
    function provisionalSettle(uint256 claimId) external returns (ProvisionalOutcome memory outcome);

    /**
     * @notice Read the provisional outcome for a given claim.
     * @param claimId The unique ID of the claim.
     */
    function getProvisionalOutcome(uint256 claimId) external view returns (ProvisionalOutcome memory);

    /**
     * @notice Check whether a claim has already undergone provisional settlement.
     * @param claimId The unique ID of the claim.
     */
    function isProvisionalSettled(uint256 claimId) external view returns (bool);

    /**
     * @notice Check whether the dispute challenge window is currently active for a claim.
     * @param claimId The unique ID of the claim.
     */
    function isChallengeWindowOpen(uint256 claimId) external view returns (bool);

    /**
     * @notice Current challenge window duration in seconds.
     */
    function challengeWindowDuration() external view returns (uint256);

    /**
     * @notice Active governance parameter version.
     */
    function parameterVersion() external view returns (uint256);
}
