// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/ReputationUpdateEngine.sol";
import "../contracts/IReputationUpdateEngine.sol";

contract ReputationUpdateEngineTest is Test {
    ReputationUpdateEngine public engine;
    address public admin = address(0x1);
    address public verifier = address(0x2);
    address public resolver = address(0x3);
    address public attacker = address(0x4);

    event ReputationUpdated(address indexed verifier, int256 delta, uint256 newScore, uint256 claimId);
    event UpdateParametersUpdated(bytes32 indexed paramId, uint256 oldValue, uint256 newValue);

    function setUp() public {
        engine = new ReputationUpdateEngine(admin, address(0));

        // Grant UPDATE_ROLE to resolver
        vm.prank(admin);
        engine.grantUpdateRole(resolver);
    }

    // ============ Constructor ============

    function test_Constructor() public {
        assertEq(engine.rewardIncrement(), 10);
        assertEq(engine.penaltyAmount(), 10);
        assertEq(engine.maliciousMultiplier(), 5);
        assertEq(engine.minimumReputationFloor(), 0);
        assertEq(engine.maximumReputationCap(), type(uint256).max);
        assertTrue(engine.hasRole(engine.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(engine.hasRole(engine.UPDATE_ROLE(), admin));
        assertTrue(engine.hasRole(engine.ADMIN_ROLE(), admin));
        assertTrue(engine.hasRole(engine.PAUSER_ROLE(), admin));
    }

    function test_RevertWhen_ZeroAddressAdmin() public {
        vm.expectRevert();
        new ReputationUpdateEngine(address(0), address(0));
    }

    // ============ Core: Positive Reputation Update ============

    function test_PositiveUpdate() public {
        IReputationUpdateEngine.ReputationUpdate memory update = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 0, // ignored, computed by reason
            reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
            claimId: 1
        });

        vm.prank(resolver);
        vm.expectEmit(true, true, true, true);
        emit ReputationUpdated(verifier, 10, 10, 1);
        engine.updateReputation(update);

        assertEq(engine.getReputation(verifier), 10);
        assertEq(engine.getUpdateCount(verifier), 1);
        assertTrue(engine.isClaimProcessed(verifier, 1));
        assertEq(engine.successfulUpdates(verifier), 1);
        assertEq(engine.totalReputationGained(verifier), 10);
    }

    // ============ Core: Negative Reputation Update ============

    function test_NegativeUpdate() public {
        // First give some reputation
        vm.prank(admin);
        engine.grantUpdateRole(admin);

        IReputationUpdateEngine.ReputationUpdate memory posUpdate = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 0,
            reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
            claimId: 1
        });
        vm.prank(admin);
        engine.updateReputation(posUpdate);

        // Now apply penalty
        IReputationUpdateEngine.ReputationUpdate memory negUpdate = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 0,
            reason: IReputationUpdateEngine.UpdateReason.INCORRECT_VERIFICATION,
            claimId: 2
        });
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit ReputationUpdated(verifier, -10, 0, 2);
        engine.updateReputation(negUpdate);

        assertEq(engine.getReputation(verifier), 0);
        assertEq(engine.totalReputationLost(verifier), 10);
        assertEq(engine.failedVerifications(verifier), 1);
    }

    // ============ Core: Malicious Behaviour ============

    function test_MaliciousBehaviour() public {
        vm.prank(admin);
        engine.grantUpdateRole(admin);

        // First give some reputation
        IReputationUpdateEngine.ReputationUpdate memory posUpdate = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 0,
            reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
            claimId: 1
        });
        vm.prank(admin);
        engine.updateReputation(posUpdate);

        // Apply malicious penalty (penalty * multiplier = 10 * 5 = 50)
        IReputationUpdateEngine.ReputationUpdate memory malUpdate = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 0,
            reason: IReputationUpdateEngine.UpdateReason.MALICIOUS_BEHAVIOUR,
            claimId: 3
        });

        vm.prank(admin);
        engine.updateReputation(malUpdate);

        assertEq(engine.getReputation(verifier), 0); // 10 - 50, floored at 0
        assertEq(engine.maliciousPenalties(verifier), 1);
        assertEq(engine.totalReputationLost(verifier), 50);
    }

    // ============ Core: Disputed Claim ============

    function test_DisputedClaim() public {
        vm.prank(admin);
        engine.grantUpdateRole(admin);

        IReputationUpdateEngine.ReputationUpdate memory update = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 1,
            reason: IReputationUpdateEngine.UpdateReason.DISPUTED_CLAIM,
            claimId: 5
        });

        vm.prank(admin);
        engine.updateReputation(update);

        // Dispute adjustment is 0 by default
        assertEq(engine.getReputation(verifier), 0);
        assertEq(engine.disputedOutcomes(verifier), 1);
    }

    // ============ Security: Duplicate Prevention ============

    function test_RevertWhen_DuplicateUpdate() public {
        IReputationUpdateEngine.ReputationUpdate memory update = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 0,
            reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
            claimId: 1
        });

        vm.prank(resolver);
        engine.updateReputation(update);

        vm.prank(resolver);
        vm.expectRevert(
            abi.encodeWithSelector(
                ReputationUpdateEngine.DuplicateUpdate.selector,
                verifier,
                uint256(1)
            )
        );
        engine.updateReputation(update);
    }

    // ============ Security: Unauthorized Access ============

    function test_RevertWhen_UnauthorizedUpdate() public {
        IReputationUpdateEngine.ReputationUpdate memory update = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 0,
            reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
            claimId: 1
        });

        vm.prank(attacker);
        vm.expectRevert(ReputationUpdateEngine.UnauthorizedUpdate.selector);
        engine.updateReputation(update);
    }

    // ============ Security: Zero Address ============

    function test_RevertWhen_ZeroAddressVerifier() public {
        IReputationUpdateEngine.ReputationUpdate memory update = IReputationUpdateEngine.ReputationUpdate({
            verifier: address(0),
            delta: 0,
            reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
            claimId: 1
        });

        vm.prank(resolver);
        vm.expectRevert(ReputationUpdateEngine.InvalidAddress.selector);
        engine.updateReputation(update);
    }

    // ============ Governance Parameters ============

    function test_SetRewardIncrement() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit UpdateParametersUpdated(keccak256("REWARD_INCREMENT"), 10, 20);
        engine.setRewardIncrement(20);
        assertEq(engine.rewardIncrement(), 20);
    }

    function test_SetPenaltyAmount() public {
        vm.prank(admin);
        engine.setPenaltyAmount(25);
        assertEq(engine.penaltyAmount(), 25);
    }

    function test_SetMaliciousMultiplier() public {
        vm.prank(admin);
        engine.setMaliciousMultiplier(10);
        assertEq(engine.maliciousMultiplier(), 10);
    }

    function test_RevertWhen_NonAdminSetsParameters() public {
        vm.prank(attacker);
        vm.expectRevert();
        engine.setRewardIncrement(20);
    }

    function test_SetMinimumReputationFloor() public {
        vm.prank(admin);
        engine.setMinimumReputationFloor(5);
        assertEq(engine.minimumReputationFloor(), 5);
    }

    function test_RevertWhen_FloorExceedsCap() public {
        vm.prank(admin);
        engine.setMaximumReputationCap(100);

        vm.prank(admin);
        vm.expectRevert(ReputationUpdateEngine.InvalidParameter.selector);
        engine.setMinimumReputationFloor(200);
    }

    // ============ View Functions ============

    function test_GetUpdateHistory() public {
        vm.prank(admin);
        engine.grantUpdateRole(admin);

        IReputationUpdateEngine.ReputationUpdate memory update1 = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 0,
            reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
            claimId: 1
        });

        IReputationUpdateEngine.ReputationUpdate memory update2 = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 0,
            reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
            claimId: 2
        });

        vm.prank(admin);
        engine.updateReputation(update1);
        vm.prank(admin);
        engine.updateReputation(update2);

        IReputationUpdateEngine.ReputationUpdateRecord[] memory history = engine.getUpdateHistory(verifier, 0, 10);
        assertEq(history.length, 2);
        assertEq(history[0].claimId, 1);
        assertEq(history[1].claimId, 2);
    }

    function test_EmptyHistoryReturnsZeroLength() public {
        IReputationUpdateEngine.ReputationUpdateRecord[] memory history = engine.getUpdateHistory(verifier, 0, 10);
        assertEq(history.length, 0);
    }

    // ============ Reputation Floor Enforcement ============

    function test_ReputationFloorEnforced() public {
        vm.prank(admin);
        engine.setMinimumReputationFloor(5);

        vm.prank(admin);
        engine.grantUpdateRole(admin);

        // Apply penalty below floor
        IReputationUpdateEngine.ReputationUpdate memory update = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 0,
            reason: IReputationUpdateEngine.UpdateReason.INCORRECT_VERIFICATION,
            claimId: 1
        });

        vm.prank(admin);
        engine.updateReputation(update);

        // Should be at floor (5), not 0
        assertEq(engine.getReputation(verifier), 5);
    }

    // ============ Reputation Cap Enforcement ============

    function test_ReputationCapEnforced() public {
        vm.startPrank(admin);
        engine.setRewardIncrement(1000);
        engine.setMaximumReputationCap(500);
        engine.grantUpdateRole(admin);
        vm.stopPrank();

        for (uint256 i = 1; i <= 3; i++) {
            IReputationUpdateEngine.ReputationUpdate memory update = IReputationUpdateEngine.ReputationUpdate({
                verifier: verifier,
                delta: 0,
                reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
                claimId: i
            });

            vm.prank(admin);
            engine.updateReputation(update);
        }

        // 3 * 1000 = 3000, but capped at 500
        assertEq(engine.getReputation(verifier), 500);
        assertEq(engine.successfulUpdates(verifier), 3);
    }

    // ============ Pausability ============

    function test_PausePreventsUpdates() public {
        vm.prank(admin);
        engine.pause();

        IReputationUpdateEngine.ReputationUpdate memory update = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 0,
            reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
            claimId: 1
        });

        vm.prank(resolver);
        vm.expectRevert();
        engine.updateReputation(update);
    }

    function test_UnpauseAllowsUpdates() public {
        vm.prank(admin);
        engine.pause();
        vm.prank(admin);
        engine.unpause();

        IReputationUpdateEngine.ReputationUpdate memory update = IReputationUpdateEngine.ReputationUpdate({
            verifier: verifier,
            delta: 0,
            reason: IReputationUpdateEngine.UpdateReason.CORRECT_VERIFICATION,
            claimId: 1
        });

        vm.prank(resolver);
        engine.updateReputation(update);

        assertEq(engine.getReputation(verifier), 10);
    }
}
