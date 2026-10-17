// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {MockERC20} from "../../contracts/MockERC20.sol";
import {GovernanceAuthorityBoundaries} from "../../contracts/governance/v2/GovernanceAuthorityBoundaries.sol";
import {IGovernanceAuthorityBoundaries} from "../../contracts/governance/v2/IGovernanceAuthorityBoundaries.sol";
import {GovernedModuleRegistry} from "../../contracts/governance/v2/GovernedModuleRegistry.sol";
import {Claims} from "../../contracts/v2/Claims.sol";
import {EmergencyController} from "../../contracts/governance/EmergencyController.sol";
import {EmergencyGatekeeper} from "../../contracts/v2/EmergencyGatekeeper.sol";
import {IModuleRegistry} from "../../contracts/v2/interfaces/IModuleRegistry.sol";
import {ModuleRegistry} from "../../contracts/v2/ModuleRegistry.sol";
import {ModuleRegistryLib} from "../../contracts/v2/libraries/ModuleRegistryLib.sol";
import {StakeVault} from "../../contracts/v2/StakeVault.sol";
import {MockV2Module} from "../../contracts/mocks/MockV2Module.sol";
import {ReputationWeightedVotingBounds} from "../../contracts/verification/ReputationWeightedVotingBounds.sol";
import {TreasuryAccounting} from "../../contracts/treasury/TreasuryAccounting.sol";
import {ITreasuryManagement} from "../../contracts/treasury/ITreasuryManagement.sol";
import {TreasuryManagement} from "../../contracts/treasury/TreasuryManagement.sol";

abstract contract TimelockEnforcementBase is Test {
    uint256 internal constant TIMELOCK_DELAY = 2 days;

    TimelockController internal timelock;

    function _deployTimelock() internal {
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, address(this));
    }

    function _scheduleAndAssertDelay(address target, bytes memory call) internal {
        bytes32 operationId = _scheduleAndAssertReady(target, call);
        timelock.execute(target, 0, call, bytes32(0), bytes32(0));
        assertTrue(timelock.isOperationDone(operationId), "operation was not marked complete");
    }

    function _scheduleAndAssertReady(address target, bytes memory call) internal returns (bytes32 operationId) {
        vm.expectRevert();
        (bool directCallSucceeded,) = target.call(call);
        assertFalse(directCallSucceeded, "bootstrap authority bypassed the timelock");

        operationId = timelock.hashOperation(target, 0, call, bytes32(0), bytes32(0));
        timelock.schedule(target, 0, call, bytes32(0), bytes32(0), TIMELOCK_DELAY);

        vm.warp(block.timestamp + TIMELOCK_DELAY - 1);
        (bool earlyExecutionSucceeded,) = address(timelock).call(
            abi.encodeCall(TimelockController.execute, (target, 0, call, bytes32(0), bytes32(0)))
        );
        assertFalse(earlyExecutionSucceeded, "timelock executed before its minimum delay");
        assertFalse(timelock.isOperationDone(operationId), "early attempt consumed the operation");

        vm.warp(block.timestamp + 1);
    }
}

contract TimelockEnforcementTest is TimelockEnforcementBase {
    MockERC20 internal stakingToken;
    MockERC20 internal additionalAsset;
    ModuleRegistry internal registry;
    StakeVault internal vault;
    address internal guardian = makeAddr("guardian");
    address internal lockMutator = makeAddr("lockMutator");

    function setUp() public {
        _deployTimelock();

        stakingToken = new MockERC20("Stake", "STK");
        additionalAsset = new MockERC20("Additional", "ADD");
        registry = new ModuleRegistry(address(this), address(timelock), guardian);
        vault = new StakeVault(address(registry), address(stakingToken), address(this));

        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(timelock));
        vault.grantRole(vault.ADMIN_ROLE(), address(timelock));
        vault.renounceRole(vault.ADMIN_ROLE(), address(this));
        vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function test_MinimumStakeChangeRequiresTimelockDelay() public {
        bytes memory call = abi.encodeCall(StakeVault.setMinStakeAmount, (2 ether));
        _scheduleAndAssertDelay(address(vault), call);

        assertEq(vault.minStakeAmount(), 2 ether);
    }

    function test_SupportedAssetChangeRequiresTimelockDelay() public {
        bytes memory call = abi.encodeCall(StakeVault.setSupportedAsset, (address(additionalAsset), true));
        _scheduleAndAssertDelay(address(vault), call);

        assertTrue(vault.supportedAssets(address(additionalAsset)));
    }

    function test_LockMutatorChangeRequiresTimelockDelay() public {
        bytes memory call = abi.encodeCall(StakeVault.setLockMutator, (lockMutator, true));
        _scheduleAndAssertDelay(address(vault), call);

        assertTrue(vault.lockMutators(lockMutator));
    }

    function test_AdminRoleGrantAndRevocationRequireTimelock() public {
        address newAdmin = makeAddr("newVaultAdmin");
        bytes32 adminRole = vault.ADMIN_ROLE();
        _scheduleAndAssertDelay(
            address(vault),
            abi.encodeCall(StakeVault.grantRole, (adminRole, newAdmin))
        );
        assertTrue(vault.hasRole(adminRole, newAdmin));

        _scheduleAndAssertDelay(
            address(vault),
            abi.encodeCall(StakeVault.revokeRole, (adminRole, newAdmin))
        );
        assertFalse(vault.hasRole(adminRole, newAdmin));
    }
}

contract TimelockRegistryEnforcementTest is TimelockEnforcementBase {
    address internal guardian = makeAddr("registryGuardian");
    GovernedModuleRegistry internal governedRegistry;
    GovernanceAuthorityBoundaries internal authorityBoundaries;
    ModuleRegistry internal moduleRegistry;

    function setUp() public {
        _deployTimelock();

        governedRegistry = new GovernedModuleRegistry(address(this));
        governedRegistry.grantRole(governedRegistry.DEFAULT_ADMIN_ROLE(), address(timelock));
        governedRegistry.grantRole(governedRegistry.REGISTRY_ADMIN_ROLE(), address(timelock));
        governedRegistry.renounceRole(governedRegistry.REGISTRY_ADMIN_ROLE(), address(this));
        governedRegistry.renounceRole(governedRegistry.DEFAULT_ADMIN_ROLE(), address(this));

        authorityBoundaries = new GovernanceAuthorityBoundaries(address(this));
        authorityBoundaries.grantRole(authorityBoundaries.DEFAULT_ADMIN_ROLE(), address(timelock));
        authorityBoundaries.grantRole(authorityBoundaries.AUTHORITY_ADMIN_ROLE(), address(timelock));
        authorityBoundaries.renounceRole(authorityBoundaries.AUTHORITY_ADMIN_ROLE(), address(this));
        authorityBoundaries.renounceRole(authorityBoundaries.DEFAULT_ADMIN_ROLE(), address(this));

        moduleRegistry = new ModuleRegistry(address(this), address(timelock), guardian);
        moduleRegistry.grantRole(moduleRegistry.DEFAULT_ADMIN_ROLE(), address(timelock));
        moduleRegistry.grantRole(moduleRegistry.DEPLOYMENT_ROLE(), address(timelock));
        moduleRegistry.renounceRole(moduleRegistry.DEPLOYMENT_ROLE(), address(this));
        moduleRegistry.renounceRole(moduleRegistry.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function test_GovernedModuleRegistrationAndRemovalRequireTimelock() public {
        address module = makeAddr("governedModule");
        bytes32 moduleKey = keccak256("GOVERNED_MODULE");

        _scheduleAndAssertDelay(
            address(governedRegistry),
            abi.encodeCall(GovernedModuleRegistry.registerModule, (moduleKey, module))
        );
        assertTrue(governedRegistry.isGovernedModule(module));

        _scheduleAndAssertDelay(
            address(governedRegistry),
            abi.encodeCall(GovernedModuleRegistry.removeModule, (moduleKey))
        );
        assertFalse(governedRegistry.isGovernedModule(module));
    }

    function test_AuthorityBindingAndRevocationRequireTimelock() public {
        IGovernanceAuthorityBoundaries.AuthorityRole role = IGovernanceAuthorityBoundaries.AuthorityRole.TREASURY;
        address treasuryAuthority = makeAddr("treasuryAuthority");

        _scheduleAndAssertDelay(
            address(authorityBoundaries),
            abi.encodeCall(GovernanceAuthorityBoundaries.bindAuthority, (role, treasuryAuthority))
        );
        assertEq(authorityBoundaries.authorityOf(role), treasuryAuthority);

        _scheduleAndAssertDelay(
            address(authorityBoundaries),
            abi.encodeCall(GovernanceAuthorityBoundaries.revokeAuthority, (role))
        );
        assertEq(authorityBoundaries.authorityOf(role), address(0));
    }

    function test_ModuleRegistrationAndActivationRequireTimelock() public {
        bytes32 moduleId = ModuleRegistryLib.MODULE_CLAIMS;
        bytes4 interfaceId = moduleRegistry.canonicalInterfaceOf(moduleId);
        MockV2Module module = new MockV2Module(2, 0, interfaceId);
        IModuleRegistry.ModuleRegistration memory registration = IModuleRegistry.ModuleRegistration({
            moduleId: moduleId,
            interfaceId: interfaceId,
            proxy: address(module),
            implementation: address(0),
            major: 2,
            minor: 0
        });

        _scheduleAndAssertDelay(
            address(moduleRegistry),
            abi.encodeCall(ModuleRegistry.registerModule, (registration))
        );
        assertEq(uint256(moduleRegistry.moduleStatus(moduleId)), uint256(IModuleRegistry.ModuleStatus.REGISTERED));

        _scheduleAndAssertDelay(
            address(moduleRegistry),
            abi.encodeCall(ModuleRegistry.activateModule, (moduleId))
        );
        assertTrue(moduleRegistry.isRegistered(moduleId));

        MockV2Module replacement = new MockV2Module(2, 1, interfaceId);
        IModuleRegistry.ModuleRegistration memory replacementRegistration = IModuleRegistry.ModuleRegistration({
            moduleId: moduleId,
            interfaceId: interfaceId,
            proxy: address(replacement),
            implementation: address(0),
            major: 2,
            minor: 1
        });
        _scheduleAndAssertDelay(
            address(moduleRegistry),
            abi.encodeCall(ModuleRegistry.proposeModuleReplacement, (replacementRegistration))
        );
        uint256 replacementReadyAt = moduleRegistry.replacementReadyAt(moduleId);
        vm.expectRevert();
        moduleRegistry.activateModuleReplacement(moduleId);
        vm.warp(replacementReadyAt);
        moduleRegistry.activateModuleReplacement(moduleId);
        assertEq(moduleRegistry.getModule(moduleId).proxy, address(replacement));

        MockV2Module cancelledReplacement = new MockV2Module(2, 2, interfaceId);
        IModuleRegistry.ModuleRegistration memory cancelledRegistration = IModuleRegistry.ModuleRegistration({
            moduleId: moduleId,
            interfaceId: interfaceId,
            proxy: address(cancelledReplacement),
            implementation: address(0),
            major: 2,
            minor: 2
        });
        _scheduleAndAssertDelay(
            address(moduleRegistry),
            abi.encodeCall(ModuleRegistry.proposeModuleReplacement, (cancelledRegistration))
        );
        _scheduleAndAssertDelay(
            address(moduleRegistry),
            abi.encodeCall(ModuleRegistry.cancelModuleReplacement, (moduleId))
        );
        assertEq(moduleRegistry.replacementReadyAt(moduleId), 0);

        _scheduleAndAssertDelay(
            address(moduleRegistry),
            abi.encodeCall(ModuleRegistry.forbidModule, (address(cancelledReplacement)))
        );
        assertTrue(moduleRegistry.isForbidden(address(cancelledReplacement)));
        _scheduleAndAssertDelay(
            address(moduleRegistry),
            abi.encodeCall(ModuleRegistry.unforbidModule, (address(cancelledReplacement)))
        );
        assertFalse(moduleRegistry.isForbidden(address(cancelledReplacement)));

        _scheduleAndAssertDelay(
            address(moduleRegistry),
            abi.encodeCall(ModuleRegistry.deprecateModule, (moduleId))
        );
        assertTrue(moduleRegistry.isDeprecated(moduleId));
        _scheduleAndAssertDelay(
            address(moduleRegistry),
            abi.encodeCall(ModuleRegistry.removeModule, (moduleId))
        );
        assertEq(uint256(moduleRegistry.moduleStatus(moduleId)), uint256(IModuleRegistry.ModuleStatus.NONE));
    }
}

contract TimelockTreasuryEnforcementTest is TimelockEnforcementBase {
    MockERC20 internal token;
    TreasuryManagement internal treasury;
    address internal emergencyAdmin = makeAddr("treasuryEmergencyAdmin");

    function setUp() public {
        _deployTimelock();
        token = new MockERC20("Protocol", "PRT");
        treasury = new TreasuryManagement(address(token), address(timelock), address(this), emergencyAdmin);
        treasury.setMinReserveRatioBPS(0);

        treasury.grantRole(treasury.DEFAULT_ADMIN_ROLE(), address(timelock));
        treasury.grantRole(treasury.ADMIN_ROLE(), address(timelock));
        treasury.renounceRole(treasury.ADMIN_ROLE(), address(this));
        treasury.renounceRole(treasury.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function test_TreasuryConfigurationAndModuleAuthorizationRequireTimelock() public {
        address module = makeAddr("treasuryModule");
        _scheduleAndAssertDelay(
            address(treasury),
            abi.encodeCall(TreasuryManagement.setMaxWithdrawalBPS, (3000))
        );
        _scheduleAndAssertDelay(
            address(treasury),
            abi.encodeCall(TreasuryManagement.setMinReserveRatioBPS, (600))
        );
        _scheduleAndAssertDelay(
            address(treasury),
            abi.encodeCall(TreasuryManagement.setEmergencyWithdrawalLimit, (100 ether))
        );
        _scheduleAndAssertDelay(
            address(treasury),
            abi.encodeCall(TreasuryManagement.setMaxAllocationBPS, (1200))
        );
        _scheduleAndAssertDelay(
            address(treasury),
            abi.encodeCall(TreasuryManagement.setWithdrawalsEnabled, (false))
        );
        _scheduleAndAssertDelay(
            address(treasury),
            abi.encodeCall(TreasuryManagement.setDepositsEnabled, (false))
        );
        _scheduleAndAssertDelay(
            address(treasury),
            abi.encodeCall(TreasuryManagement.setWithdrawalLimitPerBlock, (ITreasuryManagement.TreasuryPool.REWARDS_POOL, 10 ether))
        );
        _scheduleAndAssertDelay(
            address(treasury),
            abi.encodeCall(TreasuryManagement.setAuthorisedModule, (module, true))
        );

        ITreasuryManagement.TreasuryConfig memory config = treasury.getConfig();
        assertEq(config.maxWithdrawalBPS, 3000);
        assertEq(config.minReserveRatioBPS, 600);
        assertEq(config.emergencyWithdrawalLimit, 100 ether);
        assertEq(config.maxAllocationBPS, 1200);
        assertFalse(config.withdrawalsEnabled);
        assertFalse(config.depositsEnabled);
        assertTrue(treasury.isAuthorisedModule(module));
    }

    function test_EmergencyAdminCannotChangeTreasuryConfiguration() public {
        vm.prank(emergencyAdmin);
        (bool succeeded,) = address(treasury).call(
            abi.encodeCall(TreasuryManagement.setDepositsEnabled, (false))
        );

        assertFalse(succeeded);
        assertTrue(treasury.getConfig().depositsEnabled);
    }

    function test_EmergencyAdminCannotWithdrawTreasuryAssets() public {
        vm.prank(emergencyAdmin);
        (bool succeeded,) = address(treasury).call(
            abi.encodeCall(TreasuryManagement.emergencyWithdrawal, (makeAddr("recipient"), 1 ether))
        );

        assertFalse(succeeded);
    }

    function test_EmergencyWithdrawalRequiresTimelockAndReconcilesAccounting() public {
        address recipient = makeAddr("withdrawalRecipient");
        uint256 amount = 1 ether;
        token.mint(address(treasury), amount);
        treasury.recordGovernanceDeposit(address(this), amount);

        uint256 recordsBefore = treasury.getRecordCount();
        bytes memory call = abi.encodeCall(TreasuryManagement.emergencyWithdrawal, (recipient, amount));
        bytes32 operationId = _scheduleAndAssertReady(
            address(treasury),
            call
        );
        vm.expectEmit(true, false, false, true, address(treasury));
        emit ITreasuryManagement.EmergencyWithdrawal(recipient, amount, bytes32(0));
        timelock.execute(address(treasury), 0, call, bytes32(0), bytes32(0));
        assertTrue(timelock.isOperationDone(operationId));

        ITreasuryManagement.PoolBalance memory governancePool =
            treasury.getPoolBalance(ITreasuryManagement.TreasuryPool.GOVERNANCE_RESERVE);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(governancePool.currentBalance, 0);
        assertEq(treasury.getTotalAssets(), 0);
        assertEq(treasury.getRecordCount(), recordsBefore + 1);
    }
}

contract TimelockTreasuryAccountingEnforcementTest is TimelockEnforcementBase {
    TreasuryAccounting internal treasuryAccounting;
    MockERC20 internal token;

    function setUp() public {
        _deployTimelock();
        token = new MockERC20("Accounting", "ACC");
        treasuryAccounting = new TreasuryAccounting(address(token), address(timelock), address(this));

        treasuryAccounting.grantRole(treasuryAccounting.DEFAULT_ADMIN_ROLE(), address(timelock));
        treasuryAccounting.grantRole(treasuryAccounting.ADMIN_ROLE(), address(timelock));
        treasuryAccounting.renounceRole(treasuryAccounting.ADMIN_ROLE(), address(this));
        treasuryAccounting.renounceRole(treasuryAccounting.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function test_TreasuryAccountingRiskLimitsRequireTimelock() public {
        _scheduleAndAssertDelay(
            address(treasuryAccounting),
            abi.encodeCall(TreasuryAccounting.setMaxRewardsWithdrawalBPS, (1000))
        );
        _scheduleAndAssertDelay(
            address(treasuryAccounting),
            abi.encodeCall(TreasuryAccounting.setMinStakingReserveRatio, (1500))
        );

        assertEq(treasuryAccounting.maxRewardsWithdrawalBPS(), 1000);
        assertEq(treasuryAccounting.minStakingReserveRatio(), 1500);
    }
}

contract TimelockEmergencyConfigurationTest is TimelockEnforcementBase {
    EmergencyGatekeeper internal gatekeeper;
    address internal pauseInitiator = makeAddr("pauseInitiator");
    address internal pauseResolver = makeAddr("pauseResolver");
    bytes32 internal constant SCOPE = keccak256("TIMELOCK_TEST_SCOPE");

    function setUp() public {
        _deployTimelock();
        gatekeeper = new EmergencyGatekeeper(address(this), pauseInitiator, pauseResolver, 1 hours);
        gatekeeper.grantRole(gatekeeper.DEFAULT_ADMIN_ROLE(), address(timelock));
        gatekeeper.grantRole(gatekeeper.ADMIN_ROLE(), address(timelock));
        gatekeeper.renounceRole(gatekeeper.ADMIN_ROLE(), address(this));
        gatekeeper.renounceRole(gatekeeper.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function test_EmergencyConfigurationRequiresTimelockWhilePauseRecoveryStaysImmediate() public {
        _scheduleAndAssertDelay(
            address(gatekeeper),
            abi.encodeCall(EmergencyGatekeeper.setScopeMaxPauseLevel, (SCOPE, uint8(2)))
        );
        assertEq(gatekeeper.maxPauseLevel(SCOPE), 2);

        _scheduleAndAssertDelay(
            address(gatekeeper),
            abi.encodeCall(EmergencyGatekeeper.setEmergencyRewireDelay, (2 hours))
        );
        assertEq(gatekeeper.emergencyRewireDelay(), 2 hours);

        EmergencyController controller = new EmergencyController(pauseInitiator, pauseResolver, address(timelock));
        _scheduleAndAssertDelay(
            address(gatekeeper),
            abi.encodeCall(EmergencyGatekeeper.setEmergencyController, (address(controller)))
        );
        assertEq(gatekeeper.emergencyController(), address(controller));

        vm.prank(pauseInitiator);
        gatekeeper.pause(SCOPE);
        assertTrue(gatekeeper.locallyPaused(SCOPE));

        vm.prank(pauseResolver);
        gatekeeper.unpause(SCOPE);
        assertFalse(gatekeeper.locallyPaused(SCOPE));
    }
}

contract TimelockV2ConfigurationEnforcementTest is TimelockEnforcementBase {
    MockERC20 internal token;
    Claims internal claims;
    ReputationWeightedVotingBounds internal votingBounds;

    function setUp() public {
        _deployTimelock();
        token = new MockERC20("Configuration", "CFG");

        claims = new Claims(address(this), address(token), address(this), 1 ether, 0.01 ether);
        claims.grantRole(claims.DEFAULT_ADMIN_ROLE(), address(timelock));
        claims.grantRole(claims.ADMIN_ROLE(), address(timelock));
        claims.renounceRole(claims.ADMIN_ROLE(), address(this));
        claims.renounceRole(claims.DEFAULT_ADMIN_ROLE(), address(this));

        MockV2Module initialRoots = new MockV2Module(2, 0, bytes4(0x1234));
        votingBounds = new ReputationWeightedVotingBounds(address(this), address(initialRoots));
        votingBounds.grantRole(votingBounds.DEFAULT_ADMIN_ROLE(), address(timelock));
        votingBounds.renounceRole(votingBounds.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function test_ClaimAntiGriefParametersRequireTimelock() public {
        address nextFeeRecipient = makeAddr("nextFeeRecipient");
        bytes memory call = abi.encodeCall(
            Claims.setAntiGriefParams,
            (2 ether, 0.02 ether, 4, uint64(2 hours), 4, nextFeeRecipient)
        );
        _scheduleAndAssertDelay(address(claims), call);

        assertEq(claims.minBounty(), 2 ether);
        assertEq(claims.claimSubmissionFee(), 0.02 ether);
        assertEq(claims.maxClaimsPerWindow(), 4);
        assertEq(claims.claimSpamWindow(), 2 hours);
        assertEq(claims.maxOpenClaimsPerCreator(), 4);
        assertEq(claims.feeRecipient(), nextFeeRecipient);
    }

    function test_ReputationRootsDependencyChangeRequiresTimelock() public {
        MockV2Module replacementRoots = new MockV2Module(2, 0, bytes4(0x5678));
        _scheduleAndAssertDelay(
            address(votingBounds),
            abi.encodeCall(ReputationWeightedVotingBounds.setReputationRootsModule, (address(replacementRoots)))
        );

        assertEq(address(votingBounds.reputationRootsModule()), address(replacementRoots));
    }
}
