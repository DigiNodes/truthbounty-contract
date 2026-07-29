// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../governance/GovernanceOwnable.sol";
import "../governance/GovernanceHooks.sol";
import "../interfaces/ITruthBountyEvents.sol";
import "../IReputationOracle.sol";

contract RewardEngine is ReentrancyGuard, Pausable, GovernanceOwnable, ITruthBountyEvents {
    // ============ Roles ============

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ============ Constants ============

    uint256 public constant BASE_MULTIPLIER = 1e18;
    uint16 public constant EVENT_SCHEMA_VERSION = 1;
    uint256 public constant PERCENT_DENOMINATOR = 100;
    uint256 public constant MAX_MULTIPLIER = 10e18;
    uint256 public constant MIN_MULTIPLIER = 0;

    // ============ Claim Category ============

    enum ClaimCategory {
        TRIVIAL,
        STANDARD,
        COMPLEX,
        EXPERT
    }

    // ============ Structs ============

    struct RewardCalculation {
        address verifier;
        uint256 baseAmount;
        uint256 reputationMultiplier;
        uint256 difficultyMultiplier;
        uint256 stakeMultiplier;
        uint256 governanceMultiplier;
        uint256 finalAmount;
        uint256 reputationScore;
        uint256 activeStake;
        ClaimCategory category;
        uint256 timestamp;
        bytes32 calculationId;
    }

    struct MultiplierConfig {
        uint256 minReputationMultiplier;
        uint256 maxReputationMultiplier;
        uint256 minDifficultyMultiplier;
        uint256 maxDifficultyMultiplier;
        uint256 minStakeMultiplier;
        uint256 maxStakeMultiplier;
        uint256 minGovernanceMultiplier;
        uint256 maxGovernanceMultiplier;
    }

    // ============ State Variables ============

    IReputationOracle public reputationOracle;

    uint256 public baseRewardRate = 0.01e18;
    uint256 public minReward = 0;
    uint256 public maxReward = type(uint256).max;
    uint256 public dailyEmissionLimit = type(uint256).max;
    uint256 public antiWhaleLimit = type(uint256).max;

    uint256 public minReputationScore = 1e17;
    uint256 public maxReputationScore = 10e18;
    uint256 public defaultReputationScore = 1e18;

    uint256 public minReputationMultiplier = 0.5e18;
    uint256 public maxReputationMultiplier = 2.0e18;
    uint256 public minDifficultyMultiplier = 1.0e18;
    uint256 public maxDifficultyMultiplier = 3.0e18;
    uint256 public minStakeMultiplier = 1.0e18;
    uint256 public maxStakeMultiplier = 1.5e18;
    uint256 public governanceMultiplier = 1.0e18;

    uint256 public lowStakeThreshold = 1000e18;
    uint256 public highStakeThreshold = 10000e18;

    mapping(ClaimCategory => uint256) public categoryMultipliers;
    mapping(bytes32 => RewardCalculation) public calculations;
    mapping(uint256 => uint256) public dailyEmission;
    mapping(uint256 => mapping(address => uint256)) public dailyVerifierRewards;

    bytes32[] public calculationIds;

    uint256 public calculationCount;

    // ============ Events ============

    event RewardCalculated(
        address indexed verifier,
        uint256 amount,
        bytes32 indexed calculationId
    );

    event RewardMultiplierUpdated(
        bytes32 indexed multiplier,
        uint256 oldValue,
        uint256 newValue
    );

    event RewardCapReached(
        address indexed participant,
        uint256 attemptedReward,
        string capType
    );

    event CategoryMultiplierUpdated(
        ClaimCategory indexed category,
        uint256 oldMultiplier,
        uint256 newMultiplier
    );

    event BaseRewardRateUpdated(
        uint256 oldRate,
        uint256 newRate
    );

    event ReputationOracleUpdated(
        address indexed oldOracle,
        address indexed newOracle
    );

    event ReputationBoundsUpdated(
        uint256 oldMin,
        uint256 oldMax,
        uint256 newMin,
        uint256 newMax
    );

    event StakeThresholdsUpdated(
        uint256 oldLow,
        uint256 oldHigh,
        uint256 newLow,
        uint256 newHigh
    );

    // ============ Errors ============

    error InvalidMultiplierConfig();
    error InvalidRewardBounds();
    error InvalidReputationOracle();
    error DailyEmissionExceeded();
    error AntiWhaleLimitExceeded();
    error CalculationNotFound(bytes32 calculationId);
    error ZeroVerifier();
    error ZeroStake();

    // ============ Constructor ============

    constructor(
        address _reputationOracle,
        address initialAdmin,
        address _governanceController
    ) {
        require(_reputationOracle != address(0), "Invalid oracle address");
        require(initialAdmin != address(0), "Invalid admin address");

        reputationOracle = IReputationOracle(_reputationOracle);

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);

        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);

        categoryMultipliers[ClaimCategory.TRIVIAL] = 1.0e18;
        categoryMultipliers[ClaimCategory.STANDARD] = 1.2e18;
        categoryMultipliers[ClaimCategory.COMPLEX] = 1.5e18;
        categoryMultipliers[ClaimCategory.EXPERT] = 2.0e18;

        _initializeGovernance(_governanceController, initialAdmin, initialAdmin);
    }

    // ============ Core Calculation ============

    function calculateReward(
        address verifier,
        uint256 effectiveStake,
        uint256 activeStake,
        ClaimCategory category
    ) external nonReentrant whenNotPaused returns (uint256 rewardAmount, bytes32 calculationId) {
        if (verifier == address(0)) revert ZeroVerifier();
        if (effectiveStake == 0) revert ZeroStake();

        uint256 reputationScore = _getReputationScore(verifier);

        uint256 reputationMultiplier = _calculateReputationMultiplier(reputationScore);
        uint256 difficultyMultiplier = _getCategoryMultiplier(category);
        uint256 stakeMultiplier = _calculateStakeMultiplier(activeStake);
        uint256 govMultiplier = governanceMultiplier;

        uint256 baseAmount = (effectiveStake * baseRewardRate) / BASE_MULTIPLIER;

        uint256 finalAmount = baseAmount;
        finalAmount = (finalAmount * reputationMultiplier) / BASE_MULTIPLIER;
        finalAmount = (finalAmount * difficultyMultiplier) / BASE_MULTIPLIER;
        finalAmount = (finalAmount * stakeMultiplier) / BASE_MULTIPLIER;
        finalAmount = (finalAmount * govMultiplier) / BASE_MULTIPLIER;

        if (finalAmount < minReward) finalAmount = minReward;
        if (finalAmount > maxReward) finalAmount = maxReward;

        _enforceEmissionCaps(verifier, finalAmount);

        calculationId = keccak256(abi.encode(
            verifier, effectiveStake, activeStake, category, block.timestamp, calculationCount
        ));

        calculations[calculationId] = RewardCalculation({
            verifier: verifier,
            baseAmount: baseAmount,
            reputationMultiplier: reputationMultiplier,
            difficultyMultiplier: difficultyMultiplier,
            stakeMultiplier: stakeMultiplier,
            governanceMultiplier: govMultiplier,
            finalAmount: finalAmount,
            reputationScore: reputationScore,
            activeStake: activeStake,
            category: category,
            timestamp: block.timestamp,
            calculationId: calculationId
        });

        calculationIds.push(calculationId);
        calculationCount++;

        uint256 dayKey = block.timestamp / 1 days;
        dailyEmission[dayKey] += finalAmount;
        dailyVerifierRewards[dayKey][verifier] += finalAmount;

        emit RewardCalculated(verifier, finalAmount, calculationId);
        emit RewardCalculatedV1(
            calculationId,
            verifier,
            finalAmount,
            uint64(block.timestamp),
            EVENT_SCHEMA_VERSION
        );

        return (finalAmount, calculationId);
    }

    function previewReward(
        address verifier,
        uint256 effectiveStake,
        uint256 activeStake,
        ClaimCategory category
    ) external view returns (
        uint256 previewAmount,
        uint256 reputationScore,
        uint256 reputationMultiplier,
        uint256 difficultyMultiplier,
        uint256 stakeMultiplier,
        uint256 govMultiplier
    ) {
        if (verifier == address(0) || effectiveStake == 0) return (0, 0, 0, 0, 0, 0);

        reputationScore = _getReputationScore(verifier);
        reputationMultiplier = _calculateReputationMultiplier(reputationScore);
        difficultyMultiplier = _getCategoryMultiplier(category);
        stakeMultiplier = _calculateStakeMultiplier(activeStake);
        govMultiplier = governanceMultiplier;

        uint256 baseAmount = (effectiveStake * baseRewardRate) / BASE_MULTIPLIER;

        uint256 amount = baseAmount;
        amount = (amount * reputationMultiplier) / BASE_MULTIPLIER;
        amount = (amount * difficultyMultiplier) / BASE_MULTIPLIER;
        amount = (amount * stakeMultiplier) / BASE_MULTIPLIER;
        amount = (amount * govMultiplier) / BASE_MULTIPLIER;

        if (amount < minReward) amount = minReward;
        if (amount > maxReward) amount = maxReward;

        previewAmount = amount;
    }

    function getCalculation(bytes32 calculationId) external view returns (RewardCalculation memory) {
        if (calculations[calculationId].timestamp == 0) revert CalculationNotFound(calculationId);
        return calculations[calculationId];
    }

    function getCalculationCount() external view returns (uint256) {
        return calculationCount;
    }

    function getCalculationsPaginated(
        uint256 offset,
        uint256 limit
    ) external view returns (RewardCalculation[] memory results) {
        uint256 end = offset + limit;
        if (end > calculationCount) end = calculationCount;
        if (offset >= end) return new RewardCalculation[](0);

        results = new RewardCalculation[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            results[i - offset] = calculations[calculationIds[i]];
        }
    }

    function getDailyEmission(uint256 dayKey) external view returns (uint256) {
        return dailyEmission[dayKey];
    }

    function getVerifierDailyRewards(uint256 dayKey, address verifier) external view returns (uint256) {
        return dailyVerifierRewards[dayKey][verifier];
    }

    function getMultiplierConfig() external view returns (MultiplierConfig memory) {
        return MultiplierConfig({
            minReputationMultiplier: minReputationMultiplier,
            maxReputationMultiplier: maxReputationMultiplier,
            minDifficultyMultiplier: minDifficultyMultiplier,
            maxDifficultyMultiplier: maxDifficultyMultiplier,
            minStakeMultiplier: minStakeMultiplier,
            maxStakeMultiplier: maxStakeMultiplier,
            minGovernanceMultiplier: governanceMultiplier,
            maxGovernanceMultiplier: governanceMultiplier
        });
    }

    // ============ Internal Helpers ============

    function _getReputationScore(address user) internal view returns (uint256 score) {
        try reputationOracle.isActive() returns (bool active) {
            if (!active) return defaultReputationScore;
        } catch {
            return defaultReputationScore;
        }

        try reputationOracle.getReputationScore(user) returns (uint256 reputationScore) {
            if (reputationScore == 0) return defaultReputationScore;

            if (reputationScore < minReputationScore) return minReputationScore;
            if (reputationScore > maxReputationScore) return maxReputationScore;
            return reputationScore;
        } catch {
            return defaultReputationScore;
        }
    }

    function _calculateReputationMultiplier(uint256 reputationScore) internal view returns (uint256) {
        if (reputationScore == 0) return minReputationMultiplier;
        if (reputationScore >= maxReputationScore) return maxReputationMultiplier;

        uint256 range = maxReputationScore - minReputationScore;
        if (range == 0) return minReputationMultiplier;

        uint256 multiplierRange = maxReputationMultiplier - minReputationMultiplier;
        uint256 position = reputationScore - minReputationScore;

        return minReputationMultiplier + (position * multiplierRange) / range;
    }

    function _getCategoryMultiplier(ClaimCategory category) internal view returns (uint256) {
        uint256 m = categoryMultipliers[category];
        if (m == 0) return BASE_MULTIPLIER;
        return m;
    }

    function _calculateStakeMultiplier(uint256 activeStake) internal view returns (uint256) {
        if (activeStake <= lowStakeThreshold) return minStakeMultiplier;
        if (activeStake >= highStakeThreshold) return maxStakeMultiplier;

        uint256 range = highStakeThreshold - lowStakeThreshold;
        if (range == 0) return minStakeMultiplier;

        uint256 multiplierRange = maxStakeMultiplier - minStakeMultiplier;
        uint256 position = activeStake - lowStakeThreshold;

        return minStakeMultiplier + (position * multiplierRange) / range;
    }

    function _enforceEmissionCaps(address verifier, uint256 amount) internal view {
        uint256 dayKey = block.timestamp / 1 days;

        if (dailyEmission[dayKey] + amount > dailyEmissionLimit) {
            revert DailyEmissionExceeded();
        }

        if (dailyVerifierRewards[dayKey][verifier] + amount > antiWhaleLimit) {
            revert AntiWhaleLimitExceeded();
        }
    }

    // ============ Admin/Gov Setter Functions ============

    function setBaseRewardRate(uint256 _newRate) external onlyGovernanceOrAdmin {
        require(_newRate > 0, "Rate must be > 0");
        uint256 old = baseRewardRate;
        baseRewardRate = _newRate;
        emit BaseRewardRateUpdated(old, _newRate);
        emit ParameterUpdatedByGovernance(
            keccak256("BASE_REWARD_RATE"), old, _newRate
        );
    }

    function setRewardBounds(uint256 _min, uint256 _max) external onlyGovernanceOrAdmin {
        if (_min > _max) revert InvalidRewardBounds();
        uint256 oldMin = minReward;
        uint256 oldMax = maxReward;
        minReward = _min;
        maxReward = _max;
        emit ParameterUpdatedByGovernance(keccak256("MIN_REWARD_AMOUNT"), oldMin, _min);
        emit ParameterUpdatedByGovernance(keccak256("MAX_REWARD_AMOUNT"), oldMax, _max);
    }

    function setDailyEmissionLimit(uint256 _limit) external onlyGovernanceOrAdmin {
        uint256 old = dailyEmissionLimit;
        dailyEmissionLimit = _limit;
        emit ParameterUpdatedByGovernance(keccak256("DAILY_EMISSION_LIMIT"), old, _limit);
    }

    function setAntiWhaleLimit(uint256 _limit) external onlyGovernanceOrAdmin {
        uint256 old = antiWhaleLimit;
        antiWhaleLimit = _limit;
        emit ParameterUpdatedByGovernance(keccak256("ANTI_WHALE_LIMIT"), old, _limit);
    }

    function setReputationMultiplierBounds(uint256 _min, uint256 _max) external onlyGovernanceOrAdmin {
        if (_min < MIN_MULTIPLIER || _max > MAX_MULTIPLIER || _min > _max) revert InvalidMultiplierConfig();
        uint256 oldMin = minReputationMultiplier;
        uint256 oldMax = maxReputationMultiplier;
        minReputationMultiplier = _min;
        maxReputationMultiplier = _max;
        emit RewardMultiplierUpdated(keccak256("REPUTATION_MULTIPLIER"), oldMin, _min);
        emit RewardMultiplierUpdated(keccak256("REPUTATION_MULTIPLIER"), oldMax, _max);
    }

    function setDifficultyMultiplierBounds(uint256 _min, uint256 _max) external onlyGovernanceOrAdmin {
        if (_min < MIN_MULTIPLIER || _max > MAX_MULTIPLIER || _min > _max) revert InvalidMultiplierConfig();
        uint256 oldMin = minDifficultyMultiplier;
        uint256 oldMax = maxDifficultyMultiplier;
        minDifficultyMultiplier = _min;
        maxDifficultyMultiplier = _max;
        emit RewardMultiplierUpdated(keccak256("DIFFICULTY_MULTIPLIER"), oldMin, _min);
        emit RewardMultiplierUpdated(keccak256("DIFFICULTY_MULTIPLIER"), oldMax, _max);
    }

    function setStakeMultiplierBounds(uint256 _min, uint256 _max) external onlyGovernanceOrAdmin {
        if (_min < MIN_MULTIPLIER || _max > MAX_MULTIPLIER || _min > _max) revert InvalidMultiplierConfig();
        uint256 oldMin = minStakeMultiplier;
        uint256 oldMax = maxStakeMultiplier;
        minStakeMultiplier = _min;
        maxStakeMultiplier = _max;
        emit RewardMultiplierUpdated(keccak256("STAKE_MULTIPLIER"), oldMin, _min);
        emit RewardMultiplierUpdated(keccak256("STAKE_MULTIPLIER"), oldMax, _max);
    }

    function setGovernanceMultiplier(uint256 _multiplier) external onlyGovernanceOrAdmin {
        if (_multiplier < MIN_MULTIPLIER || _multiplier > MAX_MULTIPLIER) revert InvalidMultiplierConfig();
        uint256 old = governanceMultiplier;
        governanceMultiplier = _multiplier;
        emit RewardMultiplierUpdated(keccak256("GOVERNANCE_MULTIPLIER"), old, _multiplier);
        emit ParameterUpdatedByGovernance(keccak256("GOVERNANCE_MULTIPLIER"), old, _multiplier);
    }

    function setCategoryMultiplier(ClaimCategory category, uint256 multiplier) external onlyGovernanceOrAdmin {
        if (multiplier < MIN_MULTIPLIER || multiplier > MAX_MULTIPLIER) revert InvalidMultiplierConfig();
        uint256 old = categoryMultipliers[category];
        categoryMultipliers[category] = multiplier;
        emit CategoryMultiplierUpdated(category, old, multiplier);
    }

    function setReputationBounds(uint256 _min, uint256 _max) external onlyGovernanceOrAdmin {
        if (_min == 0 || _min >= _max) revert InvalidMultiplierConfig();
        uint256 oldMin = minReputationScore;
        uint256 oldMax = maxReputationScore;
        minReputationScore = _min;
        maxReputationScore = _max;
        emit ReputationBoundsUpdated(oldMin, oldMax, _min, _max);
    }

    function setDefaultReputationScore(uint256 _score) external onlyGovernanceOrAdmin {
        require(_score > 0, "Invalid score");
        uint256 old = defaultReputationScore;
        defaultReputationScore = _score;
        emit ParameterUpdatedByGovernance(keccak256("DEFAULT_REPUTATION_SCORE"), old, _score);
    }

    function setStakeThresholds(uint256 _low, uint256 _high) external onlyGovernanceOrAdmin {
        if (_low >= _high) revert InvalidMultiplierConfig();
        uint256 oldLow = lowStakeThreshold;
        uint256 oldHigh = highStakeThreshold;
        lowStakeThreshold = _low;
        highStakeThreshold = _high;
        emit StakeThresholdsUpdated(oldLow, oldHigh, _low, _high);
    }

    function setReputationOracle(address _newOracle) external onlyRole(ADMIN_ROLE) {
        if (_newOracle == address(0)) revert InvalidReputationOracle();
        address oldOracle = address(reputationOracle);
        reputationOracle = IReputationOracle(_newOracle);
        emit ReputationOracleUpdated(oldOracle, _newOracle);
    }

    // ============ Pause ============

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}