// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../governance/GovernanceOwnable.sol";

/**
 * @title ReputationEngine
 * @notice On-chain reputation registry for TruthBounty V2 protocol
 * @dev Stores, manages, and exposes immutable reputation data for verifiers.
 *      Provides deterministic reputation values for weighted verification,
 *      reward distribution, and governance eligibility.
 *
 * Key Features:
 * - Reputation registry mapping verifier addresses to reputation records
 * - Deterministic reputation values with extensible storage
 * - Lazy initialization for new verifiers
 * - Reputation weight calculation for verification
 * - Protocol-wide statistics tracking
 * - Immutable reputation history through events
 * - Upgrade-safe storage layout
 */
contract ReputationEngine is AccessControl, ReentrancyGuard, GovernanceOwnable {
    // ============ Roles ============

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPDATE_ROLE = keccak256("UPDATE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ============ Constants ============

    /// @notice Fixed-point precision for reputation scores (1e18 = 100%)
    uint256 public constant BASE_MULTIPLIER = 1e18;

    /// @notice Default initial reputation score for new verifiers (100% = 1.0x)
    uint256 public constant DEFAULT_INITIAL_SCORE = 1e18;

    /// @notice Minimum reputation score (10% = 0.1x)
    uint256 public constant MIN_REPUTATION_SCORE = 1e17;

    /// @notice Maximum reputation score (1000% = 10x)
    uint256 public constant MAX_REPUTATION_SCORE = 10e18;

    /// @notice Storage gap for future upgrades
    uint256[50] private __gap;

    // ============ Structs ============

    /**
     * @notice Reputation record for a verifier
     * @dev Extensible structure for future protocol versions
     */
    struct Reputation {
        uint256 score;                    // Current reputation score (scaled by 1e18)
        uint256 successfulVerifications;  // Total successful verifications
        uint256 failedVerifications;      // Total failed/incorrect verifications
        uint256 disputedVerifications;    // Total disputed claims
        uint256 totalStake;               // Total stake participated (cumulative)
        uint256 lastUpdated;              // Timestamp of last update
        bool exists;                      // Whether reputation record exists
    }

    /**
     * @notice Protocol-wide statistics
     */
    struct ProtocolStatistics {
        uint256 totalVerifiers;           // Total number of verifiers
        uint256 totalSuccessfulVerifications; // Cumulative successful verifications
        uint256 totalFailedVerifications; // Cumulative failed verifications
        uint256 totalDisputedClaims;      // Cumulative disputed claims
        uint256 totalRewardsEarned;       // Total rewards earned by verifiers
        uint256 totalStakeParticipated;   // Total stake participated across protocol
    }

    // ============ Storage ============

    /// @notice Reputation registry mapping verifier addresses to reputation records
    mapping(address => Reputation) private reputations;

    /// @notice Protocol-wide statistics
    ProtocolStatistics public protocolStats;

    /// @notice Default initial reputation score (configurable by governance)
    uint256 public defaultInitialScore = DEFAULT_INITIAL_SCORE;

    /// @notice Minimum reputation score (configurable by governance)
    uint256 public minReputationScore = MIN_REPUTATION_SCORE;

    /// @notice Maximum reputation score (configurable by governance)
    uint256 public maxReputationScore = MAX_REPUTATION_SCORE;

    /// @notice Whether reputation initialization is restricted to UPDATE_ROLE
    bool public restrictedInitialization = false;

    // ============ Events ============

    /**
     * @notice Emitted when a new reputation record is created
     */
    event ReputationCreated(address indexed verifier);

    /**
     * @notice Emitted when a reputation record is initialized
     */
    event ReputationInitialized(
        address indexed verifier,
        uint256 initialScore,
        uint256 timestamp
    );

    /**
     * @notice Emitted when reputation score is updated
     */
    event ReputationScoreUpdated(
        address indexed verifier,
        uint256 oldScore,
        uint256 newScore,
        uint256 timestamp
    );

    /**
     * @notice Emitted when verification statistics are updated
     */
    event VerificationStatsUpdated(
        address indexed verifier,
        uint256 successfulVerifications,
        uint256 failedVerifications,
        uint256 disputedVerifications,
        uint256 timestamp
    );

    /**
     * @notice Emitted when stake participation is updated
     */
    event StakeParticipationUpdated(
        address indexed verifier,
        uint256 totalStake,
        uint256 timestamp
    );

    /**
     * @notice Emitted when protocol statistics are updated
     */
    event ProtocolStatisticsUpdated(
        uint256 totalVerifiers,
        uint256 totalSuccessfulVerifications,
        uint256 totalFailedVerifications,
        uint256 totalDisputedClaims,
        uint256 totalRewardsEarned,
        uint256 totalStakeParticipated
    );

    /**
     * @notice Emitted when reputation bounds are updated
     */
    event ReputationBoundsUpdated(
        uint256 oldMinScore,
        uint256 oldMaxScore,
        uint256 newMinScore,
        uint256 newMaxScore
    );

    /**
     * @notice Emitted when default initial score is updated
     */
    event DefaultInitialScoreUpdated(
        uint256 oldScore,
        uint256 newScore
    );

    /**
     * @notice Emitted when initialization restriction is toggled
     */
    event InitializationRestrictionToggled(bool restricted);

    // ============ Errors ============

    error VerifierAlreadyExists(address verifier);
    error VerifierNotFound(address verifier);
    error InvalidReputationScore(uint256 score);
    error InvalidReputationBounds(uint256 minScore, uint256 maxScore);
    error UnauthorizedUpdate();
    error InvalidZeroAddress();

    // ============ Constructor ============

    constructor(
        address initialAdmin,
        address _governanceController
    ) {
        require(initialAdmin != address(0), "Invalid admin address");

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
        _grantRole(UPDATE_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);

        _setRoleAdmin(UPDATE_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);

        _initializeGovernance(_governanceController, initialAdmin, initialAdmin);
    }

    // ============ Reputation Initialization ============

    /**
     * @notice Initialize reputation for a new verifier
     * @param verifier The address of the verifier
     * @dev Creates a new reputation record with default values
     *      Reverts if verifier already has a reputation record
     */
    function initializeReputation(address verifier) external nonReentrant whenNotPaused {
        if (restrictedInitialization && !hasRole(UPDATE_ROLE, msg.sender)) {
            revert UnauthorizedUpdate();
        }
        if (verifier == address(0)) revert InvalidZeroAddress();
        if (reputations[verifier].exists) revert VerifierAlreadyExists(verifier);

        uint256 initialScore = defaultInitialScore;

        reputations[verifier] = Reputation({
            score: initialScore,
            successfulVerifications: 0,
            failedVerifications: 0,
            disputedVerifications: 0,
            totalStake: 0,
            lastUpdated: block.timestamp,
            exists: true
        });

        protocolStats.totalVerifiers += 1;

        emit ReputationCreated(verifier);
        emit ReputationInitialized(verifier, initialScore, block.timestamp);
        emit ProtocolStatisticsUpdated(
            protocolStats.totalVerifiers,
            protocolStats.totalSuccessfulVerifications,
            protocolStats.totalFailedVerifications,
            protocolStats.totalDisputedClaims,
            protocolStats.totalRewardsEarned,
            protocolStats.totalStakeParticipated
        );
    }

    /**
     * @notice Initialize reputation with custom initial score (UPDATE_ROLE only)
     * @param verifier The address of the verifier
     * @param initialScore The initial reputation score
     * @dev Allows setting custom initial score for special cases (e.g., migration)
     */
    function initializeReputationWithScore(
        address verifier,
        uint256 initialScore
    ) external onlyRole(UPDATE_ROLE) nonReentrant whenNotPaused {
        if (verifier == address(0)) revert InvalidZeroAddress();
        if (reputations[verifier].exists) revert VerifierAlreadyExists(verifier);
        if (initialScore < minReputationScore || initialScore > maxReputationScore) {
            revert InvalidReputationScore(initialScore);
        }

        reputations[verifier] = Reputation({
            score: initialScore,
            successfulVerifications: 0,
            failedVerifications: 0,
            disputedVerifications: 0,
            totalStake: 0,
            lastUpdated: block.timestamp,
            exists: true
        });

        protocolStats.totalVerifiers += 1;

        emit ReputationCreated(verifier);
        emit ReputationInitialized(verifier, initialScore, block.timestamp);
        emit ProtocolStatisticsUpdated(
            protocolStats.totalVerifiers,
            protocolStats.totalSuccessfulVerifications,
            protocolStats.totalFailedVerifications,
            protocolStats.totalDisputedClaims,
            protocolStats.totalRewardsEarned,
            protocolStats.totalStakeParticipated
        );
    }

    // ============ Reputation Retrieval ============

    /**
     * @notice Get full reputation record for a verifier
     * @param verifier The address of the verifier
     * @return reputation The reputation record
     */
    function getReputation(address verifier) external view returns (Reputation memory reputation) {
        if (!reputations[verifier].exists) revert VerifierNotFound(verifier);
        return reputations[verifier];
    }

    /**
     * @notice Get reputation score for a verifier
     * @param verifier The address of the verifier
     * @return score The reputation score
     */
    function getReputationScore(address verifier) external view returns (uint256 score) {
        if (!reputations[verifier].exists) revert VerifierNotFound(verifier);
        return reputations[verifier].score;
    }

    /**
     * @notice Check if a verifier has a reputation record
     * @param verifier The address of the verifier
     * @return exists True if reputation record exists
     */
    function reputationExists(address verifier) external view returns (bool exists) {
        return reputations[verifier].exists;
    }

    // ============ Reputation Weight Calculation ============

    /**
     * @notice Calculate reputation multiplier for verification weight
     * @param verifier The address of the verifier
     * @return multiplier The reputation multiplier (scaled by 1e18)
     * @dev Multiplier = reputationScore, capped at 10e18 (10x)
     *      Capped at 10x to prevent excessive dominance
     */
    function calculateReputationMultiplier(address verifier) external view returns (uint256 multiplier) {
        if (!reputations[verifier].exists) revert VerifierNotFound(verifier);
        
        uint256 score = reputations[verifier].score;
        multiplier = score;
        
        // Cap at 10x to prevent excessive dominance
        uint256 maxMultiplier = 10e18;
        if (multiplier > maxMultiplier) {
            multiplier = maxMultiplier;
        }
    }

    /**
     * @notice Calculate verification weight based on stake and reputation
     * @param stakeAmount The raw stake amount
     * @param verifier The address of the verifier
     * @return weight The verification weight (stake * reputation multiplier)
     * @dev Verification Weight = Stake Weight × Reputation Multiplier
     */
    function calculateWeight(uint256 stakeAmount, address verifier) external view returns (uint256 weight) {
        if (!reputations[verifier].exists) revert VerifierNotFound(verifier);
        
        uint256 multiplier = this.calculateReputationMultiplier(verifier);
        weight = (stakeAmount * multiplier) / BASE_MULTIPLIER;
    }

    // ============ View Helpers ============

    /**
     * @notice Check if a verifier is eligible to participate (has reputation record)
     * @param verifier The address of the verifier
     * @return eligible True if verifier is eligible
     */
    function isEligibleVerifier(address verifier) external view returns (bool eligible) {
        return reputations[verifier].exists;
    }

    /**
     * @notice Get protocol statistics
     * @return stats The protocol statistics
     */
    function getStatistics() external view returns (ProtocolStatistics memory stats) {
        return protocolStats;
    }

    /**
     * @notice Get verifier statistics
     * @param verifier The address of the verifier
     * @return successfulVerifications Total successful verifications
     * @return failedVerifications Total failed verifications
     * @return disputedVerifications Total disputed verifications
     * @return totalStake Total stake participated
     */
    function getVerifierStatistics(
        address verifier
    ) external view returns (
        uint256 successfulVerifications,
        uint256 failedVerifications,
        uint256 disputedVerifications,
        uint256 totalStake
    ) {
        if (!reputations[verifier].exists) revert VerifierNotFound(verifier);
        
        Reputation storage rep = reputations[verifier];
        return (
            rep.successfulVerifications,
            rep.failedVerifications,
            rep.disputedVerifications,
            rep.totalStake
        );
    }

    // ============ Admin/Governance Functions ============

    /**
     * @notice Set reputation bounds (governance-controlled)
     * @param _minScore Minimum reputation score
     * @param _maxScore Maximum reputation score
     */
    function setReputationBounds(
        uint256 _minScore,
        uint256 _maxScore
    ) external onlyGovernanceOrAdmin {
        if (_minScore == 0 || _minScore >= _maxScore) {
            revert InvalidReputationBounds(_minScore, _maxScore);
        }

        uint256 oldMin = minReputationScore;
        uint256 oldMax = maxReputationScore;

        minReputationScore = _minScore;
        maxReputationScore = _maxScore;

        emit ReputationBoundsUpdated(oldMin, oldMax, _minScore, _maxScore);
        emit ParameterUpdatedByGovernance(
            keccak256("REPUTATION_MIN_SCORE"),
            oldMin,
            _minScore
        );
        emit ParameterUpdatedByGovernance(
            keccak256("REPUTATION_MAX_SCORE"),
            oldMax,
            _maxScore
        );
    }

    /**
     * @notice Set default initial reputation score (governance-controlled)
     * @param _score The default initial score
     */
    function setDefaultInitialScore(uint256 _score) external onlyGovernanceOrAdmin {
        if (_score == 0) revert InvalidReputationScore(_score);

        uint256 oldScore = defaultInitialScore;
        defaultInitialScore = _score;

        emit DefaultInitialScoreUpdated(oldScore, _score);
        emit ParameterUpdatedByGovernance(
            keccak256("DEFAULT_INITIAL_REPUTATION_SCORE"),
            oldScore,
            _score
        );
    }

    /**
     * @notice Toggle initialization restriction for security
     * @param restricted Whether initialization is restricted to UPDATE_ROLE
     */
    function setInitializationRestriction(bool restricted) external onlyRole(ADMIN_ROLE) {
        restrictedInitialization = restricted;
        emit InitializationRestrictionToggled(restricted);
    }

    // ============ Reputation Update Functions (Protocol Integration) ============

    /**
     * @notice Update reputation score (UPDATE_ROLE only)
     * @param verifier The address of the verifier
     * @param newScore The new reputation score
     * @dev Called by Reputation Update Engine after verification settlement
     *      Validates score bounds and updates protocol statistics
     */
    function updateReputationScore(
        address verifier,
        uint256 newScore
    ) external onlyRole(UPDATE_ROLE) nonReentrant whenNotPaused {
        if (!reputations[verifier].exists) revert VerifierNotFound(verifier);
        if (newScore < minReputationScore || newScore > maxReputationScore) {
            revert InvalidReputationScore(newScore);
        }

        uint256 oldScore = reputations[verifier].score;
        reputations[verifier].score = newScore;
        reputations[verifier].lastUpdated = block.timestamp;

        emit ReputationScoreUpdated(verifier, oldScore, newScore, block.timestamp);
    }

    /**
     * @notice Record successful verification (UPDATE_ROLE only)
     * @param verifier The address of the verifier
     * @param stakeAmount The stake amount used in verification
     * @dev Called by Verification Aggregation after successful verification
     */
    function recordSuccessfulVerification(
        address verifier,
        uint256 stakeAmount
    ) external onlyRole(UPDATE_ROLE) nonReentrant whenNotPaused {
        if (!reputations[verifier].exists) revert VerifierNotFound(verifier);

        reputations[verifier].successfulVerifications += 1;
        reputations[verifier].totalStake += stakeAmount;
        reputations[verifier].lastUpdated = block.timestamp;

        protocolStats.totalSuccessfulVerifications += 1;
        protocolStats.totalStakeParticipated += stakeAmount;

        emit VerificationStatsUpdated(
            verifier,
            reputations[verifier].successfulVerifications,
            reputations[verifier].failedVerifications,
            reputations[verifier].disputedVerifications,
            block.timestamp
        );
        emit StakeParticipationUpdated(verifier, reputations[verifier].totalStake, block.timestamp);
        emit ProtocolStatisticsUpdated(
            protocolStats.totalVerifiers,
            protocolStats.totalSuccessfulVerifications,
            protocolStats.totalFailedVerifications,
            protocolStats.totalDisputedClaims,
            protocolStats.totalRewardsEarned,
            protocolStats.totalStakeParticipated
        );
    }

    /**
     * @notice Record failed verification (UPDATE_ROLE only)
     * @param verifier The address of the verifier
     * @param stakeAmount The stake amount used in verification
     * @dev Called by Verification Aggregation after failed verification
     */
    function recordFailedVerification(
        address verifier,
        uint256 stakeAmount
    ) external onlyRole(UPDATE_ROLE) nonReentrant whenNotPaused {
        if (!reputations[verifier].exists) revert VerifierNotFound(verifier);

        reputations[verifier].failedVerifications += 1;
        reputations[verifier].totalStake += stakeAmount;
        reputations[verifier].lastUpdated = block.timestamp;

        protocolStats.totalFailedVerifications += 1;
        protocolStats.totalStakeParticipated += stakeAmount;

        emit VerificationStatsUpdated(
            verifier,
            reputations[verifier].successfulVerifications,
            reputations[verifier].failedVerifications,
            reputations[verifier].disputedVerifications,
            block.timestamp
        );
        emit StakeParticipationUpdated(verifier, reputations[verifier].totalStake, block.timestamp);
        emit ProtocolStatisticsUpdated(
            protocolStats.totalVerifiers,
            protocolStats.totalSuccessfulVerifications,
            protocolStats.totalFailedVerifications,
            protocolStats.totalDisputedClaims,
            protocolStats.totalRewardsEarned,
            protocolStats.totalStakeParticipated
        );
    }

    /**
     * @notice Record disputed claim (UPDATE_ROLE only)
     * @param verifier The address of the verifier
     * @param stakeAmount The stake amount used in verification
     * @dev Called by Verification Aggregation when a claim is disputed
     */
    function recordDisputedClaim(
        address verifier,
        uint256 stakeAmount
    ) external onlyRole(UPDATE_ROLE) nonReentrant whenNotPaused {
        if (!reputations[verifier].exists) revert VerifierNotFound(verifier);

        reputations[verifier].disputedVerifications += 1;
        reputations[verifier].totalStake += stakeAmount;
        reputations[verifier].lastUpdated = block.timestamp;

        protocolStats.totalDisputedClaims += 1;
        protocolStats.totalStakeParticipated += stakeAmount;

        emit VerificationStatsUpdated(
            verifier,
            reputations[verifier].successfulVerifications,
            reputations[verifier].failedVerifications,
            reputations[verifier].disputedVerifications,
            block.timestamp
        );
        emit StakeParticipationUpdated(verifier, reputations[verifier].totalStake, block.timestamp);
        emit ProtocolStatisticsUpdated(
            protocolStats.totalVerifiers,
            protocolStats.totalSuccessfulVerifications,
            protocolStats.totalFailedVerifications,
            protocolStats.totalDisputedClaims,
            protocolStats.totalRewardsEarned,
            protocolStats.totalStakeParticipated
        );
    }

    /**
     * @notice Record reward earned (UPDATE_ROLE only)
     * @param verifier The address of the verifier
     * @param rewardAmount The reward amount earned
     * @dev Called by Reward Engine after reward distribution
     */
    function recordRewardEarned(
        address verifier,
        uint256 rewardAmount
    ) external onlyRole(UPDATE_ROLE) nonReentrant whenNotPaused {
        if (!reputations[verifier].exists) revert VerifierNotFound(verifier);

        protocolStats.totalRewardsEarned += rewardAmount;

        emit ProtocolStatisticsUpdated(
            protocolStats.totalVerifiers,
            protocolStats.totalSuccessfulVerifications,
            protocolStats.totalFailedVerifications,
            protocolStats.totalDisputedClaims,
            protocolStats.totalRewardsEarned,
            protocolStats.totalStakeParticipated
        );
    }

    /**
     * @notice Batch update verification statistics (UPDATE_ROLE only)
     * @param verifiers Array of verifier addresses
     * @param successCount Array of successful verification counts
     * @param failCount Array of failed verification counts
     * @param disputeCount Array of disputed claim counts
     * @dev Efficient batch update for multiple verifiers
     */
    function batchUpdateVerificationStats(
        address[] calldata verifiers,
        uint256[] calldata successCount,
        uint256[] calldata failCount,
        uint256[] calldata disputeCount
    ) external onlyRole(UPDATE_ROLE) nonReentrant {
        uint256 length = verifiers.length;
        require(
            length == successCount.length &&
            length == failCount.length &&
            length == disputeCount.length,
            "Array length mismatch"
        );

        uint256 totalSuccess = 0;
        uint256 totalFail = 0;
        uint256 totalDispute = 0;

        for (uint256 i = 0; i < length; i++) {
            address verifier = verifiers[i];
            if (!reputations[verifier].exists) revert VerifierNotFound(verifier);

            reputations[verifier].successfulVerifications += successCount[i];
            reputations[verifier].failedVerifications += failCount[i];
            reputations[verifier].disputedVerifications += disputeCount[i];
            reputations[verifier].lastUpdated = block.timestamp;

            totalSuccess += successCount[i];
            totalFail += failCount[i];
            totalDispute += disputeCount[i];

            emit VerificationStatsUpdated(
                verifier,
                reputations[verifier].successfulVerifications,
                reputations[verifier].failedVerifications,
                reputations[verifier].disputedVerifications,
                block.timestamp
            );
        }

        protocolStats.totalSuccessfulVerifications += totalSuccess;
        protocolStats.totalFailedVerifications += totalFail;
        protocolStats.totalDisputedClaims += totalDispute;

        emit ProtocolStatisticsUpdated(
            protocolStats.totalVerifiers,
            protocolStats.totalSuccessfulVerifications,
            protocolStats.totalFailedVerifications,
            protocolStats.totalDisputedClaims,
            protocolStats.totalRewardsEarned,
            protocolStats.totalStakeParticipated
        );
    }

    // ============ Pause Functions ============

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
