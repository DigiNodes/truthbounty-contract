// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/governance/GovernanceOwnable.sol";

contract GovernanceOwnableMock is GovernanceOwnable {
    uint256 public nextValue;

    constructor(address admin, address emergencyAdmin_) {
        _initializeGovernance(address(0), admin, emergencyAdmin_);
    }

    function setValue(uint256 newValue) external onlyGovernanceOrAdmin {
        nextValue = newValue;
    }
}

contract GovernanceOwnableTest is Test {
    GovernanceOwnableMock public govOwnable;
    address public admin = address(0x1);
    address public emergencyAdmin_ = address(0x2);

    function setUp() public {
        govOwnable = new GovernanceOwnableMock(admin, emergencyAdmin_);
    }

    function test_Gap_SlotsReserved() public {
        uint256 gapStartSlot = 4;

        for (uint256 i = 0; i < 50; i++) {
            bytes32 slotValue = vm.load(address(govOwnable), bytes32(uint256(gapStartSlot + i)));
            assertEq(uint256(slotValue), 0, "gap slot should be uninitialized");
        }
    }

    function test_Gap_StateVariablesAccessible() public {
        assertEq(govOwnable.governanceController(), address(0));
        assertEq(govOwnable.governanceEnabled(), true);
        assertEq(govOwnable.emergencyAdmin(), emergencyAdmin_);
    }

    function test_Gap_DoesNotBreakAdminFunctions() public {
        vm.prank(admin);
        govOwnable.setValue(42);
        assertEq(govOwnable.nextValue(), 42);
    }

    function test_Gap_DoesNotBreakPause() public {
        vm.prank(emergencyAdmin_);
        govOwnable.emergencyPause();
        assertTrue(govOwnable.paused());

        vm.prank(emergencyAdmin_);
        govOwnable.emergencyUnpause();
        assertFalse(govOwnable.paused());
    }

    function test_Gap_DoesNotBreakGovernanceController() public {
        vm.prank(admin);
        govOwnable.setGovernanceController(address(0x3));
        assertEq(govOwnable.governanceController(), address(0x3));
    }
}
