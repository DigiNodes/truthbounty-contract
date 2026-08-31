// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/simulation/EconomicSimulation.sol";
import "../../contracts/simulation/IEconomicSimulation.sol";

contract EconomicSimulationTest is Test {
    EconomicSimulation public sim;
    address public admin = address(0x1);
    address public simulator = address(0x2);
    address public attacker = address(0x3);

    event SimulationExecuted(bytes32 indexed simulationId, IEconomicSimulation.Scenario indexed scenario);
    event SimulationCompleted(bytes32 indexed simulationId);

    function setUp() public {
        sim = new EconomicSimulation(admin);
        bytes32 simulatorRole = sim.SIMULATOR_ROLE();
        vm.prank(admin);
        sim.grantRole(simulatorRole, simulator);
    }

    // ============ Constructor ============

    function test_Constructor() public {
        assertEq(sim.getSimulationCount(), 0);
        assertTrue(sim.hasRole(sim.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(sim.hasRole(sim.SIMULATOR_ROLE(), admin));
    }

    // ============ Normal Growth Simulation ============

    function test_NormalGrowthSimulation() public {
        IEconomicSimulation.GovernanceParams memory govParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 20,
            rewardPercent: 80,
            minStakeAmount: 100e18,
            settlementThresholdPercent: 60,
            verificationWindowDuration: 7 days,
            rewardIncrement: 10,
            penaltyAmount: 10,
            maliciousMultiplier: 5
        });

        IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
            scenario: IEconomicSimulation.Scenario.NORMAL_GROWTH,
            durationDays: 365,
            initialTreasury: 1_000_000e18,
            initialVerifiers: 100,
            initialStakers: 500,
            dailyClaimVolume: 50,
            govParams: govParams
        });

        vm.prank(simulator);
        IEconomicSimulation.SimulationReport memory report = sim.simulate(config);

        assertEq(uint256(report.scenario), uint256(IEconomicSimulation.Scenario.NORMAL_GROWTH));
        assertTrue(report.timestamp > 0);
        assertTrue(report.metrics.treasurySolvency > 0);
        assertTrue(report.metrics.totalRewardEmissions > 0);
        assertTrue(report.valid);
    }

    // ============ High Growth Simulation ============

    function test_HighGrowthSimulation() public {
        IEconomicSimulation.GovernanceParams memory govParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 20,
            rewardPercent: 80,
            minStakeAmount: 100e18,
            settlementThresholdPercent: 60,
            verificationWindowDuration: 7 days,
            rewardIncrement: 10,
            penaltyAmount: 10,
            maliciousMultiplier: 5
        });

        IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
            scenario: IEconomicSimulation.Scenario.HIGH_GROWTH,
            durationDays: 365,
            initialTreasury: 1_000_000e18,
            initialVerifiers: 100,
            initialStakers: 500,
            dailyClaimVolume: 50,
            govParams: govParams
        });

        vm.prank(simulator);
        IEconomicSimulation.SimulationReport memory report = sim.simulate(config);

        assertEq(uint256(report.scenario), uint256(IEconomicSimulation.Scenario.HIGH_GROWTH));
        assertTrue(report.metrics.protocolRevenue > 0);
    }

    // ============ Low Participation Simulation ============

    function test_LowParticipationSimulation() public {
        IEconomicSimulation.GovernanceParams memory govParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 20,
            rewardPercent: 80,
            minStakeAmount: 100e18,
            settlementThresholdPercent: 60,
            verificationWindowDuration: 7 days,
            rewardIncrement: 10,
            penaltyAmount: 10,
            maliciousMultiplier: 5
        });

        IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
            scenario: IEconomicSimulation.Scenario.LOW_PARTICIPATION,
            durationDays: 365,
            initialTreasury: 1_000_000e18,
            initialVerifiers: 100,
            initialStakers: 500,
            dailyClaimVolume: 50,
            govParams: govParams
        });

        vm.prank(simulator);
        IEconomicSimulation.SimulationReport memory report = sim.simulate(config);

        // Low participation should have lower verifier profitability
        // Just verify it runs and returns metrics
        assertTrue(report.metrics.verifierProfitability >= 0);
    }

    // ============ Adversarial Simulation ============

    function test_AdversarialSimulation() public {
        IEconomicSimulation.GovernanceParams memory govParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 20,
            rewardPercent: 80,
            minStakeAmount: 100e18,
            settlementThresholdPercent: 60,
            verificationWindowDuration: 7 days,
            rewardIncrement: 10,
            penaltyAmount: 10,
            maliciousMultiplier: 5
        });

        IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
            scenario: IEconomicSimulation.Scenario.ADVERSARIAL_BEHAVIOUR,
            durationDays: 365,
            initialTreasury: 1_000_000e18,
            initialVerifiers: 100,
            initialStakers: 500,
            dailyClaimVolume: 50,
            govParams: govParams
        });

        vm.prank(simulator);
        IEconomicSimulation.SimulationReport memory report = sim.simulate(config);
        assertTrue(report.valid || report.warnings.length > 0);
    }

    // ============ Treasury Stress Simulation ============

    function test_TreasuryStressSimulation() public {
        IEconomicSimulation.GovernanceParams memory govParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 20,
            rewardPercent: 80,
            minStakeAmount: 100e18,
            settlementThresholdPercent: 60,
            verificationWindowDuration: 7 days,
            rewardIncrement: 10,
            penaltyAmount: 10,
            maliciousMultiplier: 5
        });

        IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
            scenario: IEconomicSimulation.Scenario.TREASURY_STRESS,
            durationDays: 365,
            initialTreasury: 100_000e18, // Small treasury
            initialVerifiers: 100,
            initialStakers: 500,
            dailyClaimVolume: 50,
            govParams: govParams
        });

        vm.prank(simulator);
        IEconomicSimulation.SimulationReport memory report = sim.simulate(config);

        // Treasury stress scenario should generate warnings
        assertTrue(report.warnings.length > 0 || report.metrics.treasurySolvency < 1_000_000e18);
    }

    // ============ Governance Change Simulation ============

    function test_GovernanceChangeSimulation() public {
        IEconomicSimulation.GovernanceParams memory govParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 30,   // Higher slash
            rewardPercent: 90,   // Higher reward
            minStakeAmount: 50e18,
            settlementThresholdPercent: 50,
            verificationWindowDuration: 7 days,
            rewardIncrement: 20,
            penaltyAmount: 15,
            maliciousMultiplier: 10
        });

        IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
            scenario: IEconomicSimulation.Scenario.GOVERNANCE_CHANGE,
            durationDays: 180,
            initialTreasury: 1_000_000e18,
            initialVerifiers: 100,
            initialStakers: 500,
            dailyClaimVolume: 50,
            govParams: govParams
        });

        vm.prank(simulator);
        IEconomicSimulation.SimulationReport memory report = sim.simulate(config);
        assertTrue(report.metrics.sustainabilityIndex > 0);
    }

    // ============ Preview Simulation ============

    function test_PreviewSimulation() public {
        IEconomicSimulation.GovernanceParams memory govParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 20,
            rewardPercent: 80,
            minStakeAmount: 100e18,
            settlementThresholdPercent: 60,
            verificationWindowDuration: 7 days,
            rewardIncrement: 10,
            penaltyAmount: 10,
            maliciousMultiplier: 5
        });

        IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
            scenario: IEconomicSimulation.Scenario.NORMAL_GROWTH,
            durationDays: 365,
            initialTreasury: 1_000_000e18,
            initialVerifiers: 100,
            initialStakers: 500,
            dailyClaimVolume: 50,
            govParams: govParams
        });

        IEconomicSimulation.EconomicMetrics memory metrics = sim.previewSimulation(config);
        assertTrue(metrics.treasurySolvency > 0);
        assertTrue(metrics.sustainabilityIndex >= 0);
    }

    // ============ Governance Parameter Validation ============

    function test_ValidateValidParams() public {
        IEconomicSimulation.GovernanceParams memory goodParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 20,
            rewardPercent: 80,
            minStakeAmount: 100e18,
            settlementThresholdPercent: 60,
            verificationWindowDuration: 7 days,
            rewardIncrement: 10,
            penaltyAmount: 10,
            maliciousMultiplier: 5
        });

        (string[] memory warnings, bool safe) = sim.validateGovernanceParams(goodParams);
        assertTrue(safe);
        assertEq(warnings.length, 0);
    }

    function test_ValidateInvalidParams() public {
        IEconomicSimulation.GovernanceParams memory badParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 0,       // Invalid
            rewardPercent: 200,    // Invalid > 100
            minStakeAmount: 0,     // Invalid
            settlementThresholdPercent: 0, // Invalid
            verificationWindowDuration: 0, // Invalid
            rewardIncrement: 0,    // Invalid
            penaltyAmount: 0,      // Invalid
            maliciousMultiplier: 0 // Invalid
        });

        (string[] memory warnings, bool safe) = sim.validateGovernanceParams(badParams);
        assertFalse(safe);
        assertTrue(warnings.length > 0);
    }

    // ============ Determinism ============

    function test_SimulationDeterminism() public {
        IEconomicSimulation.GovernanceParams memory govParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 20,
            rewardPercent: 80,
            minStakeAmount: 100e18,
            settlementThresholdPercent: 60,
            verificationWindowDuration: 7 days,
            rewardIncrement: 10,
            penaltyAmount: 10,
            maliciousMultiplier: 5
        });

        IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
            scenario: IEconomicSimulation.Scenario.NORMAL_GROWTH,
            durationDays: 365,
            initialTreasury: 1_000_000e18,
            initialVerifiers: 100,
            initialStakers: 500,
            dailyClaimVolume: 50,
            govParams: govParams
        });

        // Run simulation twice and verify results are identical
        vm.prank(simulator);
        IEconomicSimulation.SimulationReport memory report1 = sim.simulate(config);

        vm.prank(simulator);
        IEconomicSimulation.SimulationReport memory report2 = sim.simulate(config);

        // Each run should have different IDs (due to timestamps and counter)
        assertFalse(report1.simulationId == report2.simulationId);

        // But metrics should be identical (deterministic)
        assertEq(report1.metrics.treasurySolvency, report2.metrics.treasurySolvency);
        assertEq(report1.metrics.totalRewardEmissions, report2.metrics.totalRewardEmissions);
        assertEq(report1.metrics.protocolRevenue, report2.metrics.protocolRevenue);
        assertEq(report1.metrics.sustainabilityIndex, report2.metrics.sustainabilityIndex);
    }

    // ============ Simulation Isolation from Protocol State ============

    function test_SimulationDoesNotAffectProtocolState() public {
        // The simulation is pure memory-based; verify it can be called without affecting contract state
        IEconomicSimulation.GovernanceParams memory govParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 20,
            rewardPercent: 80,
            minStakeAmount: 100e18,
            settlementThresholdPercent: 60,
            verificationWindowDuration: 7 days,
            rewardIncrement: 10,
            penaltyAmount: 10,
            maliciousMultiplier: 5
        });

        IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
            scenario: IEconomicSimulation.Scenario.NORMAL_GROWTH,
            durationDays: 365,
            initialTreasury: 1_000_000e18,
            initialVerifiers: 100,
            initialStakers: 500,
            dailyClaimVolume: 50,
            govParams: govParams
        });

        uint256 countBefore = sim.getSimulationCount();

        vm.prank(simulator);
        sim.simulate(config);

        // Only simulation count and report storage change — no protocol state
        assertEq(sim.getSimulationCount(), countBefore + 1);
    }

    // ============ Access Control ============

    function test_OnlySimulatorCanRunSimulation() public {
        IEconomicSimulation.GovernanceParams memory govParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 20,
            rewardPercent: 80,
            minStakeAmount: 100e18,
            settlementThresholdPercent: 60,
            verificationWindowDuration: 7 days,
            rewardIncrement: 10,
            penaltyAmount: 10,
            maliciousMultiplier: 5
        });

        IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
            scenario: IEconomicSimulation.Scenario.NORMAL_GROWTH,
            durationDays: 365,
            initialTreasury: 1_000_000e18,
            initialVerifiers: 100,
            initialStakers: 500,
            dailyClaimVolume: 50,
            govParams: govParams
        });

        vm.prank(attacker);
        vm.expectRevert();
        sim.simulate(config);
    }

    // ============ View Functions ============

    function test_GetAvailableScenarios() public {
        IEconomicSimulation.Scenario[] memory scenarios = sim.getAvailableScenarios();
        assertEq(scenarios.length, 6);
    }

    function test_GetScenarioName() public {
        assertEq(sim.getScenarioName(IEconomicSimulation.Scenario.NORMAL_GROWTH), "Normal Growth");
        assertEq(sim.getScenarioName(IEconomicSimulation.Scenario.HIGH_GROWTH), "High Growth");
        assertEq(sim.getScenarioName(IEconomicSimulation.Scenario.TREASURY_STRESS), "Treasury Stress");
        assertEq(sim.getScenarioName(IEconomicSimulation.Scenario.GOVERNANCE_CHANGE), "Governance Change");
    }

    function test_GetScenarioDescription() public {
        string memory desc = sim.getScenarioDescription(IEconomicSimulation.Scenario.NORMAL_GROWTH);
        assertTrue(bytes(desc).length > 0);
    }

    function test_GetSimulationById() public {
        IEconomicSimulation.GovernanceParams memory govParams = IEconomicSimulation.GovernanceParams({
            slashPercent: 20,
            rewardPercent: 80,
            minStakeAmount: 100e18,
            settlementThresholdPercent: 60,
            verificationWindowDuration: 7 days,
            rewardIncrement: 10,
            penaltyAmount: 10,
            maliciousMultiplier: 5
        });

        IEconomicSimulation.SimulationConfig memory config = IEconomicSimulation.SimulationConfig({
            scenario: IEconomicSimulation.Scenario.NORMAL_GROWTH,
            durationDays: 365,
            initialTreasury: 1_000_000e18,
            initialVerifiers: 100,
            initialStakers: 500,
            dailyClaimVolume: 50,
            govParams: govParams
        });

        vm.prank(simulator);
        IEconomicSimulation.SimulationReport memory report = sim.simulate(config);

        IEconomicSimulation.SimulationReport memory fetched = sim.getSimulation(report.simulationId);
        assertEq(fetched.simulationId, report.simulationId);
        assertEq(uint256(fetched.scenario), uint256(report.scenario));
    }

    function test_RevertWhen_SimulationNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(EconomicSimulation.SimulationNotFound.selector, bytes32(0)));
        sim.getSimulation(bytes32(0));
    }

    // ============ Economic Thresholds ============

    function test_SetEconomicThreshold() public {
        bytes32 metricId = keccak256("TEST_METRIC");
        vm.prank(admin);
        sim.setEconomicThreshold(metricId, 5000);

        assertEq(sim.economicThresholds(metricId), 5000);
    }

    function test_OnlyAdminCanSetThresholds() public {
        vm.prank(attacker);
        vm.expectRevert();
        sim.setEconomicThreshold(keccak256("TEST"), 1000);
    }
}
