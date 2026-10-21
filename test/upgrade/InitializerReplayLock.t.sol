// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockUpgradeable} from "../../contracts/MockUpgradeable.sol";
import {TruthBountyToken} from "../../contracts/TruthBounty.sol";
import {ProtocolUpgradeable} from "../../contracts/upgrade/ProtocolUpgradeable.sol";
import {
    NamespacedSentinelModuleV1,
    NamespacedSentinelModuleV2
} from "../../contracts/mocks/NamespacedSentinelModule.sol";
import {UninitializedUpgradeProxy} from "./UpgradeInitializerHarness.sol";

/**
 * @title GovernanceReplayHarness
 * @notice Exposes the governance setup helper without the initializer guard, so the
 *         suite can prove that the base contract rejects it outside an initializer.
 */
contract GovernanceReplayHarness is ProtocolUpgradeable {
    function replayGovernanceSetup(address admin) external {
        _initializeGovernance(address(0), admin, admin);
    }
}

/**
 * @title InitializerReplayLockTest (PREWAVE-SC-054)
 * @notice Locks the initializer safety properties for every upgradeable implementation
 *         the repository ships:
 *           1. implementations cannot be seized (no initializer runs on them);
 *           2. each initializer runs exactly once, in order;
 *           3. upgrade reinitializers are version-gated and never skip a parent;
 *           4. constructor state never leaks into a proxy.
 *         The synthetic harnesses are covered by ProtocolInitializerSecurity.t.sol and
 *         UpgradeInitializerReinitializer.t.sol; this suite covers the real
 *         implementations (TruthBountyToken, MockUpgradeable and the sentinel module).
 */
contract InitializerReplayLockTest is Test {
    event Initialized(uint64 version);

    address internal owner = address(0xA11CE);
    address internal stranger = address(0xBAD);

    // -----------------------------------------------------------------
    // 1. Implementations cannot be seized
    // -----------------------------------------------------------------

    function test_MockUpgradeable_ImplementationCannotBeInitialized() public {
        MockUpgradeable implementation = new MockUpgradeable();

        vm.expectRevert();
        implementation.initialize(1);
    }

    function test_SentinelV1_ImplementationCannotBeInitialized() public {
        NamespacedSentinelModuleV1 implementation = new NamespacedSentinelModuleV1();

        vm.expectRevert();
        implementation.initialize(owner);
    }

    function test_TruthBountyToken_DeployedImplementationCannotBeUpgradedInPlace() public {
        TruthBountyToken token = new TruthBountyToken(owner);

        // The token is deployed directly, so the UUPS upgrade path must refuse to run.
        vm.expectRevert();
        token.upgradeToAndCall(address(0), bytes(""));
    }

    function test_TruthBountyToken_ConstructorStateDoesNotLeakIntoAProxy() public {
        TruthBountyToken implementation = new TruthBountyToken(owner);
        UninitializedUpgradeProxy proxy = new UninitializedUpgradeProxy(address(implementation));
        TruthBountyToken proxied = TruthBountyToken(address(proxy));

        assertFalse(
            proxied.hasRole(proxied.DEFAULT_ADMIN_ROLE(), owner),
            "constructor roles must not leak into the proxy"
        );
        assertEq(proxied.totalSupply(), 0, "constructor mint must not leak into the proxy");
    }

    // -----------------------------------------------------------------
    // 2. Each initializer runs once, in order
    // -----------------------------------------------------------------

    function test_MockUpgradeable_ProxyInitializesExactlyOnceAndRunsParent() public {
        MockUpgradeable implementation = new MockUpgradeable();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(MockUpgradeable.initialize, (uint256(42)))
        );
        MockUpgradeable proxied = MockUpgradeable(address(proxy));

        assertEq(proxied.value(), 42, "initializer did not run");
        assertEq(proxied.owner(), address(this), "parent initializer did not run");

        vm.expectRevert();
        proxied.initialize(43);
        assertEq(proxied.value(), 42, "a replayed initializer must not change state");
    }

    function test_SentinelV1_ProxyInitializesExactlyOnce() public {
        NamespacedSentinelModuleV1 implementation = new NamespacedSentinelModuleV1();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(NamespacedSentinelModuleV1.initialize, (owner))
        );
        NamespacedSentinelModuleV1 proxied = NamespacedSentinelModuleV1(address(proxy));

        assertEq(proxied.owner(), owner, "initializer did not run");
        assertEq(uint256(proxied.initializedVersion()), 1, "initializer version must be 1");

        vm.expectRevert();
        proxied.initialize(stranger);
        assertEq(proxied.owner(), owner, "a replayed initializer must not take over");
    }

    function test_SentinelV1_EmitsInitializedEvent() public {
        NamespacedSentinelModuleV1 implementation = new NamespacedSentinelModuleV1();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(NamespacedSentinelModuleV1.initialize, (owner))
        );

        vm.expectEmit(true, true, true, true, address(proxy));
        emit Initialized(1);
        NamespacedSentinelModuleV1(address(proxy)).initialize(owner);
    }

    function test_ProtocolUpgradeable_GovernanceSetupCannotBeReplayed() public {
        GovernanceReplayHarness implementation = new GovernanceReplayHarness();
        UninitializedUpgradeProxy proxy = new UninitializedUpgradeProxy(address(implementation));
        GovernanceReplayHarness proxied = GovernanceReplayHarness(address(proxy));

        vm.expectRevert();
        proxied.replayGovernanceSetup(stranger);

        assertFalse(
            proxied.hasRole(proxied.DEFAULT_ADMIN_ROLE(), stranger),
            "governance setup must not run outside an initializer"
        );
    }

    // -----------------------------------------------------------------
    // 3. Upgrade reinitializers are version-gated
    // -----------------------------------------------------------------

    function test_SentinelV2_ReinitializerRequiresParentInitialization() public {
        NamespacedSentinelModuleV2 implementation = new NamespacedSentinelModuleV2();
        UninitializedUpgradeProxy proxy = new UninitializedUpgradeProxy(address(implementation));
        NamespacedSentinelModuleV2 proxied = NamespacedSentinelModuleV2(address(proxy));

        // The V2 migration hook must not run on a proxy whose V1 initializer never ran.
        vm.expectRevert();
        proxied.initializeV2(1);

        assertEq(
            uint256(proxied.initializedVersion()),
            0,
            "a rejected reinitializer must not consume a version"
        );
    }

    function test_SentinelV2_UpgradeReinitIsVersionGated() public {
        NamespacedSentinelModuleV1 implV1 = new NamespacedSentinelModuleV1();
        NamespacedSentinelModuleV2 implV2 = new NamespacedSentinelModuleV2();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implV1),
            abi.encodeCall(NamespacedSentinelModuleV1.initialize, (owner))
        );
        NamespacedSentinelModuleV1 proxied = NamespacedSentinelModuleV1(address(proxy));

        vm.prank(owner);
        proxied.upgradeToAndCall(
            address(implV2), abi.encodeCall(NamespacedSentinelModuleV2.initializeV2, (uint256(7)))
        );

        NamespacedSentinelModuleV2 upgraded = NamespacedSentinelModuleV2(address(proxy));
        assertEq(upgraded.version(), 2, "implementation version must advance");
        assertEq(upgraded.appendedValue(), 7, "reinitializer did not run");
        assertEq(uint256(upgraded.initializedVersion()), 2, "reinitializer(2) must be recorded");
        assertEq(upgraded.owner(), owner, "the owner must survive the upgrade");

        // The reinitializer is version-gated: it cannot run a second time.
        vm.expectRevert();
        upgraded.initializeV2(8);
        assertEq(upgraded.appendedValue(), 7, "a rejected reinitializer must not change state");

        // The V1 initializer is gone after the upgrade and cannot be replayed.
        vm.expectRevert();
        upgraded.initialize(stranger);
    }
}
