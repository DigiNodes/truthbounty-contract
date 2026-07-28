// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/treasury/BudgetRegistry.sol";
import "../../contracts/treasury/GrantAllocation.sol";
import "../../contracts/treasury/IBudgetRegistry.sol";
import "../../contracts/treasury/IGrantAllocation.sol";

contract BudgetRegistryInvariantTest is Test {
    BudgetRegistry public registry;
    GrantAllocation public grantAllocation;
    address public admin = address(0x1);
    address public manager = address(0x2);
    address public allocator = address(0x3);
    address public grantManager = address(0x4);

    bytes32 public sampleProposalRef = keccak256("proposal-ref");

    uint256 public constant MAX_BUDGET_AMOUNT = 1_000_000e18;

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

        targetContract(address(registry));
    }

    function invariant_AllocatedLeqApproved() public {
        bytes32[] memory active = registry.getActiveBudgets();
        for (uint256 i = 0; i < active.length; i++) {
            IBudgetRegistry.Budget memory budget = registry.getBudget(active[i]);
            assertLe(budget.spentAmount, budget.approvedAmount, "spent > approved");
        }
    }

    function invariant_TotalSpentLeqTotalAllocated() public {
        uint256 totalAllocated = registry.getTotalAllocated();
        uint256 totalSpent = registry.getTotalSpent();
        assertLe(totalSpent, totalAllocated, "total spent > total allocated");
    }

    function invariant_BudgetTotalsConsistent() public {
        uint256 totalSpentFromUtilisation = 0;
        uint256 totalAllocatedFromUtilisation = 0;

        for (uint256 c = 0; c < 6; c++) {
            IBudgetRegistry.BudgetCategory category = IBudgetRegistry.BudgetCategory(c);
            (uint256 allocated, uint256 spent,) = registry.getCategoryUtilisation(category);
            totalAllocatedFromUtilisation += allocated;
            totalSpentFromUtilisation += spent;
        }

        assertEq(registry.getTotalAllocated(), totalAllocatedFromUtilisation, "totalAllocated mismatch");
        assertEq(registry.getTotalSpent(), totalSpentFromUtilisation, "totalSpent mismatch");
    }

    function invariant_BudgetsHavePositiveAmounts() public {
        bytes32[] memory active = registry.getActiveBudgets();
        for (uint256 i = 0; i < active.length; i++) {
            IBudgetRegistry.Budget memory budget = registry.getBudget(active[i]);
            assertGt(budget.approvedAmount, 0, "budget approved amount is 0");
        }
    }

    function invariant_ExpiredBudgetsNotActive() public {
        bytes32[] memory active = registry.getActiveBudgets();
        for (uint256 i = 0; i < active.length; i++) {
            IBudgetRegistry.Budget memory budget = registry.getBudget(active[i]);
            if (block.timestamp >= budget.expiresAt) {
                assertTrue(
                    uint256(budget.status) == uint256(IBudgetRegistry.BudgetStatus.CLOSED) ||
                    uint256(budget.status) == uint256(IBudgetRegistry.BudgetStatus.EXPIRED),
                    "Expired budget still active"
                );
            }
        }
    }
}
