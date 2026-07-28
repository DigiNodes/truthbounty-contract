// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/treasury/BudgetRegistry.sol";
import "../../contracts/treasury/GrantAllocation.sol";
import "../../contracts/treasury/IBudgetRegistry.sol";
import "../../contracts/treasury/IGrantAllocation.sol";

contract BudgetRegistryFuzzTest is Test {
    BudgetRegistry public registry;
    GrantAllocation public grantAllocation;
    address public admin = address(0x1);
    address public manager = address(0x2);
    address public allocator = address(0x3);
    address public grantManager = address(0x4);

    bytes32 public sampleProposalRef = keccak256("proposal-ref");

    function setUp() public {
        registry = new BudgetRegistry(admin);
        grantAllocation = new GrantAllocation(address(registry), admin);

        vm.prank(admin);
        registry.grantRole(registry.BUDGET_MANAGER_ROLE(), manager);
        vm.prank(admin);
        registry.grantRole(registry.BUDGET_ALLOCATOR_ROLE(), allocator);
        vm.prank(admin);
        registry.grantRole(registry.BUDGET_ALLOCATOR_ROLE(), address(grantAllocation));

        vm.prank(admin);
        grantAllocation.grantRole(grantAllocation.GRANT_MANAGER_ROLE(), grantManager);
        vm.prank(admin);
        grantAllocation.grantRole(grantAllocation.GRANT_APPROVER_ROLE(), grantManager);
        vm.prank(admin);
        grantAllocation.grantRole(grantAllocation.MILESTONE_VERIFIER_ROLE(), grantManager);
    }

    function testFuzz_BudgetCreation(uint256 amount, uint256 duration) public {
        amount = bound(amount, 1, 1_000_000_000e18);
        duration = bound(duration, 1 days, 365 days);

        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(
            IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT,
            amount,
            duration,
            "Fuzz Budget",
            sampleProposalRef
        );

        IBudgetRegistry.Budget memory budget = registry.getBudget(budgetId);
        assertEq(budget.approvedAmount, amount);
        assertEq(budget.spentAmount, 0);
        assertEq(uint256(budget.status), uint256(IBudgetRegistry.BudgetStatus.ACTIVE));
    }

    function testFuzz_BudgetAllocation(uint256 approved, uint256 allocated) public {
        approved = bound(approved, 1e18, 1_000_000e18);
        allocated = bound(allocated, 0, approved);

        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(
            IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT,
            approved,
            30 days,
            "Fuzz Alloc",
            sampleProposalRef
        );

        if (allocated > 0) {
            vm.prank(allocator);
            registry.allocateBudget(budgetId, allocated);

            IBudgetRegistry.Budget memory budget = registry.getBudget(budgetId);
            assertEq(budget.spentAmount, allocated);
            assertTrue(budget.spentAmount <= budget.approvedAmount);
        }
    }

    function testFuzz_BudgetSpending(uint256 approved, uint256 spent1, uint256 spent2) public {
        approved = bound(approved, 2e18, 1_000_000e18);
        spent1 = bound(spent1, 0, approved / 2);
        spent2 = bound(spent2, 0, approved - spent1);

        vm.prank(manager);
        bytes32 budgetId = registry.createBudget(
            IBudgetRegistry.BudgetCategory.ECOSYSTEM,
            approved,
            30 days,
            "Fuzz Spend",
            sampleProposalRef
        );

        if (spent1 > 0) {
            vm.prank(allocator);
            registry.spendFromBudget(budgetId, spent1, address(0x99), keccak256("spend1"));
        }

        if (spent2 > 0) {
            vm.prank(allocator);
            registry.spendFromBudget(budgetId, spent2, address(0x99), keccak256("spend2"));
        }

        IBudgetRegistry.Budget memory budget = registry.getBudget(budgetId);
        assertEq(budget.spentAmount, spent1 + spent2);
        assertTrue(budget.spentAmount <= budget.approvedAmount);
    }

    function testFuzz_GrantLifecycle(
        uint256 budgetAmount,
        uint256 grantAmount,
        uint256 milestone1Pct,
        uint256 milestone2Pct
    ) public {
        budgetAmount = bound(budgetAmount, 100e18, 1_000_000e18);
        grantAmount = bound(grantAmount, 1e18, budgetAmount);

        milestone1Pct = bound(milestone1Pct, 1, 99);
        milestone2Pct = 100 - milestone1Pct;

        vm.prank(manager);
        bytes32 bId = registry.createBudget(
            IBudgetRegistry.BudgetCategory.ECOSYSTEM,
            budgetAmount,
            180 days,
            "Fuzz Grant Budget",
            sampleProposalRef
        );

        uint256[] memory milestones = new uint256[](2);
        milestones[0] = milestone1Pct;
        milestones[1] = milestone2Pct;

        address recipient = address(0xAA);

        vm.prank(grantManager);
        bytes32 grantId = grantAllocation.proposeGrant(recipient, grantAmount, bId, "Fuzz Grant", milestones);

        IGrantAllocation.Grant memory grant = grantAllocation.getGrant(grantId);
        assertEq(grant.status, IGrantAllocation.GrantStatus.PROPOSED);
        assertEq(grant.totalAmount, grantAmount);
        assertTrue(grant.amountPaid <= grant.totalAmount);

        vm.prank(grantManager);
        grantAllocation.approveGrant(grantId);
        assertEq(uint256(grantAllocation.getGrant(grantId).status), uint256(IGrantAllocation.GrantStatus.APPROVED));

        vm.prank(grantManager);
        grantAllocation.completeMilestone(grantId, 0);

        vm.prank(grantManager);
        grantAllocation.completeMilestone(grantId, 1);

        vm.prank(grantManager);
        uint256 payment = grantAllocation.releasePayment(grantId);

        assertEq(payment, grantAmount);
        assertEq(grantAllocation.getGrant(grantId).amountPaid, grantAmount);
    }

    function testFuzz_DeterministicAccounting(
        uint256 amount1,
        uint256 amount2,
        uint256 timeSkip
    ) public {
        amount1 = bound(amount1, 1e18, 500_000e18);
        amount2 = bound(amount2, 1e18, 500_000e18);
        timeSkip = bound(timeSkip, 0, 30 days);

        vm.prank(manager);
        bytes32 bId1 = registry.createBudget(
            IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT,
            amount1,
            60 days,
            "Acc1",
            sampleProposalRef
        );

        vm.prank(manager);
        bytes32 bId2 = registry.createBudget(
            IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT,
            amount2,
            60 days,
            "Acc2",
            sampleProposalRef
        );

        vm.warp(block.timestamp + timeSkip);

        uint256 totalAllocated1 = registry.getTotalAllocated();
        assertEq(totalAllocated1, amount1 + amount2);

        vm.prank(allocator);
        registry.allocateBudget(bId1, amount1);

        (uint256 allocated, uint256 spent, uint256 remaining) = registry.getCategoryUtilisation(IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT);
        assertEq(allocated, amount1 + amount2);
        assertEq(spent, amount1);
        assertEq(remaining, amount2);
    }

    function testFuzz_MultipleCategories(
        uint256 devAmount,
        uint256 secAmount,
        uint256 ecoAmount
    ) public {
        devAmount = bound(devAmount, 1e18, 100_000e18);
        secAmount = bound(secAmount, 1e18, 100_000e18);
        ecoAmount = bound(ecoAmount, 1e18, 100_000e18);

        vm.prank(manager);
        registry.createBudget(
            IBudgetRegistry.BudgetCategory.PROTOCOL_DEVELOPMENT,
            devAmount,
            30 days,
            "Dev",
            sampleProposalRef
        );
        vm.prank(manager);
        registry.createBudget(
            IBudgetRegistry.BudgetCategory.SECURITY,
            secAmount,
            30 days,
            "Sec",
            sampleProposalRef
        );
        vm.prank(manager);
        registry.createBudget(
            IBudgetRegistry.BudgetCategory.ECOSYSTEM,
            ecoAmount,
            30 days,
            "Eco",
            sampleProposalRef
        );

        assertEq(registry.getBudgetCount(), 3);
        assertEq(registry.getTotalAllocated(), devAmount + secAmount + ecoAmount);

        bytes32[] memory active = registry.getActiveBudgets();
        assertEq(active.length, 3);
    }
}
