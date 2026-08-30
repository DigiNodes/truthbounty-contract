// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProtocolExecutionBounds} from "../contracts/performance/ProtocolExecutionBounds.sol";
import {GasBudgetRegistry} from "../contracts/performance/GasBudgetRegistry.sol";
import {PullSettlementLedger} from "../contracts/performance/PullSettlementLedger.sol";
import {LoopBoundsCatalog} from "../contracts/performance/LoopBoundsCatalog.sol";
import {ICriticalPathGasBudgets} from "../contracts/performance/ICriticalPathGasBudgets.sol";
import {MockERC20} from "../contracts/MockERC20.sol";
import {HostileTokenRecipient, HostileERC20} from "../contracts/mocks/HostileTokenRecipient.sol";

contract GasBoundedExecutionTest is Test {
    GasBudgetRegistry internal budgets;
    PullSettlementLedger internal ledger;
    MockERC20 internal token;
    LoopBoundsCatalog internal catalog;

    address internal userA = address(0xA);
    address internal userB = address(0xB);

    function setUp() public {
        budgets = new GasBudgetRegistry(address(this));
        token = new MockERC20("Test", "TST");
        ledger = new PullSettlementLedger(address(this), token);
        catalog = new LoopBoundsCatalog();
        token.mint(address(ledger), 1_000_000 ether);
    }

    function test_MaxSettlementBatchBoundEnforced() public {
        address[] memory beneficiaries = new address[](ProtocolExecutionBounds.MAX_SETTLEMENT_BATCH_SIZE + 1);
        uint256[] memory amounts = new uint256[](ProtocolExecutionBounds.MAX_SETTLEMENT_BATCH_SIZE + 1);
        for (uint256 i = 0; i < beneficiaries.length; ++i) {
            beneficiaries[i] = address(uint160(0x1000 + i));
            amounts[i] = 1 ether;
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                PullSettlementLedger.BatchTooLarge.selector,
                beneficiaries.length,
                ProtocolExecutionBounds.MAX_SETTLEMENT_BATCH_SIZE
            )
        );
        ledger.creditBatch(beneficiaries, amounts, bytes32("batch"));
    }

    function test_HostileRecipientDoesNotBlockOtherWithdrawals() public {
        HostileERC20 hostileToken = new HostileERC20();
        PullSettlementLedger hostileLedger = new PullSettlementLedger(address(this), IERC20(address(hostileToken)));
        hostileToken.mint(address(hostileLedger), 100 ether);

        HostileTokenRecipient hostile = new HostileTokenRecipient();
        hostileLedger.credit(address(hostile), 5 ether, bytes32("h"));
        hostileLedger.credit(userB, 5 ether, bytes32("u"));

        vm.prank(userB);
        hostileLedger.withdraw(5 ether);
        assertEq(hostileToken.balanceOf(userB), 5 ether);

        vm.prank(address(hostile));
        vm.expectRevert();
        hostileLedger.withdraw(5 ether);
    }

    function test_PullCreditDoesNotTransferTokens() public {
        ledger.credit(userA, 25 ether, bytes32("ref"));
        assertEq(token.balanceOf(address(ledger)), 1_000_000 ether);
        assertEq(ledger.availableBalance(userA), 25 ether);
    }

    function test_GasBudgetsSeededForAllCriticalPaths() public view {
        assertEq(budgets.budgetCount(), 9);
        for (uint256 i = 0; i < 9; ++i) {
            (uint256 maxGas,) = budgets.getBudget(ICriticalPathGasBudgets.Operation(i));
            assertGt(maxGas, 0);
            assertLe(maxGas, ProtocolExecutionBounds.RECOMMENDED_TX_GAS_CEILING);
        }
    }

    function test_LoopCatalogDocumentsBounds() public view {
        assertEq(catalog.catalogSize(), 12);
        LoopBoundsCatalog.LoopBound memory first = catalog.getLoopBound(0);
        assertEq(first.maxIterations, ProtocolExecutionBounds.MAX_VERIFIERS_PER_CLAIM);
    }

    function test_WithdrawalGasWithinBudget() public {
        ledger.credit(userA, 1 ether, bytes32("gas"));
        (uint256 budget,) = budgets.getBudget(ICriticalPathGasBudgets.Operation.WITHDRAWAL);

        vm.prank(userA);
        uint256 gasBefore = gasleft();
        ledger.withdraw(1 ether);
        uint256 gasUsed = gasBefore - gasleft();
        assertLe(gasUsed, budget);
    }

    function test_CreditBatchAtMaxBoundSucceeds() public {
        uint256 max = ProtocolExecutionBounds.MAX_SETTLEMENT_BATCH_SIZE;
        address[] memory beneficiaries = new address[](max);
        uint256[] memory amounts = new uint256[](max);
        for (uint256 i = 0; i < max; ++i) {
            beneficiaries[i] = address(uint160(0x2000 + i));
            amounts[i] = 1;
        }
        ledger.creditBatch(beneficiaries, amounts, bytes32("max"));
        assertEq(ledger.availableBalance(beneficiaries[0]), 1);
    }
}
