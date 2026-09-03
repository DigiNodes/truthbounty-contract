// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/bootstrap/BootstrapController.sol";

contract BootstrapScenarioTests is Test {
    BootstrapController public controller;
    address public admin = address(0x1);

    bytes32 constant MODULE_GOV = keccak256("GOVERNANCE");
    bytes32 constant MODULE_TOKEN = keccak256("TOKEN");

    function setUp() public {
        vm.prank(admin);
        controller = new BootstrapController(admin, address(0));

        vm.prank(admin);
        controller.registerModule(MODULE_GOV, address(0x100), "Governance");
        vm.prank(admin);
        controller.registerModule(MODULE_TOKEN, address(0x101), "Token");
    }

    function test_NotBootstrappedByDefault() public {
        assertFalse(controller.isBootstrapped());
    }

    function test_ModuleCountMatchesRegistry() public {
        assertEq(controller.getModuleCount(), 2);
    }

    function test_BootstrapConfigDefaults() public {
        BootstrapController.BootstrapConfig memory cfg = controller.getBootstrapConfig();
        assertEq(cfg.verificationWindowDuration, 0);
        assertEq(cfg.minStakeAmount, 0);
    }

    function test_ModulesNotInitializedBeforeBootstrap() public {
        assertFalse(controller.isModuleInitialized(MODULE_GOV));
        assertFalse(controller.isModuleInitialized(MODULE_TOKEN));
    }

    function test_ModuleAddressesStored() public {
        assertEq(controller.getModuleAddress(MODULE_GOV), address(0x100));
        assertEq(controller.getModuleAddress(MODULE_TOKEN), address(0x101));
    }

    function test_FullyInitializedFalseBeforeBootstrap() public {
        assertFalse(controller.isFullyInitialized());
    }

    function test_BootstrapStateDefaults() public {
        BootstrapController.BootstrapState memory state = controller.getBootstrapState();
        assertFalse(state.bootstrapped);
        assertEq(state.bootstrapTimestamp, 0);
        assertEq(state.blockNumber, 0);
    }

    function test_AdminHasDefaultAdminRole() public {
        assertTrue(controller.hasRole(controller.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_ModuleEnumerationWorks() public {
        uint256 count = controller.getModuleCount();
        for (uint256 i = 0; i < count; i++) {
            (bytes32 id, BootstrapController.ModuleInfo memory info) = controller.getModuleAt(i);
            assertTrue(info.registered);
            assertEq(id, info.registered ? id : bytes32(0));
        }
    }
}