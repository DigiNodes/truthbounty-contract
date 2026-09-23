// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../contracts/upgrade/ProtocolUpgradeable.sol";

contract ProtocolUpgradeableHarness is ProtocolUpgradeable {
    uint256 public value;

    function initialize(
        address admin,
        address upgradeController,
        address governanceController,
        uint256 initialValue
    ) external initializer {
        _initializeProtocolUpgradeable(admin, upgradeController, governanceController);
        value = initialValue;
    }

    function initializeWithoutGuard(
        address admin,
        address upgradeController,
        address governanceController
    ) external {
        _initializeProtocolUpgradeable(admin, upgradeController, governanceController);
    }

    function reinitializeV2(uint256 newValue) external reinitializer(2) {
        value = newValue;
    }
}

contract ProtocolInitializerSecurityTest is Test {
    address internal admin = address(0xA11CE);
    address internal attacker = address(0xBAD);

    function test_ImplementationInitializerIsDisabled() public {
        ProtocolUpgradeableHarness implementation = new ProtocolUpgradeableHarness();

        vm.expectRevert();
        implementation.initialize(admin, address(0), address(0), 7);
    }

    function test_ProxyCanInitializeExactlyOnce() public {
        ProtocolUpgradeableHarness implementation = new ProtocolUpgradeableHarness();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                ProtocolUpgradeableHarness.initialize,
                (admin, address(0), address(0), 7)
            )
        );
        ProtocolUpgradeableHarness proxied = ProtocolUpgradeableHarness(address(proxy));

        assertEq(proxied.value(), 7);
        assertTrue(proxied.hasRole(proxied.DEFAULT_ADMIN_ROLE(), admin));

        vm.expectRevert();
        proxied.initialize(admin, address(0), address(0), 8);
    }

    function test_UnguardedDerivedSetupCannotInitialize() public {
        ProtocolUpgradeableHarness implementation = new ProtocolUpgradeableHarness();
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), bytes(""));
        ProtocolUpgradeableHarness proxied = ProtocolUpgradeableHarness(address(proxy));

        vm.prank(attacker);
        vm.expectRevert();
        proxied.initializeWithoutGuard(admin, address(0), address(0));

        assertFalse(proxied.hasRole(proxied.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_ReinitializerVersionCanOnlyBeUsedOnce() public {
        ProtocolUpgradeableHarness implementation = new ProtocolUpgradeableHarness();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                ProtocolUpgradeableHarness.initialize,
                (admin, address(0), address(0), 7)
            )
        );
        ProtocolUpgradeableHarness proxied = ProtocolUpgradeableHarness(address(proxy));

        proxied.reinitializeV2(9);
        assertEq(proxied.value(), 9);

        vm.expectRevert();
        proxied.reinitializeV2(10);
    }
}
