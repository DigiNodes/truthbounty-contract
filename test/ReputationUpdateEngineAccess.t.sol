// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/ReputationUpdateEngine.sol";
import "../contracts/IReputationUpdateEngine.sol";
import "../contracts/governance/GovernanceController.sol";
import "../contracts/governance/GovernanceHooks.sol";

contract ReputationUpdateEngineAccessTest is Test {
    ReputationUpdateEngine public engine;
    GovernanceController public governance;
    address public admin = address(0x1);
    address public verifier = address(0x2);
    address public resolver = address(0x3);
    address public governanceAddress = address(0x10);

    function setUp() public {
        governance = new GovernanceController(admin);

        engine = new ReputationUpdateEngine(admin, address(governance));
        engine.grantUpdateRole(resolver);
    }

    // ============ Role Management ============

    function test_GrantUpdateRole() public {
        assertFalse(engine.hasRole(engine.UPDATE_ROLE(), resolver));

        vm.prank(admin);
        engine.grantUpdateRole(resolver);

        assertTrue(engine.hasRole(engine.UPDATE_ROLE(), resolver));
    }

    function test_RevokeUpdateRole() public {
        vm.prank(admin);
        engine.grantUpdateRole(resolver);
        vm.prank(admin);
        engine.revokeUpdateRole(resolver);

        assertFalse(engine.hasRole(engine.UPDATE_ROLE(), resolver));
    }

    function test_AdminCanUpdate() public {
        IReputationUpdateEngine.ReputationUpdate memory update = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 0,
            reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
            claimId: 1
        });

        vm.prank(admin);
        engine.updateReputation(update);

        assertEq(engine.getReputation(verifier), 10);
    }

    // ============ Only Admin Can Grant Roles ============

    function test_OnlyAdminCanGrantUpdateRole() public {
        vm.prank(resolver);
        vm.expectRevert();
        engine.grantUpdateRole(address(0x5));
    }

    // ============ Governance Integration ============

    function test_GovernanceCanSetParameters() public {
        // Governance (admin) can update parameters
        vm.prank(admin);
        engine.setRewardIncrement(50);

        assertEq(engine.rewardIncrement(), 50);
    }

    function test_GovernanceControllerAddress() public {
        assertEq(engine.governanceController(), address(governance));
        assertTrue(engine.hasRole(engine.GOVERNANCE_ROLE(), address(governance)));
    }

    // ============ Multiple Updates per Verifier ============

    function test_MultiplePositiveUpdates() public {
        vm.prank(admin);
        engine.grantUpdateRole(admin);

        for (uint256 i = 1; i <= 5; i++) {
            IReputationUpdateEngine.ReputationUpdate memory update = IReputationUpdateEngine.ReputationUpdate({
                verifier: verifier,
                delta: 0,
                reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
                claimId: i
            });
            vm.prank(admin);
            engine.updateReputation(update);
        }

        assertEq(engine.getReputation(verifier), 50);
        assertEq(engine.getUpdateCount(verifier), 5);
        assertEq(engine.successfulUpdates(verifier), 5);
        assertEq(engine.totalReputationGained(verifier), 50);
    }

    // ============ History Pagination ============

    function test_HistoryPagination() public {
        vm.prank(admin);
        engine.grantUpdateRole(admin);

        for (uint256 i = 1; i <= 10; i++) {
            IReputationUpdateEngine.ReputationUpdate memory update = IReputationUpdateEngine.ReputationUpdate({
                verifier: verifier,
                delta: 0,
                reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
                claimId: i
            });
            vm.prank(admin);
            engine.updateReputation(update);
        }

        // Test pagination
        IReputationUpdateEngine.ReputationUpdateRecord[] memory page1 = engine.getUpdateHistory(verifier, 0, 3);
        assertEq(page1.length, 3);

        IReputationUpdateEngine.ReputationUpdateRecord[] memory page2 = engine.getUpdateHistory(verifier, 8, 5);
        assertEq(page2.length, 2); // Only 2 remaining

        // Offset beyond length
        IReputationUpdateEngine.ReputationUpdateRecord[] memory empty = engine.getUpdateHistory(verifier, 20, 5);
        assertEq(empty.length, 0);
    }
}
