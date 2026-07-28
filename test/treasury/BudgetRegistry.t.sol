// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/treasury/BudgetRegistry.sol";
import "../../contracts/treasury/IBudgetRegistry.sol";

contract BudgetRegistryTest is Test {
    BudgetRegistry public registry;
    address public manager = address(0x1);
    address public allocator = address(0x2);
    address public unauthorised = address(0x3);

    bytes32 public sampleProposalRef = keccak256("proposal-1");

    function setUp() public {
        registry = new BudgetRegistry(address(this));
        registry.grantRole(registry.BUDGET_MANAGER_ROLE(), manager);
        registry.grantRole(registry.BUDGET_ALLOCATOR_ROLE(), allocator);
    }

    function test_CreateBudget() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(
            IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT,
            100_000e18,
            30 days,
            "Q1 Development",
            sampleProposalRef
        );
        IBudgetRegistry.Budget memory budget = registry.getBudget(budgetId);
        assertEq(uint256(budget.category), uint256(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT));
        assertEq(budget.approvedAmount, 100_000e18);
        assertEq(budget.spentAmount, 0);
        assertEq(budget.name, "Q1 Development");
        assertEq(uint256(budget.status), uint256(IBudgetRegistry.BudgetStatus.ACTIVE));
    }

    function test_CreateBudgetZeroAmount() public {
        vm.prank(manager);
        vm.expectRevert(IBudgetRegistry.ZeroAmount.selector);
        registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 0, 30 days, "Zero Budget", sampleProposalRef);
    }

    function test_CreateBudgetUnauthorised() public {
        vm.prank(unauthorised);
        vm.expectRevert();
        registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 1000e18, 30 days, "Unauthorised", sampleProposalRef);
    }

    function test_CreateBudgetEmptyName() public {
        vm.prank(manager);
        vm.expectRevert(IBudgetRegistry.BudgetNameEmpty.selector);
        registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 1000e18, 30 days, "", sampleProposalRef);
    }

    function test_CreateBudgetInvalidDuration() public {
        vm.prank(manager);
        vm.expectRevert(IBudgetRegistry.InvalidExpiration.selector);
        registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 1000e18, 12 hours, "Too Short", sampleProposalRef);
        vm.prank(manager);
        vm.expectRevert(IBudgetRegistry.InvalidExpiration.selector);
        registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 1000e18, 400 days, "Too Long", sampleProposalRef);
    }

    function test_AllocateBudget() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100_000e18, 30 days, "Dev Budget", sampleProposalRef);
        vm.prank(allocator);
        registry.allocateBudget(budgetId, 50_000e18);
        IBudgetRegistry.Budget memory budget = registry.getBudget(budgetId);
        assertEq(budget.spentAmount, 50_000e18);
    }

    function test_AllocateBudgetExceedsApproved() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100_000e18, 30 days, "Dev Budget", sampleProposalRef);
        vm.prank(allocator);
        vm.expectRevert(abi.encodeWithSelector(IBudgetRegistry.InsufficientBudget.selector, budgetId, 150_000e18, 100_000e18));
        registry.allocateBudget(budgetId, 150_000e18);
    }

    function test_AllocateBudgetUnauthorised() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100_000e18, 30 days, "Dev Budget", sampleProposalRef);
        vm.prank(unauthorised);
        vm.expectRevert();
        registry.allocateBudget(budgetId, 10_000e18);
    }

    function test_SpendFromBudget() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.ECOSYSTEM, 50_000e18, 30 days, "Ecosystem Grant", sampleProposalRef);
        vm.prank(allocator);
        bool success = registry.spendFromBudget(budgetId, 25_000e18, address(0x5), keccak256("grant-1"));
        assertTrue(success);
        IBudgetRegistry.Budget memory budget = registry.getBudget(budgetId);
        assertEq(budget.spentAmount, 25_000e18);
    }

    function test_SpendFromBudgetExceedsApproved() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.ECOSYSTEM, 10_000e18, 30 days, "Ecosystem Grant", sampleProposalRef);
        vm.prank(allocator);
        vm.expectRevert(abi.encodeWithSelector(IBudgetRegistry.InsufficientBudget.selector, budgetId, 20_000e18, 10_000e18));
        registry.spendFromBudget(budgetId, 20_000e18, address(0x5), keccak256("grant-1"));
    }

    function test_SpendFromBudgetZeroRecipient() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.ECOSYSTEM, 10_000e18, 30 days, "Ecosystem Grant", sampleProposalRef);
        vm.prank(allocator);
        vm.expectRevert(IBudgetRegistry.ZeroAddress.selector);
        registry.spendFromBudget(budgetId, 5_000e18, address(0), keccak256("grant-1"));
    }

    function test_CloseBudget() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.OPERATIONS, 10_000e18, 30 days, "Ops Budget", sampleProposalRef);
        vm.prank(manager);
        registry.closeBudget(budgetId);
        IBudgetRegistry.Budget memory budget = registry.getBudget(budgetId);
        assertEq(uint256(budget.status), uint256(IBudgetRegistry.BudgetStatus.CLOSED));
    }

    function test_AllocateClosedBudget() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.OPERATIONS, 10_000e18, 30 days, "Ops Budget", sampleProposalRef);
        vm.prank(manager);
        registry.closeBudget(budgetId);
        vm.prank(allocator);
        vm.expectRevert(abi.encodeWithSelector(IBudgetRegistry.BudgetAlreadyClosed.selector, budgetId));
        registry.allocateBudget(budgetId, 1_000e18);
    }

    function test_SetCategoryConfig() public {
        registry.setCategoryConfig(IBudgetRegistry.BudgetCategory.SECURITY, 500_000e18, 150_000e18, true);
        IBudgetRegistry.CategoryConfig memory config = registry.getCategoryConfig(IBudgetRegistry.BudgetCategory.SECURITY);
        assertEq(config.annualLimit, 500_000e18);
        assertEq(config.quarterlyLimit, 150_000e18);
        assertTrue(config.enabled);
    }

    function test_DisableCategory() public {
        registry.setCategoryConfig(IBudgetRegistry.BudgetCategory.RESEARCH, type(uint256).max, type(uint256).max, false);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IBudgetRegistry.CategoryNotEnabled.selector, IBudgetRegistry.BudgetCategory.RESEARCH));
        registry.createBudget(IBudgetRegistry.BudgetCategory.RESEARCH, 10_000e18, 30 days, "Research Budget", sampleProposalRef);
    }

    function test_AnnualLimitExceeded() public {
        registry.setCategoryConfig(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100_000e18, 100_000e18, true);
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100_000e18, 30 days, "Dev Budget", sampleProposalRef);
        vm.prank(allocator);
        registry.allocateBudget(budgetId, 100_000e18);
        vm.prank(manager);
        bytes32 budgetId2 = registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 10_000e18, 30 days, "Dev Budget 2", sampleProposalRef);
        vm.prank(allocator);
        vm.expectRevert(abi.encodeWithSelector(IBudgetRegistry.AnnualLimitExceeded.selector, IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 110_000e18, 100_000e18));
        registry.allocateBudget(budgetId2, 10_000e18);
    }

    function test_SetEmergencyReserve() public {
        registry.setEmergencyReserve(50_000e18);
        assertEq(registry.getEmergencyReserve(), 50_000e18);
    }

    function test_SetEmergencyReserveUnauthorised() public {
        vm.prank(unauthorised);
        vm.expectRevert();
        registry.setEmergencyReserve(10_000e18);
    }

    function test_BudgetCreatedEvent() public {
        bytes32 budgetId = keccak256(abi.encode(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, "Dev Budget", 100_000e18, block.timestamp, 0));
        vm.prank(manager);
        vm.expectEmit(true, true, false, true);
        emit IBudgetRegistry.BudgetCreated(budgetId, IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100_000e18, "Dev Budget");
        registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100_000e18, 30 days, "Dev Budget", sampleProposalRef);
    }

    function test_BudgetSpentEvent() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.ECOSYSTEM, 50_000e18, 30 days, "Ecosystem Grant", sampleProposalRef);
        address recipient = address(0x5);
        bytes32 ref = keccak256("grant-1");
        vm.prank(allocator);
        vm.expectEmit(true, false, true, true);
        emit IBudgetRegistry.BudgetSpent(budgetId, 25_000e18, recipient, ref);
        registry.spendFromBudget(budgetId, 25_000e18, recipient, ref);
    }

    function test_BudgetClosedEvent() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.OPERATIONS, 10_000e18, 30 days, "Ops Budget", sampleProposalRef);
        vm.prank(manager);
        vm.expectEmit(true, false, false, false);
        emit IBudgetRegistry.BudgetClosed(budgetId);
        registry.closeBudget(budgetId);
    }

    function test_GetActiveBudgets() public {
        vm.prank(manager);
        registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100_000e18, 30 days, "Budget 1", sampleProposalRef);
        vm.prank(manager);
        registry.createBudget(IBudgetRegistry.BudgetCategory.SECURITY, 50_000e18, 30 days, "Budget 2", sampleProposalRef);
        bytes32[] memory active = registry.getActiveBudgets();
        assertEq(active.length, 2);
    }

    function test_GetCategoryBudgets() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100_000e18, 30 days, "Dev Budget", sampleProposalRef);
        bytes32[] memory catBudgets = registry.getCategoryBudgets(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT);
        assertEq(catBudgets.length, 1);
        assertEq(catBudgets[0], budgetId);
    }

    function test_GetBudgetCount() public {
        assertEq(registry.getBudgetCount(), 0);
        vm.prank(manager);
        registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100_000e18, 30 days, "Budget 1", sampleProposalRef);
        assertEq(registry.getBudgetCount(), 1);
    }

    function test_GetCategoryUtilisation() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.COMMUNITY, 200_000e18, 30 days, "Community Budget", sampleProposalRef);
        vm.prank(allocator);
        registry.allocateBudget(budgetId, 80_000e18);
        (uint256 allocated, uint256 spent, uint256 remaining) = registry.getCategoryUtilisation(IBudgetRegistry.BudgetCategory.COMMUNITY);
        assertEq(allocated, 200_000e18);
        assertEq(spent, 80_000e18);
        assertEq(remaining, 120_000e18);
    }

    function test_GetTotalAllocatedAndSpent() public {
        vm.prank(manager);
        bytes32 budgetId1 = registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100_000e18, 30 days, "Dev Budget", sampleProposalRef);
        vm.prank(manager);
        registry.createBudget(IBudgetRegistry.BudgetCategory.SECURITY, 50_000e18, 30 days, "Security Budget", sampleProposalRef);
        assertEq(registry.getTotalAllocated(), 150_000e18);
        vm.prank(allocator);
        registry.allocateBudget(budgetId1, 30_000e18);
        assertEq(registry.getTotalSpent(), 30_000e18);
    }

    function test_GetGovernanceExpenditure() public {
        (uint256 totalAllocated, uint256 totalSpent) = registry.getGovernanceExpenditure();
        assertEq(totalAllocated, 0);
        assertEq(totalSpent, 0);
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100_000e18, 30 days, "Dev Budget", sampleProposalRef);
        vm.prank(allocator);
        registry.allocateBudget(budgetId, 40_000e18);
        (totalAllocated, totalSpent) = registry.getGovernanceExpenditure();
        assertEq(totalAllocated, 100_000e18);
        assertEq(totalSpent, 40_000e18);
    }

    function test_PausePreventsActions() public {
        registry.pause();
        assertTrue(registry.paused());
        vm.prank(manager);
        vm.expectRevert();
        registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100e18, 30 days, "Paused Budget", sampleProposalRef);
    }

    function test_UnpauseResumesActions() public {
        registry.pause();
        assertTrue(registry.paused());
        registry.unpause();
        assertFalse(registry.paused());
        vm.prank(manager);
        registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100e18, 30 days, "Unpaused Budget", sampleProposalRef);
    }

    function test_UnauthorisedAllocationRejected() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 1000e18, 30 days, "Test", sampleProposalRef);
        vm.prank(unauthorised);
        vm.expectRevert();
        registry.allocateBudget(budgetId, 100e18);
    }

    function test_OverspendingImpossible() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 100e18, 30 days, "Small Budget", sampleProposalRef);
        vm.prank(allocator);
        registry.allocateBudget(budgetId, 100e18);
        vm.prank(allocator);
        vm.expectRevert();
        registry.allocateBudget(budgetId, 1);
    }

    function test_BudgetExpires() public {
        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT, 1000e18, 1 days, "Quick Budget", sampleProposalRef);
        vm.warp(block.timestamp + 2 days);
        vm.prank(allocator);
        vm.expectRevert(abi.encodeWithSelector(IBudgetRegistry.BudgetExpiredError.selector, budgetId));
        registry.allocateBudget(budgetId, 100e18);
    }

    function test_GetBudgetNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IBudgetRegistry.BudgetNotFound.selector, keccak256("nonexistent")));
        registry.getBudget(keccak256("nonexistent"));
    }
}
