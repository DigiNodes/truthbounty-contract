// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "../../contracts/governance/EmergencyController.sol";
import "../../contracts/v2/EmergencyControls.sol";
import {IEmergencyControls} from "../../contracts/v2/interfaces/IEmergencyControls.sol";
import {IV2Module} from "../../contracts/v2/interfaces/IV2Module.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title EmergencyRecoveryFuzzTest
 * @notice Property-based fuzz tests for EmergencyController and EmergencyControls.
 * @dev Enforces state-invariants across arbitrary inputs:
 *      - Monotonicity of operation restriction across pause levels
 *      - Fail-closed authorization: no unauthorized caller can pause or unpause
 *      - Strict separation of powers: emergency council can never lift pause
 *      - Global scope dominance in V2 scoped emergency controls
 *      - Sequential recovery step integrity
 */
contract EmergencyRecoveryFuzzTest is Test {
    EmergencyController internal controller;
    EmergencyControls internal controls;

    address internal admin = makeAddr("admin");
    address internal emergencyCouncil = makeAddr("emergencyCouncil");
    address internal daoGovernance = makeAddr("daoGovernance");
    address internal timelockController = makeAddr("timelockController");

    function setUp() public {
        controller = new EmergencyController(
            emergencyCouncil,
            daoGovernance,
            timelockController
        );

        controls = new EmergencyControls(
            admin,
            emergencyCouncil,
            daoGovernance
        );
    }

    /// @dev Property: Emergency council can pause, but can NEVER lift pause regardless of proposal reference.
    function testFuzz_emergencyCouncil_cannotLiftPause(uint8 level, bytes32 proposalRef) public {
        vm.assume(level >= 1 && level <= 3);

        vm.prank(emergencyCouncil);
        controller.activatePause(level, "Fuzz pause", proposalRef);

        // Emergency council attempts to lift
        vm.prank(emergencyCouncil);
        vm.expectRevert("Only DAO governance can lift pause");
        controller.liftPause(proposalRef);

        // Invariant: protocol remains paused
        assertEq(controller.currentPauseLevel(), level);
    }

    /// @dev Property: Unauthorized callers can never activate a pause.
    function testFuzz_unauthorized_activation_reverts(address caller, uint8 level, string calldata reason) public {
        vm.assume(caller != emergencyCouncil);
        vm.assume(caller != daoGovernance);
        vm.assume(caller != timelockController);
        vm.assume(level >= 1 && level <= 3);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyController.NotAuthorizedForLevel.selector,
                caller,
                level
            )
        );
        controller.activatePause(level, reason, bytes32(0));
    }

    /// @dev Property: At Level 1+, high-risk operations are always blocked.
    function testFuzz_level1_blocks_highRisk(uint8 level) public {
        vm.assume(level >= 1 && level <= 3);

        vm.prank(emergencyCouncil);
        controller.activatePause(level, "Fuzz L1+", bytes32(0));

        assertFalse(controller.isOperationAllowed(keccak256("claim_creation")));
        assertFalse(controller.isOperationAllowed(keccak256("staking")));
        assertFalse(controller.isOperationAllowed(keccak256("verification_submission")));
    }

    /// @dev Property: At Level 2+, financial operations are always blocked.
    function testFuzz_level2_blocks_financial(uint8 level) public {
        vm.assume(level >= 2 && level <= 3);

        vm.prank(emergencyCouncil);
        controller.activatePause(level, "Fuzz L2+", bytes32(0));

        assertFalse(controller.isOperationAllowed(keccak256("reward_distribution")));
        assertFalse(controller.isOperationAllowed(keccak256("treasury_transfer")));
        assertFalse(controller.isOperationAllowed(keccak256("withdrawal")));
    }

    /// @dev Property: At Level 3, all operations except governance recovery are blocked.
    function testFuzz_level3_only_allows_governance_recovery(bytes32 opType) public {
        vm.prank(emergencyCouncil);
        controller.activatePause(3, "Fuzz L3", bytes32(0));

        if (opType == keccak256("governance_recovery")) {
            assertTrue(controller.isOperationAllowed(opType));
        } else {
            assertFalse(controller.isOperationAllowed(opType));
        }
    }

    /// @dev Property: In V2 EmergencyControls, global pause halts all arbitrary scopes.
    function testFuzz_v2EmergencyControls_globalScope_dominance(bytes32 arbitraryScope) public {
        vm.prank(emergencyCouncil);
        controls.pause(controls.SCOPE_ALL());

        // Invariant: any scope is paused when global scope is paused
        assertTrue(controls.paused(arbitraryScope));
    }

    /// @dev Property: In V2 EmergencyControls, only GOVERNANCE_ROLE can unpause.
    function testFuzz_v2EmergencyControls_unauthorized_unpause(address caller, bytes32 scope) public {
        vm.assume(caller != daoGovernance);

        vm.prank(emergencyCouncil);
        controls.pause(scope);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(EmergencyControls.UnauthorizedToUnpause.selector, caller)
        );
        controls.unpause(scope);
    }
}
