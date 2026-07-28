// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/bootstrap/BootstrapController.sol";

contract BootstrapFuzzTest is Test {
    BootstrapController public controller;
    address public admin = address(0x1);

    bytes32 constant MODULE_GOV = keccak256("GOVERNANCE");
    bytes32 constant MODULE_TOKEN = keccak256("TOKEN");

    event ModuleRegistered(bytes32 indexed moduleId, address indexed module, string name);

    function setUp() public {
        vm.prank(admin);
        controller = new BootstrapController(admin, address(0));
    }

    function testFuzz_RegisterModules_RandomAddresses(
        address[] calldata addresses
    ) public {
        vm.assume(addresses.length > 0 && addresses.length <= 10);
        for (uint256 i = 0; i < addresses.length; i++) {
            vm.assume(addresses[i] != address(0));
        }

        bytes32[] memory ids = new bytes32[](addresses.length);
        string[] memory names = new string[](addresses.length);

        for (uint256 i = 0; i < addresses.length; i++) {
            ids[i] = keccak256(abi.encode(i));
            names[i] = string(abi.encode(i));
        }

        vm.prank(admin);
        controller.registerModules(ids, addresses, names);

        assertEq(controller.getModuleCount(), addresses.length);

        for (uint256 i = 0; i < addresses.length; i++) {
            address stored = controller.getModuleAddress(ids[i]);
            assertEq(stored, addresses[i]);
        }
    }

    function testFuzz_RegisterModule_RejectsDuplicate(
        bytes32 moduleId,
        address moduleAddress
    ) public {
        vm.assume(moduleAddress != address(0));

        vm.prank(admin);
        controller.registerModule(moduleId, moduleAddress, "test");

        vm.expectRevert(BootstrapController.ModuleAlreadyRegistered.selector);
        vm.prank(admin);
        controller.registerModule(moduleId, moduleAddress, "test");
    }

    function testFuzz_RegisterModule_RejectsZeroAddress(
        bytes32 moduleId
    ) public {
        vm.expectRevert(BootstrapController.InvalidAddress.selector);
        vm.prank(admin);
        controller.registerModule(moduleId, address(0), "test");
    }

    function testFuzz_RegisterModule_RejectsEmptyName(
        bytes32 moduleId,
        address moduleAddress
    ) public {
        vm.assume(moduleAddress != address(0));

        vm.expectRevert(BootstrapController.EmptyModuleName.selector);
        vm.prank(admin);
        controller.registerModule(moduleId, moduleAddress, "");
    }

    function testFuzz_Bootstrap_RejectsDuplicate(
        address deployer
    ) public {
        vm.assume(deployer != address(0));

        vm.prank(admin);
        controller.grantRole(controller.DEPLOYER_ROLE(), deployer);

        bytes32[] memory ids = new bytes32[](1);
        address[] memory addrs = new address[](1);
        string[] memory names = new string[](1);
        ids[0] = keccak256("GOVERNANCE");
        addrs[0] = address(0x100);
        names[0] = "Governance";

        vm.prank(admin);
        controller.registerModules(ids, addrs, names);

        vm.expectRevert(BootstrapController.ModuleNotRegistered.selector);
        vm.prank(deployer);
        controller.bootstrap();
    }

    function testFuzz_AccessControl_RejectsNonAdmin(
        address caller,
        bytes32 moduleId,
        address moduleAddress
    ) public {
        vm.assume(caller != address(0) && caller != admin);
        vm.assume(moduleAddress != address(0));

        vm.expectRevert();
        vm.prank(caller);
        controller.registerModule(moduleId, moduleAddress, "test");
    }

    function testFuzz_ModuleEnumeration_Consistent(
        uint256 count
    ) public {
        count = bound(count, 1, 8);

        bytes32[] memory ids = new bytes32[](count);
        address[] memory addrs = new address[](count);
        string[] memory names = new string[](count);

        for (uint256 i = 0; i < count; i++) {
            ids[i] = keccak256(abi.encode(i));
            addrs[i] = address(uint160(0x100 + i));
            names[i] = string(abi.encode(i));
        }

        vm.prank(admin);
        controller.registerModules(ids, addrs, names);

        assertEq(controller.getModuleCount(), count);

        for (uint256 i = 0; i < count; i++) {
            (bytes32 storedId, BootstrapController.ModuleInfo memory info) = controller.getModuleAt(i);
            assertEq(storedId, ids[i]);
            assertEq(info.addr, addrs[i]);
            assertTrue(info.registered);
        }
    }

    function testFuzz_GetModuleAt_RevertsOutOfBounds(
        uint256 index
    ) public {
        vm.assume(index > 0);

        controller.getModuleAt(0);
    }
}