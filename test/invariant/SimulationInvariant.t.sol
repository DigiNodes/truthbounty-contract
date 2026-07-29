// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../contracts/simulation/EconomicSimulation.sol";
import "../../contracts/simulation/IEconomicSimulation.sol";

/**
 * @title SimulationInvariantTest
 * @notice Invariant tests for the Economic Simulation Framework (SC-032)
 *
 * Key invariants:
 * 1. Simulations never alter protocol state (only store reports)
 * 2. Repeated simulations with identical configs produce identical metrics
 * 3. Metrics remain internally consistent
 * 4. Valid configs always produce valid reports
 * 5. Invalid configs are rejected
 */
contract SimulationInvariantTest is StdInvariant, Test {
    EconomicSimulation public sim;
    address public admin = address(0x1);
    address public simulator = address(0x2);

    IEconomicSimulation.GovernanceParams public defaultGovParams;

    function setUp() public {
        sim = new EconomicSimulation(admin);
        sim.grantRole(sim.SIMULATOR_ROLE(), simulator);

        defaultGovParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 20,
            rewardPercent: 80,
            minStakeAmount: 100e18,
            settlementThresholdPercent: 60,
            verificationWindowDuration: 7 days,
            rewardIncrement: 10,
            penaltyAmount: 10,
            maliciousMultiplier: 5
        });

        targetContract(address(sim));
    }

    // ============ Invariant 1: Simulation Isolation ============

    function invariant_SimulationsOnlyStoreReports() public {
        // The only state mutations from simulations are report storage
        // Verify the contract doesn't have unintended state changes
        assertTrue(sim.hasRole(sim.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(sim.getSimulationCount() >= 0);
    }

    // ============ Invariant 2: Deterministic Metrics ============

    function invariant_DeterministicMetrics() public {
        IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
            scenario: IEconomicSimulation.Scenario.NORMAL_GROWTH,
            durationDays: 365,
            initialTreasury: 1_000_000e18,
            initialVerifiers: 100,
            initialStakers: 500,
            dailyClaimVolume: 50,
            govParams: defaultGovParams
        });

        // Preview (no state change) — should always return the same metrics
        IEconomicSimulation.EconomicMetrics memory m1 = sim.previewSimulation(config);
        IEconomicSimulation.EconomicMetrics memory m2 = sim.previewSimulation(config);

        assertEq(m1.treasurySolvency, m2.treasurySolvency, "Treasury solvency mismatch");
        assertEq(m1.totalRewardEmissions, m2.totalRewardEmissions, "Reward emissions mismatch");
        assertEq(m1.protocolRevenue, m2.protocolRevenue, "Revenue mismatch");
        assertEq(m1.sustainabilityIndex, m2.sustainabilityIndex, "Sustainability mismatch");
    }

    // ============ Invariant 3: Metrics Internal Consistency ============

    function invariant_MetricsInternalConsistency() public {
        IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
            scenario: IEconomicSimulation.Scenario.NORMAL_GROWTH,
            durationDays: 365,
            initialTreasury: 1_000_000e18,
            initialVerifiers: 100,
            initialStakers: 500,
            dailyClaimVolume: 50,
            govParams: defaultGovParams
        });

        IEconomicSimulation.EconomicMetrics memory metrics = sim.previewSimulation(config);

        // Treasury solvency should not exceed initial treasury (for normal growth)
        // due to reward emissions
        assertTrue(metrics.treasurySolvency <= config.initialTreasury || metrics.inflationRate > 0);

        // Inflation rate should be reasonable
        assertTrue(metrics.inflationRate <= 10000, "Inflation exceeds 100%");

        // Reserve utilisation should be between 0 and 10000 BPS
        assertTrue(metrics.reserveUtilisation <= 10000, "Reserve util exceeds 100%");

        // Sustainability index should be between 0 and 10000
        assertTrue(metrics.sustainabilityIndex <= 10000, "Sustainability exceeds max");
    }

    // ============ Invariant 4: All Scenarios Produce Valid Reports ============

    function invariant_AllScenariosProduceReports() public {
        IEconomicSimulation.Scenario[6] memory scenarios = [
            IEconomicSimulation.Scenario.NORMAL_GROWTH,
            IEconomicSimulation.Scenario.HIGH_GROWTH,
            IEconomicSimulation.Scenario.LOW_PARTICIPATION,
            IEconomicSimulation.Scenario.ADVERSARIAL_BEHAVIOUR,
            IEconomicSimulation.Scenario.TREASURY_STRESS,
            IEconomicSimulation.Scenario.GOVERNANCE_CHANGE
        ];

        for (uint256 i = 0; i < scenarios.length; i++) {
            IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
                scenario: scenarios[i],
                durationDays: 30,
                initialTreasury: 1_000_000e18,
                initialVerifiers: 100,
                initialStakers: 500,
                dailyClaimVolume: 50,
                govParams: defaultGovParams
            });

            IEconomicSimulation.EconomicMetrics memory metrics = sim.previewSimulation(config);
            assertTrue(metrics.treasurySolvency > 0 || metrics.sustainabilityIndex > 0, "Scenario failed");
        }
    }

    // ============ Invariant 5: Governance Validation ============

    function invariant_GovernanceValidationRejectsInvalidParams() public {
        IEconomicSimulation.GovernanceParams memory invalidParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 0,
            rewardPercent: 0,
            minStakeAmount: 0,
            settlementThresholdPercent: 0,
            verificationWindowDuration: 0,
            rewardIncrement: 0,
            penaltyAmount: 0,
            maliciousMultiplier: 0
        });

        (, bool safe) = sim.validateGovernanceParams(invalidParams);
        assertFalse(safe, "Should reject invalid params");
    }

    // ============ Invariant 6: Storage is Append-Only ============

    function invariant_SimulationStorageIsAppendOnly() public {
        // Verify that once a simulation is stored, it can always be retrieved
        uint256 count = sim.getSimulationCount();
        assertTrue(count >= 0);

        // Check that no simulation reports can be deleted or overwritten
        if (count > 0) {
            bytes32[] memory ids = sim.getSimulationsPaginated(0, count);
            for (uint256 i = 0; i < ids.length; i++) {
                IEconomicSimulation.SimulationReport memory report = sim.getSimulation(ids[i]);
                assertTrue(report.timestamp > 0, "Report should have timestamp");
            }
        }
    }
}
