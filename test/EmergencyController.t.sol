// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../contracts/governance/EmergencyController.sol";

/**
 * @title EmergencyControllerTest
 * @notice Unit tests for the Emergency Pause & Circuit Breaker Framework
 */
contract EmergencyControllerTest is Test {
    EmergencyController public controller;

    address public emergencyCouncil = makeAddr("emergencyCouncil");
    address public daoGovernance = makeAddr("daoGovernance");
    address public timelockController = makeAddr("timelockController");
    address public unauthorisedUser = makeAddr("unauthorisedUser");
    address public recoveryExecutor = makeAddr("recoveryExecutor");

    function setUp() public {
        controller = new EmergencyController(
            emergencyCouncil,
            daoGovernance,
            timelockController
        );
        vm.prank(daoGovernance);
        controller.grantRole(controller.RECOVERY_EXECUTOR(), recoveryExecutor);
    }

    // ─── Initialisation ───────────────────────────────────────────────

    function test_initialState() public view {
        assertEq(controller.currentPauseLevel(), controller.LEVEL_NORMAL());
        assertEq(controller.recoveryComplete(), true);
        assertEq(controller.getEmergencyHistoryCount(), 0);
    }

    function test_constructor_revertsZeroAddress() public {
        vm.expectRevert(EmergencyController.ZeroAddress.selector);
        new EmergencyController(address(0), daoGovernance, timelockController);
    }

    // ─── Pause Activation ─────────────────────────────────────────────

    function test_emergencyCouncil_canActivateLevel1() public {
        vm.prank(emergencyCouncil);
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "Security incident", bytes32(0));
        assertEq(controller.currentPauseLevel(), controller.LEVEL_HIGH_RISK());
    }

    function test_emergencyCouncil_canActivateLevel3() public {
        vm.prank(emergencyCouncil);
        controller.activatePause(controller.LEVEL_SHUTDOWN(), "Critical exploit", bytes32(0));
        assertEq(controller.currentPauseLevel(), controller.LEVEL_SHUTDOWN());
    }

    function test_daoGovernance_canActivateLevel2() public {
        vm.prank(daoGovernance);
        controller.activatePause(controller.LEVEL_FINANCIAL(), "Oracle failure", bytes32(0));
        assertEq(controller.currentPauseLevel(), controller.LEVEL_FINANCIAL());
    }

    function test_timelock_canActivateLevel1() public {
        vm.prank(timelockController);
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "Scheduled maintenance", bytes32(0));
        assertEq(controller.currentPauseLevel(), controller.LEVEL_HIGH_RISK());
    }

    function test_timelock_cannotActivateLevel2() public {
        vm.prank(timelockController);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyController.NotAuthorizedForLevel.selector,
                timelockController,
                controller.LEVEL_FINANCIAL()
            )
        );
        controller.activatePause(controller.LEVEL_FINANCIAL(), "Not allowed", bytes32(0));
    }

    function test_unauthorised_cannotActivate() public {
        vm.prank(unauthorisedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyController.NotAuthorizedForLevel.selector,
                unauthorisedUser,
                controller.LEVEL_HIGH_RISK()
            )
        );
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "Hack attempt", bytes32(0));
    }

    function test_cannotActivateSameOrLowerLevel() public {
        vm.prank(emergencyCouncil);
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "First", bytes32(0));

        vm.prank(emergencyCouncil);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyController.AlreadyAtLevel.selector,
                controller.LEVEL_HIGH_RISK()
            )
        );
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "Duplicate", bytes32(0));
    }

    function test_cannotActivateLevel0() public {
        vm.prank(emergencyCouncil);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyController.InvalidPauseLevel.selector, 0)
        );
        controller.activatePause(0, "Invalid", bytes32(0));
    }

    function test_cannotActivateAboveMaxLevel() public {
        vm.prank(emergencyCouncil);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyController.InvalidPauseLevel.selector, 99)
        );
        controller.activatePause(99, "Invalid", bytes32(0));
    }

    function test_timelockCooldown_enforced() public {
        vm.prank(timelockController);
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "First", bytes32(0));

        // Lift via governance
        vm.prank(daoGovernance);
        controller.liftPause(bytes32(0));

        // Timelock tries again immediately — should fail
        vm.prank(timelockController);
        vm.expectRevert("Timelock cooldown not elapsed");
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "Too soon", bytes32(0));

        // After cooldown
        vm.warp(block.timestamp + controller.timelockCooldown() + 1);
        vm.prank(timelockController);
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "After cooldown", bytes32(0));
        assertEq(controller.currentPauseLevel(), controller.LEVEL_HIGH_RISK());
    }

    // ─── Pause Lifting ─────────────────────────────────────────────────

    function test_daoGovernance_canLiftPause() public {
        vm.prank(emergencyCouncil);
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "Test", bytes32(0));

        vm.prank(daoGovernance);
        controller.liftPause(bytes32(0));

        assertEq(controller.currentPauseLevel(), controller.LEVEL_NORMAL());
    }

    function test_emergencyCouncil_cannotLiftPause() public {
        vm.prank(emergencyCouncil);
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "Test", bytes32(0));

        vm.prank(emergencyCouncil);
        vm.expectRevert("Only DAO governance can lift pause");
        controller.liftPause(bytes32(0));
    }

    function test_cannotLiftWhenNotPaused() public {
        vm.prank(daoGovernance);
        vm.expectRevert(EmergencyController.ProtocolNotPaused.selector);
        controller.liftPause(bytes32(0));
    }

    // ─── Recovery ─────────────────────────────────────────────────────

    function test_recoveryFlow_completes() public {
        // Activate and lift
        vm.prank(emergencyCouncil);
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "Test", bytes32(0));
        vm.prank(daoGovernance);
        controller.liftPause(bytes32(0));

        // Complete recovery steps
        vm.startPrank(recoveryExecutor);
        controller.completeRecoveryStep("Validation complete");
        controller.completeRecoveryStep("State verified");
        controller.completeRecoveryStep("All systems operational");
        vm.stopPrank();

        (bool complete, uint8 step, bool paused, uint8 level) = controller.getRecoveryStatus();
        assertTrue(complete);
        assertEq(step, 0);
        assertFalse(paused);
    }

    function test_recovery_mustBePaused() public {
        vm.prank(recoveryExecutor);
        vm.expectRevert("Recovery already complete");
        controller.completeRecoveryStep("Should fail");
    }

    // ─── Audit Trail ──────────────────────────────────────────────────

    function test_auditTrail_recordsActions() public {
        vm.prank(emergencyCouncil);
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "First incident", bytes32(0));

        assertEq(controller.getEmergencyHistoryCount(), 1);

        EmergencyController.EmergencyRecord[] memory history = controller.getEmergencyHistory(0, 10);
        assertEq(history[0].level, controller.LEVEL_HIGH_RISK());
        assertEq(history[0].initiator, emergencyCouncil);
        assertEq(history[0].reason, "First incident");
    }

    // ─── Read Interface ───────────────────────────────────────────────

    function test_isOperationAllowed_normalState() public view {
        assertTrue(controller.isOperationAllowed(keccak256("claim_creation")));
        assertTrue(controller.isOperationAllowed(keccak256("reward_distribution")));
    }

    function test_isOperationAllowed_level1_blocksHighRisk() public {
        vm.prank(emergencyCouncil);
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "Test", bytes32(0));

        assertFalse(controller.isOperationAllowed(keccak256("claim_creation")));
        assertFalse(controller.isOperationAllowed(keccak256("staking")));
        assertTrue(controller.isOperationAllowed(keccak256("reward_distribution")));
    }

    function test_isOperationAllowed_level3_onlyGovernance() public {
        vm.prank(emergencyCouncil);
        controller.activatePause(controller.LEVEL_SHUTDOWN(), "Critical", bytes32(0));

        assertFalse(controller.isOperationAllowed(keccak256("claim_creation")));
        assertFalse(controller.isOperationAllowed(keccak256("reward_distribution")));
        assertTrue(controller.isOperationAllowed(keccak256("governance_recovery")));
    }

    // ─── Events ───────────────────────────────────────────────────────

    function test_emitsEmergencyPauseActivated() public {
        vm.prank(emergencyCouncil);
        vm.expectEmit(true, true, true, true);
        emit EmergencyController.EmergencyPauseActivated(
            controller.LEVEL_HIGH_RISK(),
            emergencyCouncil,
            "Test reason",
            bytes32(0)
        );
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "Test reason", bytes32(0));
    }

    function test_emitsEmergencyPauseLifted() public {
        vm.prank(emergencyCouncil);
        controller.activatePause(controller.LEVEL_HIGH_RISK(), "Test", bytes32(0));

        vm.prank(daoGovernance);
        vm.expectEmit(true, true, true, true);
        emit EmergencyController.EmergencyPauseLifted(
            controller.LEVEL_HIGH_RISK(),
            daoGovernance,
            bytes32(0)
        );
        controller.liftPause(bytes32(0));
    }
}
