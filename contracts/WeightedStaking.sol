// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./IReputationOracle.sol";
import "./governance/GovernanceOwnable.sol";
import "./governance/GovernanceHooks.sol";

/**
 * @title WeightedStaking
 * @notice Implements reputation-weighted staking power for fair influence scaling
 * @dev Integrates with reputation oracles to calculate effective stake based on reputation scores
 *
 * Key Features:
 * - Deterministic weighted stake calculation
 * - Reputation score validation and bounds checking
 * - Support for multiple reputation oracle sources
 * - Prevents low-reputation dominance through minimum thresholds
 * - Emergency fallback to equal weighting
 */
contract WeightedStaking is AccessControl, ReentrancyGuard, GovernanceOwnable {
    // ============ Roles ============

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ============ State Variables ============

    /// @notice The reputation oracle used for score lookups
    IReputationOracle public reputationOracle;

    /// @notice Base multiplier for reputation scaling (1e18 = 100%)
    uint256 public constant BASE_MULTIPLIER = 1e18;

    /// @notice Minimum reputation score to prevent zero/near-zero weights (0.1 = 10%)
    uint256 public minReputationScore = 1e17; // 0.1 * 1e18

    /// @notice Maximum reputation score cap to prevent excessive dominance (10x = 1000%)
    uint256 public maxReputationScore = 10e18; // 10 * 1e18

    /// @notice Default reputation for users without a score (1.0 = 100%)
    uint256 public defaultReputationScore = 1e18; // 1.0 * 1e18

    /// @notice Whether to use weighted staking (can be disabled in emergencies)
    bool public weightedStakingEnabled = true;

    /// @notice Whether to apply sqrt scaling to reputation (matches API behaviour)
    bool public useSqrtWeighting = true;
    
    // Governance parameter IDs
    bytes32 public constant GOVERNANCE_PARAM_MIN_REP = keccak256("MIN_REPUTATION_SCORE");
    bytes32 public constant GOVERNANCE_PARAM_MAX_REP = keccak256("MAX_REPUTATION_SCORE");
    bytes32 public constant GOVERNANCE_PARAM_DEFAULT_REP = keccak256("DEFAULT_REPUTATION_SCORE");
    bytes32 public constant GOVERNANCE_PARAM_WEIGHTED_ENABLED = keccak256("WEIGHTED_STAKING_ENABLED");

    // ============ Structs ============

    /// @notice Stores weighted stake calculation result
    struct WeightedStakeResult {
        uint256 rawStake;           // Original stake amount
        uint256 reputationScore;    // Reputation score used
        uint256 effectiveStake;     // Calculated weighted stake
        uint256 weight;             // Weight multiplier applied (1e18 = 100%)
    }

    // ============ Events ============

    event ReputationOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event ReputationBoundsUpdated(uint256 minScore, uint256 maxScore);
    event DefaultReputationUpdated(uint256 newDefault);
    event WeightedStakingToggled(bool enabled);
    event SqrtWeightingToggled(bool enabled);
    event WeightedStakeCalculated(
        address indexed user,
        uint256 rawStake,
        uint256 reputationScore,
        uint256 effectiveStake,
        uint256 weight
    );

    // ============ Errors ============

    error InvalidReputationOracle();
    error InvalidReputationBounds();
    error InvalidDefaultReputation();
    error OracleNotActive();
    error ZeroStakeAmount();

    // ============ Constructor ============

    /**
     * @notice Initialize the weighted staking contract
     * @param _reputationOracle Address of the reputation oracle contract
     */
    constructor(address _reputationOracle, address initialAdmin, address _governanceController) {
        if (_reputationOracle == address(0)) revert InvalidReputationOracle();
        require(initialAdmin != address(0), "Invalid admin address");
        
        reputationOracle = IReputationOracle(_reputationOracle);
        
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
        
        // Initialize governance
        _initializeGovernance(_governanceController, initialAdmin, initialAdmin);
    }

    // ============ Core Functions ============

    /**
     * @notice Calculate effective stake based on reputation
     * @param user The address of the staker
     * @param stakeAmount The raw stake amount
     * @return result The weighted stake calculation result
     *
     * @dev Formula: effectiveStake = stakeAmount × (reputationScore / BASE_MULTIPLIER)
     *      - If weighted staking is disabled, returns stakeAmount unchanged
     *      - Reputation scores are clamped between min and max bounds
     *      - Uses default reputation if oracle returns 0 or is inactive
     */
    function calculateWeightedStake(
        address user,
        uint256 stakeAmount
    ) public view returns (WeightedStakeResult memory result) {
        if (stakeAmount == 0) revert ZeroStakeAmount();

        result.rawStake = stakeAmount;

        // If weighted staking is disabled, return equal weight
        if (!weightedStakingEnabled) {
            result.reputationScore = BASE_MULTIPLIER;
            result.weight = BASE_MULTIPLIER;
            result.effectiveStake = stakeAmount;
            return result;
        }

        // Get reputation score from oracle
        uint256 rawReputationScore = _getReputationScore(user);

        // Apply bounds to reputation score
        uint256 boundedScore = _applyReputationBounds(rawReputationScore);

        // Apply sqrt scaling if enabled (matches API behaviour)
        uint256 weight = useSqrtWeighting ? _sqrt(boundedScore * BASE_MULTIPLIER) : boundedScore;
        result.reputationScore = boundedScore;
        result.weight = weight;

        // Calculate effective stake: stake × (weight / BASE_MULTIPLIER)
        result.effectiveStake = (stakeAmount * weight) / BASE_MULTIPLIER;

        return result;
    }

    /**
     * @notice Calculate effective stake and emit event (for state-changing operations)
     * @param user The address of the staker
     * @param stakeAmount The raw stake amount
     * @return effectiveStake The weighted stake amount
     */
    function calculateAndRecordWeightedStake(
        address user,
        uint256 stakeAmount
    ) external nonReentrant returns (uint256 effectiveStake) {
        WeightedStakeResult memory result = calculateWeightedStake(user, stakeAmount);

        emit WeightedStakeCalculated(
            user,
            result.rawStake,
            result.reputationScore,
            result.effectiveStake,
            result.weight
        );

        return result.effectiveStake;
    }

    /**
     * @notice Batch calculate weighted stakes for multiple users
     * @param users Array of user addresses
     * @param stakeAmounts Array of stake amounts
     * @return results Array of weighted stake results
     */
    function batchCalculateWeightedStake(
        address[] calldata users,
        uint256[] calldata stakeAmounts
    ) external view returns (WeightedStakeResult[] memory results) {
        require(users.length == stakeAmounts.length, "Array length mismatch");

        results = new WeightedStakeResult[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            results[i] = calculateWeightedStake(users[i], stakeAmounts[i]);
        }

        return results;
    }

    // ============ Internal Helper Functions ============

    /**
     * @notice Safely get reputation score from oracle with fallback
     * @param user The address to query
     * @return score The reputation score or default if unavailable
     */
    function _getReputationScore(address user) internal view returns (uint256 score) {
        // Check if oracle is active
        try reputationOracle.isActive() returns (bool active) {
            if (!active) {
                return defaultReputationScore;
            }
        } catch {
            return defaultReputationScore;
        }

        // Try to get reputation score
        try reputationOracle.getReputationScore(user) returns (uint256 reputationScore) {
            // If oracle returns 0, use default
            if (reputationScore == 0) {
                return defaultReputationScore;
            }
            return reputationScore;
        } catch {
            // If oracle call fails, use default
            return defaultReputationScore;
        }
    }

    /**
     * @notice Apply min/max bounds to reputation score
     * @param score The raw reputation score
     * @return boundedScore The score clamped between min and max
     */
    function _applyReputationBounds(uint256 score) internal view returns (uint256 boundedScore) {
        if (score < minReputationScore) {
            return minReputationScore;
        }
        if (score > maxReputationScore) {
            return maxReputationScore;
        }
        return score;
    }

    /**
     * @notice Babylonian sqrt for 18-decimal fixed-point numbers
     * @param x The value to take the square root of (18 decimals)
     * @return y The square root result (18 decimals)
     */
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        y = x;
        uint256 z = (x + 1) / 2;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    // ============ Admin Functions ============

    /**
     * @notice Update the reputation oracle address
     * @param _newOracle Address of the new reputation oracle
     */
    function setReputationOracle(address _newOracle) external onlyRole(ADMIN_ROLE) {
        if (_newOracle == address(0)) revert InvalidReputationOracle();

        address oldOracle = address(reputationOracle);
        reputationOracle = IReputationOracle(_newOracle);

        emit ReputationOracleUpdated(oldOracle, _newOracle);
    }

    /**
     * @notice Update the minimum and maximum reputation score bounds
     * @param _minScore New minimum reputation score
     * @param _maxScore New maximum reputation score
     */
    function setReputationBounds(uint256 _minScore, uint256 _maxScore) external onlyRole(ADMIN_ROLE) {
        if (_minScore == 0 || _minScore >= _maxScore) revert InvalidReputationBounds();

        minReputationScore = _minScore;
        maxReputationScore = _maxScore;

        emit ReputationBoundsUpdated(_minScore, _maxScore);
    }

    /**
     * @notice Update the default reputation score for users without reputation
     * @param _defaultScore New default reputation score
     */
    function setDefaultReputationScore(uint256 _defaultScore) external onlyGovernanceOrAdmin {
        if (_defaultScore == 0) revert InvalidDefaultReputation();

        defaultReputationScore = _defaultScore;

        emit DefaultReputationUpdated(_defaultScore);
    }

    /**
     * @notice Enable or disable weighted staking (emergency toggle)
     * @param _enabled Whether to enable weighted staking
     */
    function setWeightedStakingEnabled(bool _enabled) external onlyGovernanceOrAdmin {
        weightedStakingEnabled = _enabled;

        emit WeightedStakingToggled(_enabled);
    }

    /**
     * @notice Enable or disable sqrt-based weighting
     * @param _enabled True to use sqrt, false for linear
     */
    function setSqrtWeighting(bool _enabled) external onlyGovernanceOrAdmin {
        useSqrtWeighting = _enabled;
        emit SqrtWeightingToggled(_enabled);
    }

    // ============ Governance Parameter Updates ============
    
    /**
     * @notice Update minimum reputation score ( governance or admin )
     * @param newMinScore New minimum score
     */
    function setMinReputationScore(uint256 newMinScore) external onlyGovernanceOrAdmin {
        require(newMinScore > 0 && newMinScore < maxReputationScore, "Invalid min score");
        
        uint256 old = minReputationScore;
        minReputationScore = newMinScore;
        
        emit ParameterUpdatedByGovernance(GOVERNANCE_PARAM_MIN_REP, old, newMinScore);
    }
    
    /**
     * @notice Update maximum reputation score ( governance or admin )
     * @param newMaxScore New maximum score
     */
    function setMaxReputationScore(uint256 newMaxScore) external onlyGovernanceOrAdmin {
        require(newMaxScore > minReputationScore, "Invalid max score");
        
        uint256 old = maxReputationScore;
        maxReputationScore = newMaxScore;
        
        emit ParameterUpdatedByGovernance(GOVERNANCE_PARAM_MAX_REP, old, newMaxScore);
    }
    
    /**
     * @notice Update default reputation score ( governance or admin )
     * @param newDefaultScore New default score
     */
    function setDefaultReputationScoreByGov(uint256 newDefaultScore) external onlyGovernanceOrAdmin {
        require(newDefaultScore > 0, "Invalid default score");
        
        uint256 old = defaultReputationScore;
        defaultReputationScore = newDefaultScore;
        
        emit ParameterUpdatedByGovernance(GOVERNANCE_PARAM_DEFAULT_REP, old, newDefaultScore);
    }

    // ============ View Functions ============

    /**
     * @notice Get the current configuration parameters
     * @return oracle Reputation oracle address
     * @return minScore Minimum reputation score
     * @return maxScore Maximum reputation score
     * @return defaultScore Default reputation score
     * @return enabled Whether weighted staking is enabled
     */
    function getConfiguration() external view returns (
        address oracle,
        uint256 minScore,
        uint256 maxScore,
        uint256 defaultScore,
        bool enabled
    ) {
        return (
            address(reputationOracle),
            minReputationScore,
            maxReputationScore,
            defaultReputationScore,
            weightedStakingEnabled
        );
    }

    /**
     * @notice Preview the weight that would be applied to a user's stake
     * @param user The address to check
     * @return weight The weight multiplier (1e18 = 100%)
     */
    function previewWeight(address user) external view returns (uint256 weight) {
        if (!weightedStakingEnabled) {
            return BASE_MULTIPLIER;
        }

        uint256 rawScore = _getReputationScore(user);
        uint256 bounded = _applyReputationBounds(rawScore);
        return useSqrtWeighting ? _sqrt(bounded * BASE_MULTIPLIER) : bounded;
    }
}
