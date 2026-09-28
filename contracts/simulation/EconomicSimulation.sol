// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IEconomicSimulation.sol";

contract EconomicSimulation is IEconomicSimulation, AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SIMULATOR_ROLE = keccak256("SIMULATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_SUSTAINABLE_INFLATION_BPS = 500;
    uint256 public constant MIN_SUSTAINABLE_TREASURY_BPS = 2000;
    uint256 public constant MIN_VERIFIER_PROFITABILITY = 1e17;
    uint256 public constant MAX_RESERVE_UTILISATION_BPS = 8000;

    uint256 private _simulationCounter;
    mapping(bytes32 => SimulationReport) private _reports;
    bytes32[] private _simulationIds;
    mapping(bytes32 => uint256) public economicThresholds;

    event ThresholdUpdated(bytes32 indexed metricId, uint256 oldValue, uint256 newValue);
    event SimulationLimitExceeded(bytes32 indexed simulationId, string reason);

    error SimulationNotFound(bytes32 simulationId);
    error InvalidConfig();
    error ZeroAddress();
    error InvalidDuration();

    constructor(address initialAdmin) {
        if (initialAdmin == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
        _grantRole(SIMULATOR_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);

        _setRoleAdmin(SIMULATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);

        economicThresholds[keccak256("INFLATION_RATE")] = MAX_SUSTAINABLE_INFLATION_BPS;
        economicThresholds[keccak256("TREASURY_SOLVENCY")] = 1e22;
        economicThresholds[keccak256("RESERVE_UTILISATION")] = MAX_RESERVE_UTILISATION_BPS;
        economicThresholds[keccak256("VERIFIER_PROFITABILITY")] = MIN_VERIFIER_PROFITABILITY;
    }

    function simulate(SimulationConfig calldata config)
        external
        nonReentrant
        whenNotPaused
        onlyRole(SIMULATOR_ROLE)
        returns (SimulationReport memory report)
    {
        if (config.durationDays == 0) revert InvalidDuration();

        bytes32 simulationId = _generateSimulationId(config);
        EconomicMetrics memory metrics = _runSimulation(config);
        (string[] memory warnings, string[] memory recommendations) = _analyzeResults(config, metrics);

        report = SimulationReport({
            simulationId: simulationId,
            scenario: config.scenario,
            config: config,
            metrics: metrics,
            warnings: warnings,
            recommendations: recommendations,
            timestamp: block.timestamp,
            valid: warnings.length == 0 || _isConfigValid(config)
        });

        _reports[simulationId] = report;
        _simulationIds.push(simulationId);
        _simulationCounter++;

        emit SimulationExecuted(simulationId, config.scenario);
        emit SimulationCompleted(simulationId);

        if (metrics.inflationRate > economicThresholds[keccak256("INFLATION_RATE")]) {
            emit EconomicThresholdExceeded(keccak256("INFLATION_RATE"), metrics.inflationRate);
        }
        if (metrics.reserveUtilisation > economicThresholds[keccak256("RESERVE_UTILISATION")]) {
            emit EconomicThresholdExceeded(keccak256("RESERVE_UTILISATION"), metrics.reserveUtilisation);
        }

        return report;
    }

    function previewSimulation(SimulationConfig calldata config)
        external
        view
        returns (EconomicMetrics memory metrics)
    {
        return _runSimulation(config);
    }

    function getAvailableScenarios() external pure returns (Scenario[] memory scenarios) {
        scenarios = new Scenario[](6);
        scenarios[0] = Scenario.NORMAL_GROWTH;
        scenarios[1] = Scenario.HIGH_GROWTH;
        scenarios[2] = Scenario.LOW_PARTICIPATION;
        scenarios[3] = Scenario.ADVERSARIAL_BEHAVIOUR;
        scenarios[4] = Scenario.TREASURY_STRESS;
        scenarios[5] = Scenario.GOVERNANCE_CHANGE;
    }

    function getScenarioName(Scenario scenario) external pure returns (string memory name) {
        if (scenario == Scenario.NORMAL_GROWTH) return "Normal Growth";
        if (scenario == Scenario.HIGH_GROWTH) return "High Growth";
        if (scenario == Scenario.LOW_PARTICIPATION) return "Low Participation";
        if (scenario == Scenario.ADVERSARIAL_BEHAVIOUR) return "Adversarial Behaviour";
        if (scenario == Scenario.TREASURY_STRESS) return "Treasury Stress";
        if (scenario == Scenario.GOVERNANCE_CHANGE) return "Governance Change";
        return "Unknown";
    }

    function getScenarioDescription(Scenario scenario) external pure returns (string memory description) {
        if (scenario == Scenario.NORMAL_GROWTH) {
            return "Steady claim creation, stable verifier participation, sustainable treasury growth.";
        }
        if (scenario == Scenario.HIGH_GROWTH) {
            return "Rapid user onboarding, increased claim volume, and higher reward distribution.";
        }
        if (scenario == Scenario.LOW_PARTICIPATION) {
            return "Declining verifier activity, reduced staking, slower settlements.";
        }
        if (scenario == Scenario.ADVERSARIAL_BEHAVIOUR) {
            return "Sybil attacks, spam claims, reward farming, and coordinated collusion.";
        }
        if (scenario == Scenario.TREASURY_STRESS) {
            return "Reduced revenue, increased payouts, and emergency expenditures.";
        }
        if (scenario == Scenario.GOVERNANCE_CHANGE) {
            return "Modified reward multipliers, staking requirement updates, fee adjustments, and treasury allocation changes.";
        }
        return "";
    }

    function getSimulation(bytes32 simulationId) external view returns (SimulationReport memory report) {
        if (_reports[simulationId].timestamp == 0) revert SimulationNotFound(simulationId);
        return _reports[simulationId];
    }

    function getSimulationCount() external view returns (uint256) {
        return _simulationCounter;
    }

    function getSimulationsPaginated(uint256 offset, uint256 limit) external view returns (bytes32[] memory ids) {
        uint256 total = _simulationIds.length;
        if (offset >= total) return new bytes32[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        ids = new bytes32[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            ids[i - offset] = _simulationIds[i];
        }
    }

    function validateGovernanceParams(GovernanceParams calldata params)
        external
        view
        returns (string[] memory warnings, bool safe)
    {
        uint256 count = 0;

        if (params.slashPercent == 0 || params.slashPercent > 50) count++;
        if (params.rewardPercent == 0 || params.rewardPercent > 100) count++;
        if (params.rewardPercent + params.slashPercent > 100) count++;
        if (params.minStakeAmount == 0) count++;
        if (params.settlementThresholdPercent == 0 || params.settlementThresholdPercent > 100) count++;
        if (params.rewardIncrement == 0) count++;
        if (params.penaltyAmount == 0) count++;
        if (params.maliciousMultiplier == 0) count++;
        if (params.verificationWindowDuration < 1 hours) count++;
        if (params.verificationWindowDuration > 30 days) count++;

        warnings = new string[](count);
        uint256 i = 0;

        if (params.slashPercent == 0 || params.slashPercent > 50) warnings[i++] = "Slash percent must be between 1 and 50.";
        if (params.rewardPercent == 0 || params.rewardPercent > 100) warnings[i++] = "Reward percent must be between 1 and 100.";
        if (params.rewardPercent + params.slashPercent > 100) warnings[i++] = "Reward percent + slash percent exceeds 100%.";
        if (params.minStakeAmount == 0) warnings[i++] = "Min stake amount must be greater than 0.";
        if (params.settlementThresholdPercent == 0 || params.settlementThresholdPercent > 100) warnings[i++] = "Settlement threshold must be between 1 and 100.";
        if (params.rewardIncrement == 0) warnings[i++] = "Reward increment must be greater than 0.";
        if (params.penaltyAmount == 0) warnings[i++] = "Penalty amount must be greater than 0.";
        if (params.maliciousMultiplier == 0) warnings[i++] = "Malicious multiplier must be greater than 0.";
        if (params.verificationWindowDuration < 1 hours) warnings[i++] = "Verification window must be at least 1 hour.";
        if (params.verificationWindowDuration > 30 days) warnings[i++] = "Verification window must not exceed 30 days.";

        safe = (warnings.length == 0);
    }

    function setEconomicThreshold(bytes32 metricId, uint256 threshold) external onlyRole(ADMIN_ROLE) {
        uint256 old = economicThresholds[metricId];
        economicThresholds[metricId] = threshold;
        emit ThresholdUpdated(metricId, old, threshold);
    }

    function getSimulationReport(bytes32 simulationId) external view returns (SimulationReport memory) {
        SimulationReport memory report = _reports[simulationId];
        if (report.simulationId == bytes32(0)) revert SimulationNotFound(simulationId);
        return report;
    }

    function getSimulationId(uint256 index) external view returns (bytes32) {
        if (index >= _simulationIds.length) revert SimulationNotFound(bytes32(0));
        return _simulationIds[index];
    }

    function updateEconomicThreshold(bytes32 metricId, uint256 newValue) external onlyRole(ADMIN_ROLE) {
        uint256 oldValue = economicThresholds[metricId];
        economicThresholds[metricId] = newValue;
        emit ThresholdUpdated(metricId, oldValue, newValue);
    }

    function grantRole(bytes32 role, address account) public override onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public override onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) public override {
        if (account != msg.sender) revert AccessControlUnauthorizedAccount(account, getRoleAdmin(role));
        _revokeRole(role, account);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _runSimulation(SimulationConfig memory config)
        internal
        pure
        returns (EconomicMetrics memory metrics)
    {
        (uint256 verifierBonus, uint256 claimMultiplier, uint256 revenueMultiplier) = _getScenarioModifiers(config.scenario);

        uint256 treasury = config.initialTreasury;
        uint256 verifiers = config.initialVerifiers;
        uint256 stakers = config.initialStakers;
        uint256 dailyClaims = config.dailyClaimVolume * claimMultiplier / BPS;
        uint256 durationDays = config.durationDays;
        GovernanceParams memory gp = config.govParams;

        uint256 totalRewards;
        uint256 totalRevenue;
        uint256 totalSettlements;

        for (uint256 day = 0; day < durationDays; day++) {
            uint256 activeVerifiers = verifiers * _getParticipationRate(config.scenario, day) / BPS;
            uint256 settledToday = dailyClaims;
            totalSettlements += settledToday;

            uint256 totalStaked = stakers * gp.minStakeAmount * (1e18 + verifierBonus) / 1e18;
            uint256 dailyReward = _calculateDailyRewards(activeVerifiers, totalStaked, gp.rewardPercent, gp.slashPercent, settledToday);
            uint256 dailyRevenue = _calculateDailyRevenue(settledToday, totalStaked, gp.slashPercent, revenueMultiplier);

            totalRewards += dailyReward;
            totalRevenue += dailyRevenue;
            treasury = treasury + dailyRevenue - dailyReward;

            if (treasury > type(uint256).max / 2) {
                treasury = 0;
            }

            if (treasury > config.initialTreasury / 2) {
                verifiers = verifiers + (verifiers * 5 / BPS);
                stakers = stakers + (stakers * 3 / BPS);
            }
        }

        metrics.treasurySolvency = treasury;
        metrics.totalRewardEmissions = totalRewards;
        metrics.protocolRevenue = totalRevenue;

        uint256 avgVerifiers = (config.initialVerifiers + verifiers) / 2;
        metrics.verifierProfitability = avgVerifiers > 0 ? totalRewards / avgVerifiers : 0;
        metrics.averageSettlementCost = totalSettlements > 0 ? totalRewards / totalSettlements : 0;

        uint256 annualisedRewards = totalRewards * 365 days / (durationDays * 1 days);
        uint256 economicBase = config.initialTreasury > 0 ? config.initialTreasury : 1e18;
        metrics.inflationRate = (annualisedRewards * BPS) / economicBase;
        metrics.reserveUtilisation = config.initialTreasury > 0 ? ((config.initialTreasury - treasury) * BPS) / config.initialTreasury : 0;
        metrics.sustainabilityIndex = _calculateSustainabilityIndex(metrics);
    }

    function _getScenarioModifiers(Scenario scenario)
        internal
        pure
        returns (uint256 verifierBonus, uint256 claimMultiplier, uint256 revenueMultiplier)
    {
        if (scenario == Scenario.NORMAL_GROWTH) return (0, BPS, BPS);
        if (scenario == Scenario.HIGH_GROWTH) return (0, 2 * BPS, BPS);
        if (scenario == Scenario.LOW_PARTICIPATION) return (0, BPS / 3, BPS / 2);
        if (scenario == Scenario.ADVERSARIAL_BEHAVIOUR) return (0, BPS, BPS / 2);
        if (scenario == Scenario.TREASURY_STRESS) return (0, BPS / 2, BPS / 4);
        if (scenario == Scenario.GOVERNANCE_CHANGE) return (0, 3 * BPS / 2, BPS);
        revert InvalidConfig();
    }

    function _getParticipationRate(Scenario scenario, uint256 day) internal pure returns (uint256) {
        if (scenario == Scenario.LOW_PARTICIPATION) return 1000;
        if (scenario == Scenario.ADVERSARIAL_BEHAVIOUR) return day % 7 < 3 ? 4000 : 7000;
        if (scenario == Scenario.TREASURY_STRESS) return 6000;
        if (scenario == Scenario.GOVERNANCE_CHANGE) return 8000 + (day % 800);
        return 10000;
    }

    function _calculateDailyRewards(
        uint256 activeVerifiers,
        uint256 totalStaked,
        uint256 rewardPercent,
        uint256 slashPercent,
        uint256 settledToday
    ) internal pure returns (uint256) {
        if (activeVerifiers == 0 || totalStaked == 0) return 0;
        uint256 baseReward = totalStaked * rewardPercent / BPS;
        uint256 slashAmount = settledToday * slashPercent / BPS;
        return baseReward - slashAmount;
    }

    function _calculateDailyRevenue(
        uint256 settledToday,
        uint256 totalStaked,
        uint256 slashPercent,
        uint256 revenueMultiplier
    ) internal pure returns (uint256) {
        if (totalStaked == 0) return 0;
        uint256 slashAmount = settledToday * slashPercent / BPS;
        return slashAmount * revenueMultiplier / BPS;
    }

    function _calculateSustainabilityIndex(EconomicMetrics memory metrics) internal pure returns (uint256) {
        uint256 score = 10000;

        if (metrics.inflationRate > MAX_SUSTAINABLE_INFLATION_BPS) score -= 1000;
        if (metrics.treasurySolvency < MIN_SUSTAINABLE_TREASURY_BPS) score -= 1000;
        if (metrics.verifierProfitability < MIN_VERIFIER_PROFITABILITY) score -= 1000;
        if (metrics.reserveUtilisation > MAX_RESERVE_UTILISATION_BPS) score -= 1000;

        return score;
    }

    function _generateSimulationId(SimulationConfig memory config) internal view returns (bytes32) {
        return keccak256(abi.encode(config.scenario, config.durationDays, config.initialTreasury, config.initialVerifiers, config.initialStakers, config.dailyClaimVolume, config.govParams, block.timestamp, _simulationCounter));
    }

    function _isConfigValid(SimulationConfig calldata config) internal pure returns (bool) {
        if (config.initialTreasury == 0) return false;
        if (config.initialVerifiers == 0) return false;
        if (config.initialStakers == 0) return false;
        if (config.durationDays == 0) return false;
        if (config.dailyClaimVolume == 0) return false;
        if (config.govParams.minStakeAmount == 0) return false;
        if (config.govParams.rewardPercent > BPS) return false;
        if (config.govParams.slashPercent > BPS) return false;
        return true;
    }

    function _analyzeResults(SimulationConfig calldata config, EconomicMetrics memory metrics)
        internal
        pure
        returns (string[] memory warnings, string[] memory recommendations)
    {
        uint256 warningCount = 0;
        uint256 recommendationCount = 0;

        if (metrics.inflationRate > MAX_SUSTAINABLE_INFLATION_BPS) {
            warningCount++; recommendationCount++;
        }
        if (metrics.treasurySolvency < MIN_SUSTAINABLE_TREASURY_BPS) {
            warningCount++; recommendationCount++;
        }
        if (metrics.verifierProfitability < MIN_VERIFIER_PROFITABILITY) {
            warningCount++; recommendationCount++;
        }
        if (metrics.reserveUtilisation > MAX_RESERVE_UTILISATION_BPS) {
            warningCount++; recommendationCount++;
        }

        warnings = new string[](warningCount);
        recommendations = new string[](recommendationCount);

        uint256 wIdx = 0;
        uint256 rIdx = 0;

        if (metrics.inflationRate > MAX_SUSTAINABLE_INFLATION_BPS) {
            warnings[wIdx] = "Inflation rate exceeds sustainable limit";
            recommendations[rIdx] = "Reduce reward emissions or increase treasury";
            wIdx++; rIdx++;
        }
        if (metrics.treasurySolvency < MIN_SUSTAINABLE_TREASURY_BPS) {
            warnings[wIdx] = "Treasury solvency below minimum threshold";
            recommendations[rIdx] = "Increase treasury or reduce reward emissions";
            wIdx++; rIdx++;
        }
        if (metrics.verifierProfitability < MIN_VERIFIER_PROFITABILITY) {
            warnings[wIdx] = "Verifier profitability below minimum threshold";
            recommendations[rIdx] = "Increase rewards or reduce costs";
            wIdx++; rIdx++;
        }
        if (metrics.reserveUtilisation > MAX_RESERVE_UTILISATION_BPS) {
            warnings[wIdx] = "Reserve utilisation exceeds maximum threshold";
            recommendations[rIdx] = "Reduce reserve utilisation or increase reserves";
            wIdx++; rIdx++;
        }
    }

    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
