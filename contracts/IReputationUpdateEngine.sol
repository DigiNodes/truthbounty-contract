// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IReputationUpdateEngine
 * @notice Interface for the protocol's sole authorised reputation mutation engine
 * @dev Every completed claim resolution produces a transparent and reproducible
 *      reputation update that rewards accurate participation while penalising
 *      inaccurate or malicious behaviour.
 *
 *      Only authorised protocol contracts may invoke the update function.
 *      EOAs and external contracts must never modify reputation directly.
 *
 *      SC-008 — Reputation Update Engine
 */
interface IReputationUpdateEngine {

    // ============ Types ============

    /// @notice Reason for a reputation update
    enum UpdateReason {
        CORRECT_VERIFICATION,
        INCORRECT_VERIFICATION,
        DISPUTED_CLAIM,
        MALICIOUS_BEHAVIOUR
    }

    /// @notice A reputation update instruction
    struct ReputationUpdate {
        address verifier;
        int256 delta;                // Positive = reward, negative = penalty
        UpdateReason reason;
        uint256 claimId;
    }

    /// @notice Immutable update record stored on-chain
    struct ReputationUpdateRecord {
        uint256 claimId;
        int256  delta;
        uint256 timestamp;
        UpdateReason reason;
    }

    // ============ Events ============

    /// @notice Emitted when a verifier's reputation score changes
    event ReputationUpdated(
        address indexed verifier,
        int256  delta,
        uint256 newScore,
        uint256 claimId
    );

    /// @notice Emitted when governance parameters are updated
    event UpdateParametersUpdated(
        bytes32 indexed paramId,
        uint256 oldValue,
        uint256 newValue
    );

    // ============ Core Functions ============

    /**
     * @notice Apply a deterministic reputation update to a verifier
     * @param update The update parameters (verifier, delta, reason, claimId)
     * @dev Only authorised protocol components may call this.
     *      Reverts if the update would cause underflow/overflow or
     *      if the claimId has already been used for this verifier.
     */
    function updateReputation(ReputationUpdate calldata update) external;

    // ============ View Functions ============

    /**
     * @notice Get a verifier's current reputation score
     * @param verifier The address to query
     * @return score The current reputation score
     */
    function getReputation(address verifier) external view returns (uint256 score);

    /**
     * @notice Get the number of update records for a verifier
     */
    function getUpdateCount(address verifier) external view returns (uint256);

    /**
     * @notice Get a paginated slice of update history for a verifier
     * @param verifier Address to query
     * @param offset   Start index
     * @param limit    Max entries to return
     */
    function getUpdateHistory(
        address verifier,
        uint256 offset,
        uint256 limit
    ) external view returns (ReputationUpdateRecord[] memory);

    /**
     * @notice Check whether a verifier has already been updated for a claim
     * @param verifier The verifier address
     * @param claimId  The claim ID
     * @return True if the verifier already received an update for this claim
     */
    function isClaimProcessed(address verifier, uint256 claimId) external view returns (bool);

    // ============ Governance Parameters ============

    /// @notice Reputation increment for a correct verification (default: +10)
    function rewardIncrement() external view returns (uint256);

    /// @notice Reputation penalty for an incorrect verification (default: -10)
    function penaltyAmount() external view returns (uint256);

    /// @notice Multiplier applied to penalties for malicious behaviour (default: 5x)
    function maliciousMultiplier() external view returns (uint256);

    /// @notice Adjustment applied to disputes (neutral — default: 0)
    function disputeAdjustment() external view returns (int256);

    /// @notice Minimum reputation floor (default: 0)
    function minimumReputationFloor() external view returns (uint256);

    /// @notice Maximum reputation cap (default: type(uint256).max, i.e. no cap)
    function maximumReputationCap() external view returns (uint256);
}
