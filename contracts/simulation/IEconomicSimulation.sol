// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IEconomicSimulation
 * @notice Interface for the Protocol Economic Simulation & Stress Testing Framework (SC-032)
 * @dev The simulation framework models protocol behaviour under a wide range of
 *      scenarios without affecting live protocol state.
 *
 *      Simulation results are advisory only and must never directly execute
 *      protocol changes. The framework is intended for governance decision-making,
 *      audit validation, and continuous economic verification.
 */
interface IEconomicSimulation {

    // ============ Types ============

    /// @brief Predefined simulation scenarios
    enum Scenario {
        NORMAL_GROWTH,
        HIGH_GROWTH,
        LOW_PARTICIPATION,
        ADVERSARIAL_BEHAVIOUR,
        TREASURY_STRESS,
        GOVERNANCE_CHANGE
    }

    /// @brief Economic metrics computed by a simulation run
    struct EconomicMetrics {
        uint256 treasurySolvency;       // Remaining treasury balance (tokens)
        uint256 totalRewardEmissions;   // Total rewards distributed
        uint256 protocolRevenue;        // Revenue collected (fees, slashing)
        uint256 verifierProfitability;  // Avg profit per verifier (tokens)
        uint256 averageSettlementCost;  // Avg cost to settle a claim (tokens)
        uint256 inflationRate;          // Effective inflation rate (basis points)
        uint256 reserveUtilisation;     // Treasury reserve utilisation (basis points)
        uint256 sustainabilityIndex;    // Composite sustainability score (0-10000)
    }

    /// @brief Governance parameter override set for simulation
    struct GovernanceParams {
        uint256 slashPercent;
        uint256 rewardPercent;
        uint256 minStakeAmount;
        uint256 settlementThresholdPercent;
        uint256 verificationWindowDuration;
        uint256 rewardIncrement;
        uint256 penaltyAmount;
        uint256 maliciousMultiplier;
    }

    /// @brief Simulation configuration
    struct SimulationConfig {
        Scenario scenario;
        uint256 durationDays;           // How many days to simulate
        uint256 initialTreasury;        // Starting treasury balance
        uint256 initialVerifiers;       // Starting number of verifiers
        uint256 initialStakers;         // Starting number of stakers
        uint256 dailyClaimVolume;       // Average claims per day
        GovernanceParams govParams;     // Governance parameters to test
    }

    /// @brief Structured simulation report
    struct SimulationReport {
        bytes32 simulationId;
        Scenario scenario;
        SimulationConfig config;
        EconomicMetrics metrics;
        string[] warnings;              // Generated warnings (machine-readable)
        string[] recommendations;       // Recommendations
        uint256 timestamp;
        bool valid;                     // Whether the simulation was valid
    }

    // ============ Events ============

    /// @notice Emitted when a simulation is executed
    event SimulationExecuted(
        bytes32 indexed simulationId,
        Scenario    indexed scenario
    );

    /// @notice Emitted when an economic threshold is exceeded
    event EconomicThresholdExceeded(
        bytes32 indexed metric,
        uint256        value
    );

    /// @notice Emitted when a simulation completes
    event SimulationCompleted(bytes32 indexed simulationId);

    // ============ Core Functions ============

    /**
     * @notice Execute a deterministic economic simulation
     * @param config The simulation configuration
     * @return report The structured simulation report
     */
    function simulate(SimulationConfig calldata config) external returns (SimulationReport memory report);

    // ============ View Functions ============

    /**
     * @notice Get all available scenarios
     * @return scenarios Array of available scenario enum values
     */
    function getAvailableScenarios() external view returns (Scenario[] memory scenarios);

    /**
     * @notice Get a human-readable name for a scenario
     * @param scenario The scenario enum value
     * @return name Human-readable name string
     */
    function getScenarioName(Scenario scenario) external view returns (string memory name);

    /**
     * @notice Get a human-readable description for a scenario
     * @param scenario The scenario enum value
     * @return description Human-readable description
     */
    function getScenarioDescription(Scenario scenario) external view returns (string memory description);

    /**
     * @notice Get a simulation report by ID
     * @param simulationId The simulation ID
     * @return report The simulation report
     */
    function getSimulation(bytes32 simulationId) external view returns (SimulationReport memory report);

    /**
     * @notice Get the total number of simulations executed
     */
    function getSimulationCount() external view returns (uint256);

    /**
     * @notice Get a paginated list of simulation IDs
     * @param offset Start index
     * @param limit  Max entries to return
     * @return ids Array of simulation IDs
     */
    function getSimulationsPaginated(uint256 offset, uint256 limit) external view returns (bytes32[] memory ids);

    /**
     * @notice Preview what metrics would result from a given config without storing
     * @param config The simulation configuration
     * @return metrics The computed economic metrics
     */
    function previewSimulation(SimulationConfig calldata config) external view returns (EconomicMetrics memory metrics);

    /**
     * @notice Validate governance parameters and return warnings
     * @param params The governance parameters to validate
     * @return warnings Array of warning strings (empty if safe)
     * @return safe True if all checks pass
     */
    function validateGovernanceParams(GovernanceParams calldata params) external view returns (string[] memory warnings, bool safe);

    // ============ Admin ============

    /**
     * @notice Set a warning threshold for a metric
     * @param metricId keccak256 identifier of the metric
     * @param threshold Value above/below which a warning is generated
     */
    function setEconomicThreshold(bytes32 metricId, uint256 threshold) external;
}
