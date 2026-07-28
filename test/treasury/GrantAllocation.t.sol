// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/treasury/BudgetRegistry.sol";
import "../../contracts/treasury/GrantAllocation.sol";
import "../../contracts/treasury/IBudgetRegistry.sol";
import "../../contracts/treasury/IGrantAllocation.sol";

contract GrantAllocationTest is Test {
    BudgetRegistry public registry;
    GrantAllocation public grantAllocation;
    address public manager = address(0x1);
    address public approver = address(0x2);
    address public milestoneVerifier = address(0x3);
    address public grantee = address(0x4);
    address public unauthorised = address(0x5);

    bytes32 public budgetId;
    bytes32 public sampleProposalRef = keccak256("proposal-1");

    function setUp() public {
        registry = new BudgetRegistry(address(this));
        registry.grantRole(registry.BUDGET_MANAGER_ROLE(), manager);

        grantAllocation = new GrantAllocation(address(registry), address(this));
        grantAllocation.grantRole(grantAllocation.GRANT_MANAGER_ROLE(), manager);
        grantAllocation.grantRole(grantAllocation.GRANT_APPROVER_ROLE(), approver);
        grantAllocation.grantRole(grantAllocation.MILESTONE_VERIFIER_ROLE(), milestoneVerifier);

        registry.grantRole(registry.BUDGET_ALLOCATOR_ROLE(), address(grantAllocation));

        vm.prank(manager);
        budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.ECOSYSTEM, 100_000e18, 180 days, "Ecosystem Grants", sampleProposalRef);
    }

    function test_ProposeGrant() public {
        uint256[] memory milestones = new uint256[](3);
        milestones[0] = 30; milestones[1] = 30; milestones[2] = 40;

        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 50_000e18, budgetId, "Ecosystem Integration Grant", milestones);

        IGrantAllocation.Grant memory grant = grantAllocation.getGrant(grantId);
        assertEq(grant.recipient, grantee);
        assertEq(grant.totalAmount, 50_000e18);
        assertEq(grant.budgetId, budgetId);
        assertEq(uint256(grant.status), uint256(IGrantAllocation.GrantStatus.PROPOSED));
        assertEq(grant.milestoneCount, 3);
    }

    function test_ProposeGrantInvalidRecipient() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        vm.expectRevert(IGrantAllocation.InvalidRecipient.selector);
        grantAllocation.proposeGrant(address(0), 10_000e18, budgetId, "Test", milestones);
    }

    function test_ProposeGrantZeroAmount() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        vm.expectRevert(IGrantAllocation.ZeroAmount.selector);
        grantAllocation.proposeGrant(grantee, 0, budgetId, "Test", milestones);
    }

    function test_ProposeGrantInvalidMilestones() public {
        uint256[] memory milestones = new uint256[](0);
        vm.prank(manager);
        vm.expectRevert(IGrantAllocation.InvalidMilestoneConfig.selector);
        grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Test", milestones);
    }

    function test_ProposeGrantMilestoneOverflow() public {
        uint256[] memory milestones = new uint256[](2);
        milestones[0] = 60; milestones[1] = 50;
        vm.prank(manager);
        vm.expectRevert(IGrantAllocation.InvalidMilestoneConfig.selector);
        grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Test", milestones);
    }

    function test_ProposeGrantExceedsBudget() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        vm.expectRevert();
        grantAllocation.proposeGrant(grantee, 200_000e18, budgetId, "Over Limit", milestones);
    }

    function test_ProposeGrantUnauthorised() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(unauthorised);
        vm.expectRevert();
        grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Test", milestones);
    }

    function test_ApproveGrant() public {
        uint256[] memory milestones = new uint256[](2);
        milestones[0] = 50; milestones[1] = 50;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 30_000e18, budgetId, "Dev Grant", milestones);
        vm.prank(approver);
        grantAllocation.approveGrant(grantId);
        IGrantAllocation.Grant memory grant = grantAllocation.getGrant(grantId);
        assertEq(uint256(grant.status), uint256(IGrantAllocation.GrantStatus.APPROVED));
        assertTrue(grant.approvedAt > 0);
    }

    function test_ApproveGrantUnauthorised() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Test", milestones);
        vm.prank(unauthorised);
        vm.expectRevert();
        grantAllocation.approveGrant(grantId);
    }

    function test_ApproveAlreadyApprovedGrant() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Test", milestones);
        vm.prank(approver);
        grantAllocation.approveGrant(grantId);
        vm.prank(approver);
        vm.expectRevert(abi.encodeWithSelector(IGrantAllocation.GrantNotInState.selector, grantId, IGrantAllocation.GrantStatus.PROPOSED));
        grantAllocation.approveGrant(grantId);
    }

    function test_CompleteMilestone() public {
        uint256[] memory milestones = new uint256[](3);
        milestones[0] = 25; milestones[1] = 25; milestones[2] = 50;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 40_000e18, budgetId, "Milestone Grant", milestones);
        vm.prank(approver);
        grantAllocation.approveGrant(grantId);
        vm.prank(milestoneVerifier);
        grantAllocation.completeMilestone(grantId, 0);
        IGrantAllocation.Milestone[] memory ms = grantAllocation.getGrantMilestones(grantId);
        assertTrue(ms[0].completed);
        assertTrue(ms[0].completedAt > 0);
        IGrantAllocation.Grant memory grant = grantAllocation.getGrant(grantId);
        assertEq(grant.milestonesCompleted, 1);
    }

    function test_CompleteMilestoneAlreadyCompleted() public {
        uint256[] memory milestones = new uint256[](2);
        milestones[0] = 50; milestones[1] = 50;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 20_000e18, budgetId, "Test", milestones);
        vm.prank(approver);
        grantAllocation.approveGrant(grantId);
        vm.prank(milestoneVerifier);
        grantAllocation.completeMilestone(grantId, 0);
        vm.prank(milestoneVerifier);
        vm.expectRevert(abi.encodeWithSelector(IGrantAllocation.MilestoneAlreadyCompleted.selector, 0));
        grantAllocation.completeMilestone(grantId, 0);
    }

    function test_CompleteMilestoneInvalidIndex() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Test", milestones);
        vm.prank(approver);
        grantAllocation.approveGrant(grantId);
        vm.prank(milestoneVerifier);
        vm.expectRevert(IGrantAllocation.InvalidMilestoneConfig.selector);
        grantAllocation.completeMilestone(grantId, 5);
    }

    function test_AllMilestonesCompleteTriggersCompleted() public {
        uint256[] memory milestones = new uint256[](2);
        milestones[0] = 50; milestones[1] = 50;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 20_000e18, budgetId, "Test", milestones);
        vm.prank(approver);
        grantAllocation.approveGrant(grantId);
        vm.prank(milestoneVerifier);
        grantAllocation.completeMilestone(grantId, 0);
        vm.prank(milestoneVerifier);
        grantAllocation.completeMilestone(grantId, 1);
        IGrantAllocation.Grant memory grant = grantAllocation.getGrant(grantId);
        assertEq(grant.milestonesCompleted, 2);
        vm.prank(manager);
        vm.expectEmit(true, true, false, false);
        emit IGrantAllocation.GrantCompleted(grantId, grantee, 20_000e18);
        uint256 payment = grantAllocation.releasePayment(grantId);
        assertEq(payment, 20_000e18);
        grant = grantAllocation.getGrant(grantId);
        assertEq(uint256(grant.status), uint256(IGrantAllocation.GrantStatus.COMPLETED));
    }

    function test_ReleasePayment() public {
        uint256[] memory milestones = new uint256[](2);
        milestones[0] = 50; milestones[1] = 50;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 20_000e18, budgetId, "Payment Grant", milestones);
        vm.prank(approver);
        grantAllocation.approveGrant(grantId);
        vm.prank(milestoneVerifier);
        grantAllocation.completeMilestone(grantId, 0);
        vm.prank(manager);
        uint256 payment = grantAllocation.releasePayment(grantId);
        assertEq(payment, 10_000e18);
    }

    function test_ReleasePaymentFullAmount() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 15_000e18, budgetId, "Full Grant", milestones);
        vm.prank(approver);
        grantAllocation.approveGrant(grantId);
        vm.prank(milestoneVerifier);
        grantAllocation.completeMilestone(grantId, 0);
        vm.prank(manager);
        uint256 payment = grantAllocation.releasePayment(grantId);
        assertEq(payment, 15_000e18);
        IGrantAllocation.Grant memory grant = grantAllocation.getGrant(grantId);
        assertEq(uint256(grant.status), uint256(IGrantAllocation.GrantStatus.COMPLETED));
        assertEq(grant.amountPaid, 15_000e18);
    }

    function test_ReleasePaymentBeforeProposed() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Test", milestones);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IGrantAllocation.GrantNotInState.selector, grantId, IGrantAllocation.GrantStatus.APPROVED));
        grantAllocation.releasePayment(grantId);
    }

    function test_ReleasePaymentNoMilestonesCompleted() public {
        uint256[] memory milestones = new uint256[](2);
        milestones[0] = 50; milestones[1] = 50;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Test", milestones);
        vm.prank(approver);
        grantAllocation.approveGrant(grantId);
        vm.prank(manager);
        vm.expectRevert("No payment available");
        grantAllocation.releasePayment(grantId);
    }

    function test_CancelGrant() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Test", milestones);
        vm.prank(manager);
        vm.expectEmit(true, false, false, false);
        emit IGrantAllocation.GrantCancelled(grantId, "Budget reallocation");
        grantAllocation.cancelGrant(grantId, "Budget reallocation");
        IGrantAllocation.Grant memory grant = grantAllocation.getGrant(grantId);
        assertEq(uint256(grant.status), uint256(IGrantAllocation.GrantStatus.CANCELLED));
    }

    function test_CancelCompletedGrant() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Test", milestones);
        vm.prank(approver);
        grantAllocation.approveGrant(grantId);
        vm.prank(milestoneVerifier);
        grantAllocation.completeMilestone(grantId, 0);
        vm.prank(manager);
        grantAllocation.releasePayment(grantId);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IGrantAllocation.GrantAlreadyCompleted.selector, grantId));
        grantAllocation.cancelGrant(grantId, "Too late");
    }

    function test_GrantProposedEvent() public {
        uint256[] memory milestones = new uint256[](2);
        milestones[0] = 50; milestones[1] = 50;
        bytes32 grantId = keccak256(abi.encode(grantee, 30_000e18, budgetId, block.timestamp, 0));
        vm.prank(manager);
        vm.expectEmit(true, true, true, true);
        emit IGrantAllocation.GrantProposed(grantId, grantee, 30_000e18, budgetId);
        grantAllocation.proposeGrant(grantee, 30_000e18, budgetId, "Event Grant", milestones);
    }

    function test_GrantApprovedEvent() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Test", milestones);
        vm.prank(approver);
        vm.expectEmit(true, true, true, false);
        emit IGrantAllocation.GrantApproved(grantId, grantee, 10_000e18);
        grantAllocation.approveGrant(grantId);
    }

    function test_GrantPaymentEvent() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Test", milestones);
        vm.prank(approver);
        grantAllocation.approveGrant(grantId);
        vm.prank(milestoneVerifier);
        grantAllocation.completeMilestone(grantId, 0);
        vm.prank(manager);
        vm.expectEmit(true, true, true, false);
        emit IGrantAllocation.GrantPayment(grantId, grantee, 10_000e18);
        uint256 payment = grantAllocation.releasePayment(grantId);
        assertEq(payment, 10_000e18);
    }

    function test_GetGrantsForBudget() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Grant 1", milestones);
        bytes32[] memory grants = grantAllocation.getGrantsForBudget(budgetId);
        assertEq(grants.length, 1);
        assertEq(grants[0], grantId);
    }

    function test_GetGrantsForRecipient() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        bytes32 grantId = grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Grant 1", milestones);
        bytes32[] memory grants = grantAllocation.getGrantsForRecipient(grantee);
        assertEq(grants.length, 1);
        assertEq(grants[0], grantId);
    }

    function test_GetGrantCount() public {
        assertEq(grantAllocation.getGrantCount(), 0);
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Grant 1", milestones);
        assertEq(grantAllocation.getGrantCount(), 1);
    }

    function test_UnauthorisedGrantProposal() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(unauthorised);
        vm.expectRevert();
        grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Hack", milestones);
    }

    function test_GrantCannotExceedBudget() public {
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        vm.expectRevert();
        grantAllocation.proposeGrant(grantee, 200_000e18, budgetId, "Overflow", milestones);
    }

    function test_PausePreventsProposals() public {
        grantAllocation.pause();
        assertTrue(grantAllocation.paused());
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        vm.expectRevert();
        grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Paused", milestones);
    }

    function test_UnpauseResumesProposals() public {
        grantAllocation.pause();
        grantAllocation.unpause();
        uint256[] memory milestones = new uint256[](1);
        milestones[0] = 100;
        vm.prank(manager);
        grantAllocation.proposeGrant(grantee, 10_000e18, budgetId, "Resumed", milestones);
    }
}
