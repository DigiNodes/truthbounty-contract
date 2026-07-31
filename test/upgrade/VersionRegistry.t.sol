// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/upgrade/VersionRegistry.sol";

contract VersionRegistryTest is Test {
    VersionRegistry public registry;

    address public admin = address(0x1);
    address public impl1 = address(0x10);
    address public proxy1 = address(0x20);
    address public impl2 = address(0x30);

    function setUp() public {
        registry = new VersionRegistry(admin);
    }

    function test_RegisterVersion() public {
        uint256 idx = registry.registerVersion(
            "TruthBounty",
            impl1,
            proxy1,
            "1.0.0",
            bytes32(0),
            keccak256("hash1")
        );

        assertEq(idx, 0);

        IVersionRegistry.VersionEntry memory entry = registry.getVersion("TruthBounty", "1.0.0");
        assertEq(entry.implementation, impl1);
        assertEq(entry.proxy, proxy1);
        assertEq(entry.semanticVersion, "1.0.0");
        assertEq(uint256(entry.status), uint256(IVersionRegistry.VersionStatus.ACTIVE));
    }

    function test_RegisterMultipleVersions() public {
        registry.registerVersion("TruthBounty", impl1, proxy1, "1.0.0", bytes32(0), bytes32(0));
        registry.registerVersion("TruthBounty", impl2, proxy1, "2.0.0", bytes32(0), bytes32(0));

        assertEq(registry.getVersionCount("TruthBounty"), 2);

        IVersionRegistry.VersionEntry memory latest = registry.getLatestVersion("TruthBounty");
        assertEq(latest.implementation, impl2);
        assertEq(latest.semanticVersion, "2.0.0");
    }

    function test_GetActiveVersion() public {
        registry.registerVersion("TruthBounty", impl1, proxy1, "1.0.0", bytes32(0), bytes32(0));
        registry.registerVersion("TruthBounty", impl2, proxy1, "2.0.0", bytes32(0), bytes32(0));

        IVersionRegistry.VersionEntry memory active = registry.getActiveVersion("TruthBounty");
        assertEq(active.semanticVersion, "2.0.0");
    }

    function test_UpdateVersionStatus() public {
        registry.registerVersion("TruthBounty", impl1, proxy1, "1.0.0", bytes32(0), bytes32(0));
        registry.registerVersion("TruthBounty", impl2, proxy1, "2.0.0", bytes32(0), bytes32(0));

        registry.updateVersionStatus("TruthBounty", "1.0.0", IVersionRegistry.VersionStatus.DEPRECATED);

        assertFalse(registry.isVersionActive("TruthBounty", "1.0.0"));
        assertTrue(registry.isVersionActive("TruthBounty", "2.0.0"));
    }

    function test_UpdateVersionStatus_SetActive() public {
        registry.registerVersion("TruthBounty", impl1, proxy1, "1.0.0", bytes32(0), bytes32(0));
        registry.registerVersion("TruthBounty", impl2, proxy1, "2.0.0", bytes32(0), bytes32(0));

        registry.updateVersionStatus("TruthBounty", "2.0.0", IVersionRegistry.VersionStatus.ROLLED_BACK);

        IVersionRegistry.VersionEntry memory active = registry.getActiveVersion("TruthBounty");
        assertEq(active.semanticVersion, "1.0.0");
    }

    function test_GetVersionAtIndex() public {
        registry.registerVersion("TruthBounty", impl1, proxy1, "1.0.0", bytes32(0), bytes32(0));
        registry.registerVersion("TruthBounty", impl2, proxy1, "2.0.0", bytes32(0), bytes32(0));

        IVersionRegistry.VersionEntry memory v0 = registry.getVersionAtIndex("TruthBounty", 0);
        assertEq(v0.semanticVersion, "1.0.0");

        IVersionRegistry.VersionEntry memory v1 = registry.getVersionAtIndex("TruthBounty", 1);
        assertEq(v1.semanticVersion, "2.0.0");
    }

    function test_GetContractNames() public {
        registry.registerVersion("TruthBounty", impl1, proxy1, "1.0.0", bytes32(0), bytes32(0));
        registry.registerVersion("Staking", impl2, proxy1, "1.0.0", bytes32(0), bytes32(0));

        string[] memory names = registry.getContractNames();
        assertEq(names.length, 2);
    }

    function test_IsVersionActive() public {
        registry.registerVersion("TruthBounty", impl1, proxy1, "1.0.0", bytes32(0), bytes32(0));

        assertTrue(registry.isVersionActive("TruthBounty", "1.0.0"));
        assertFalse(registry.isVersionActive("TruthBounty", "2.0.0"));
        assertFalse(registry.isVersionActive("NonExistent", "1.0.0"));
    }

    function test_RegisterVersion_RevertsZeroImpl() public {
        vm.expectRevert(VersionRegistry.ZeroAddress.selector);
        registry.registerVersion("TruthBounty", address(0), proxy1, "1.0.0", bytes32(0), bytes32(0));
    }

    function test_RegisterVersion_RevertsEmptyName() public {
        vm.expectRevert(VersionRegistry.EmptyString.selector);
        registry.registerVersion("", impl1, proxy1, "1.0.0", bytes32(0), bytes32(0));
    }

    function test_UpdateVersionStatus_RevertsNotRegistered() public {
        vm.expectRevert();
        registry.updateVersionStatus("NonExistent", "1.0.0", IVersionRegistry.VersionStatus.DEPRECATED);
    }

    function test_GetVersion_RevertsNotFound() public {
        vm.expectRevert();
        registry.getVersion("TruthBounty", "9.0.0");
    }

    function test_RegisterVersion_RecordsTimestamp() public {
        uint256 before = block.timestamp;
        registry.registerVersion("TruthBounty", impl1, proxy1, "1.0.0", bytes32(0), bytes32(0));
        uint256 after_ = block.timestamp;

        IVersionRegistry.VersionEntry memory entry = registry.getVersion("TruthBounty", "1.0.0");
        assertGe(entry.deployedAt, before);
        assertLe(entry.deployedAt, after_);
    }

    function test_IsContractRegistered() public {
        assertFalse(registry.isContractRegistered("TruthBounty"));
        registry.registerVersion("TruthBounty", impl1, proxy1, "1.0.0", bytes32(0), bytes32(0));
        assertTrue(registry.isContractRegistered("TruthBounty"));
    }
}
