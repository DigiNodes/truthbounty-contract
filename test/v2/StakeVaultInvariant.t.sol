// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../contracts/v2/StakeVault.sol";
import "../../contracts/v2/interfaces/IV2Types.sol";
import "../../contracts/mocks/MockModuleRegistry.sol";
import "../../contracts/MockERC20.sol";

contract StakeVaultInvariantHandler is Test {
    StakeVault public vault;
    MockERC20 public token;
    MockModuleRegistry public registry;

    address public settlement;
    address public userA;
    address public userB;

    uint256 public ghostCustody;
    uint256 public ghostLocked;
    uint256 public ghostClaimable;
    uint256 public ghostProtocol;

    constructor() {
        registry = new MockModuleRegistry();
        token = new MockERC20("Stake", "STK");
        vault = new StakeVault(address(registry), address(token), address(this));

        settlement = address(0xSETTLE);
        userA = address(0xA);
        userB = address(0xB);

        registry.registerModule(vault.MODULE_SETTLEMENT(), settlement);

        token.mint(userA, type(uint128).max / 2);
        token.mint(userB, type(uint128).max / 2);

        vm.prank(userA);
        token.approve(address(vault), type(uint256).max);
        vm.prank(userB);
        token.approve(address(vault), type(uint256).max);
    }

    function depositStake(uint256 claimId, uint256 amount, uint256 actorSeed) public {
        amount = bound(amount, 1, 1_000 ether);
        claimId = bound(claimId, 1, 100);
        address user = actorSeed % 2 == 0 ? userA : userB;

        vm.prank(user);
        try vault.depositStake(claimId, amount) {
            ghostCustody += amount;
            ghostLocked += amount;
        } catch {}
    }

    function releaseStake(uint256 claimId, uint256 amount, uint256 actorSeed) public {
        amount = bound(amount, 1, 1_000 ether);
        claimId = bound(claimId, 1, 100);
        address user = actorSeed % 2 == 0 ? userA : userB;

        vm.prank(settlement);
        try vault.releaseStake(claimId, user, amount) {
            ghostLocked -= amount;
            ghostClaimable += amount;
        } catch {}
    }

    function withdraw(uint256 amount, uint256 actorSeed) public {
        amount = bound(amount, 1, 1_000 ether);
        address user = actorSeed % 2 == 0 ? userA : userB;

        vm.prank(user);
        try vault.withdraw(address(token), amount) {
            ghostClaimable -= amount;
            ghostCustody -= amount;
        } catch {}
    }
}

contract StakeVaultInvariantTest is StdInvariant, Test {
    StakeVaultInvariantHandler public handler;

    function setUp() public {
        handler = new StakeVaultInvariantHandler();
        targetContract(address(handler.vault));
    }

    function invariant_obligationsNeverExceedCustody() public view {
        (uint256 custody, uint256 obligations) = handler.vault().reconcile(address(handler.token()));
        assertLe(obligations, custody);
    }

    function invariant_custodyMatchesTokenBalance() public view {
        uint256 balance = handler.token().balanceOf(address(handler.vault()));
        assertEq(handler.vault().totalCustody(address(handler.token())), balance);
    }

    function invariant_reconcileEquality() public view {
        address asset = address(handler.token());
        (uint256 custody, uint256 obligations) = handler.vault().reconcile(asset);
        assertEq(custody, obligations);
    }
}
