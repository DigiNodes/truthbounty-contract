// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {EmergencyControls} from "../../contracts/v2/EmergencyControls.sol";
import {EmergencyGatekeeper} from "../../contracts/v2/EmergencyGatekeeper.sol";
import {EmergencyController} from "../../contracts/governance/EmergencyController.sol";
import {GasBudgetRegistry} from "../../contracts/performance/GasBudgetRegistry.sol";
import {ICriticalPathGasBudgets} from "../../contracts/performance/ICriticalPathGasBudgets.sol";
import {IEmergencyControls} from "../../contracts/v2/interfaces/IEmergencyControls.sol";

/**
 * @title EmergencyPauseBoundsTest
 * @notice Dedicated test suite for PREWAVE-SC-074 (#749) — Bound Emergency Pause Gas and Blast Radius.
 * @dev Enforces:
 *      1. Pause gas cost strictly bounded below approved budget (180,000 gas).
 *      2. Blast-radius containment: pausing one scope does not affect unrelated scopes.
 *      3. Repeat pause determinism: fail-closed reverts on repeated pause calls.
 *      4. Event auditability: verified emission of scope, actor, and incident details.
 *      5. O(1) complexity: pause execution does not iterate unbounded collections.
 */
contract EmergencyPauseBoundsTest is Test {
    EmergencyControls internal controls;
    EmergencyGatekeeper internal gatekeeper;
    EmergencyController internal controller;
    GasBudgetRegistry internal budgets;

    address internal admin = address(0xAD11);
    address internal emergencyCouncil = address(0xEC01);
    address internal governance = address(0x6001);
    address internal unauthorized = address(0xBAD1);

    bytes32 internal constant SCOPE_ALL = bytes32(0);
    bytes32 internal constant SCOPE_CLAIMS = keccak256("truthbounty.v2.scope.claims");
    bytes32 internal constant SCOPE_EVIDENCE = keccak256("truthbounty.v2.scope.evidence");
    bytes32 internal constant SCOPE_STAKING = keccak256("truthbounty.v2.scope.staking");
    bytes32 internal constant SCOPE_VERIFICATION = keccak256("truthbounty.v2.scope.verification");
    bytes32 internal constant SCOPE_SETTLEMENT = keccak256("truthbounty.v2.scope.settlement");
    bytes32 internal constant SCOPE_TREASURY = keccak256("truthbounty.v2.scope.treasury");
    bytes32 internal constant SCOPE_DISPUTES = keccak256("truthbounty.v2.scope.disputes");

    uint256 internal constant EMERGENCY_PAUSE_BUDGET = 180_000;

    event EmergencyPaused(bytes32 indexed scope, address indexed actor);
    event ScopePauseUpdated(bytes32 indexed scope, address indexed actor, bool paused);
    event EmergencyPauseActivated(
        uint8 indexed level,
        address indexed executor,
        string reason,
        bytes32 indexed proposalRef
    );

    function setUp() public {
        controls = new EmergencyControls(admin, emergencyCouncil, governance);
        gatekeeper = new EmergencyGatekeeper(admin, emergencyCouncil, governance, 1 hours);
        controller = new EmergencyController(emergencyCouncil, governance, governance);
        budgets = new GasBudgetRegistry(admin);
    }

    // =========================================================================
    // 1. Gas Budget Bounds (< 180,000 gas)
    // =========================================================================

    function test_EmergencyControls_PauseGasWithinApprovedBudget() public {
        (uint256 budget,) = budgets.getBudget(ICriticalPathGasBudgets.Operation.EMERGENCY_PAUSE);
        assertEq(budget, EMERGENCY_PAUSE_BUDGET, "Configured budget must match approved 180,000 gas");

        bytes32[7] memory scopes = [
            SCOPE_CLAIMS,
            SCOPE_EVIDENCE,
            SCOPE_STAKING,
            SCOPE_VERIFICATION,
            SCOPE_SETTLEMENT,
            SCOPE_TREASURY,
            SCOPE_DISPUTES
        ];

        for (uint256 i = 0; i < scopes.length; ++i) {
            bytes32 sc = scopes[i];
            vm.prank(emergencyCouncil);
            uint256 gasStart = gasleft();
            controls.pause(sc);
            uint256 gasUsed = gasStart - gasleft();

            assertLt(gasUsed, EMERGENCY_PAUSE_BUDGET, "Pause gas exceeded 180,000 budget");
            assertLt(gasUsed, 70_000, "O(1) pause should consume well under 70,000 gas");
        }
    }

    function test_EmergencyGatekeeper_PauseGasWithinBudget() public {
        vm.prank(emergencyCouncil);
        uint256 gasStart = gasleft();
        gatekeeper.pause(SCOPE_CLAIMS);
        uint256 gasUsed = gasStart - gasleft();

        assertLt(gasUsed, EMERGENCY_PAUSE_BUDGET, "Gatekeeper pause exceeded 180,000 gas");
    }

    function test_EmergencyController_ActivatePauseGasWithinBudget() public {
        vm.prank(emergencyCouncil);
        uint256 gasStart = gasleft();
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "Incident containment", bytes32("INC_001"));
        uint256 gasUsed = gasStart - gasleft();

        assertLt(gasUsed, EMERGENCY_PAUSE_BUDGET, "EmergencyController pause exceeded 180,000 gas");
    }

    // =========================================================================
    // 2. Blast Radius Containment
    // =========================================================================

    function test_BlastRadius_PausingOneScopeDoesNotAffectOthers() public {
        vm.prank(emergencyCouncil);
        controls.pause(SCOPE_CLAIMS);

        assertTrue(controls.paused(SCOPE_CLAIMS), "Paused scope must report paused");
        assertFalse(controls.paused(SCOPE_EVIDENCE), "Unrelated scope must not be paused");
        assertFalse(controls.paused(SCOPE_STAKING), "Unrelated scope must not be paused");
        assertFalse(controls.paused(SCOPE_TREASURY), "Unrelated scope must not be paused");
    }

    function test_BlastRadius_GatekeeperScopedIsolation() public {
        vm.prank(emergencyCouncil);
        gatekeeper.pause(SCOPE_SETTLEMENT);

        assertTrue(gatekeeper.paused(SCOPE_SETTLEMENT), "Target scope must be paused");
        assertFalse(gatekeeper.paused(SCOPE_STAKING), "Unrelated scope must not be paused");
        gatekeeper.requireNotPaused(SCOPE_STAKING); // Should not revert
    }

    function test_Composition_GlobalPauseHaltsAllScopes() public {
        vm.prank(emergencyCouncil);
        controls.pause(SCOPE_ALL);

        assertTrue(controls.paused(SCOPE_CLAIMS), "SCOPE_ALL must halt claims");
        assertTrue(controls.paused(SCOPE_EVIDENCE), "SCOPE_ALL must halt evidence");
        assertTrue(controls.paused(SCOPE_STAKING), "SCOPE_ALL must halt staking");
        assertTrue(controls.paused(SCOPE_TREASURY), "SCOPE_ALL must halt treasury");
    }

    // =========================================================================
    // 3. Repeat Pause Determinism
    // =========================================================================

    function test_RepeatPauseRevertsDeterministically_EmergencyControls() public {
        vm.prank(emergencyCouncil);
        controls.pause(SCOPE_TREASURY);

        vm.prank(emergencyCouncil);
        vm.expectRevert(abi.encodeWithSelector(EmergencyControls.AlreadyPaused.selector, SCOPE_TREASURY));
        controls.pause(SCOPE_TREASURY);
    }

    function test_RepeatPauseRevertsDeterministically_EmergencyGatekeeper() public {
        vm.prank(emergencyCouncil);
        gatekeeper.pause(SCOPE_DISPUTES);

        vm.prank(emergencyCouncil);
        vm.expectRevert(abi.encodeWithSelector(EmergencyGatekeeper.ScopeAlreadyPaused.selector, SCOPE_DISPUTES, true));
        gatekeeper.pause(SCOPE_DISPUTES);
    }

    function test_RepeatPauseRevertsDeterministically_EmergencyController() public {
        vm.prank(emergencyCouncil);
        controller.activatePause(2, "Level 2 pause", bytes32("L2"));

        vm.prank(emergencyCouncil);
        vm.expectRevert(abi.encodeWithSelector(EmergencyController.AlreadyAtLevel.selector, 2));
        controller.activatePause(2, "Repeat level 2", bytes32("L2_REPEAT"));
    }

    // =========================================================================
    // 4. Audit Event Completeness
    // =========================================================================

    function test_AuditEvents_EmergencyControls() public {
        vm.expectEmit(true, true, false, false, address(controls));
        emit EmergencyPaused(SCOPE_STAKING, emergencyCouncil);

        vm.prank(emergencyCouncil);
        controls.pause(SCOPE_STAKING);
    }

    function test_AuditEvents_EmergencyGatekeeper() public {
        vm.expectEmit(true, true, false, false, address(gatekeeper));
        emit EmergencyPaused(SCOPE_VERIFICATION, emergencyCouncil);

        vm.expectEmit(true, true, false, true, address(gatekeeper));
        emit ScopePauseUpdated(SCOPE_VERIFICATION, emergencyCouncil, true);

        vm.prank(emergencyCouncil);
        gatekeeper.pause(SCOPE_VERIFICATION);
    }

    function test_AuditEvents_EmergencyController() public {
        string memory reason = "Congestion halt";
        bytes32 incidentRef = bytes32("REF_749");

        vm.expectEmit(true, true, false, true, address(controller));
        emit EmergencyPauseActivated(3, emergencyCouncil, reason, incidentRef);

        vm.prank(emergencyCouncil);
        controller.activatePause(3, reason, incidentRef);
    }

    // =========================================================================
    // 5. O(1) Scalability (No Loop / Unbounded Collection Iteration)
    // =========================================================================

    function test_O1Complexity_PauseGasConstantAcrossSequences() public {
        vm.prank(emergencyCouncil);
        uint256 gas1Start = gasleft();
        controls.pause(SCOPE_CLAIMS);
        uint256 gas1 = gas1Start - gasleft();

        vm.prank(emergencyCouncil);
        uint256 gas2Start = gasleft();
        controls.pause(SCOPE_EVIDENCE);
        uint256 gas2 = gas2Start - gasleft();

        // Execution of subsequent pauses should not diverge significantly (within warm cache EVM delta)
        uint256 delta = gas1 > gas2 ? gas1 - gas2 : gas2 - gas1;
        assertLt(delta, 500, "Pause execution gas must exhibit O(1) constant complexity");
    }
}
