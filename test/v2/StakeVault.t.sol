// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/v2/StakeVault.sol";
import "../../contracts/v2/libraries/V2Errors.sol";
import "../../contracts/v2/interfaces/IStakeCustody.sol";
import "../../contracts/v2/interfaces/IV2Module.sol";
import "../../contracts/v2/interfaces/IV2Types.sol";
import "../../contracts/mocks/MockModuleRegistry.sol";
import "../../contracts/mocks/FeeOnTransferERC20.sol";
import "../../contracts/mocks/ReentrancyAttacker.sol";
import "../../contracts/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakeVaultTest is Test {
    StakeVault internal vault;
    MockModuleRegistry internal registry;
    MockERC20 internal token;
    MockERC20 internal tokenB;

    address internal admin = address(this);
    address internal verifier = address(0xBEEF);
    address internal verifier2 = address(0xCAFE);
    address internal settlement = address(0xA001);
    address internal slashing = address(0xA002);

    uint256 internal constant CLAIM_A = 1;
    uint256 internal constant CLAIM_B = 2;
    uint256 internal constant STAKE = 100 ether;

    function setUp() public {
        registry = new MockModuleRegistry();
        token = new MockERC20("Stake", "STK");
        tokenB = new MockERC20("Alt", "ALT");
        vault = new StakeVault(address(registry), address(token), admin);

        vault.setSupportedAsset(address(tokenB), true);

        registry.registerModule(vault.MODULE_SETTLEMENT(), settlement);
        registry.registerModule(vault.MODULE_SLASHING(), slashing);

        token.mint(verifier, 1_000 ether);
        token.mint(verifier2, 1_000 ether);
        tokenB.mint(verifier, 1_000 ether);
        tokenB.mint(verifier2, 1_000 ether);

        vm.prank(verifier);
        token.approve(address(vault), type(uint256).max);
        vm.prank(verifier2);
        token.approve(address(vault), type(uint256).max);
        vm.prank(verifier);
        tokenB.approve(address(vault), type(uint256).max);
        vm.prank(verifier2);
        tokenB.approve(address(vault), type(uint256).max);
    }

    // -------------------------------------------------------------------------
    // Deposit / lock / unlock / withdraw
    // -------------------------------------------------------------------------

    function test_depositStake_locksVerifierPrincipal() public {
        vm.prank(verifier);
        vault.depositStake(CLAIM_A, STAKE);

        assertEq(vault.staked(CLAIM_A, verifier), STAKE);
        assertEq(vault.totalStaked(CLAIM_A), STAKE);
        assertEq(vault.lockedPrincipal(address(token), verifier, CLAIM_A, 0, IV2Types.LockCategory.VERIFIER_PRINCIPAL), STAKE);
        assertEq(vault.claimableBalance(address(token), verifier), 0);
        assertEq(vault.totalCustody(address(token)), STAKE);
    }

    function test_releaseStake_unlocksToClaimable() public {
        vm.prank(verifier);
        vault.depositStake(CLAIM_A, STAKE);

        vm.prank(settlement);
        vault.releaseStake(CLAIM_A, verifier, STAKE);

        assertEq(vault.staked(CLAIM_A, verifier), 0);
        assertEq(vault.claimableBalance(address(token), verifier), STAKE);
    }

    function test_withdraw_pullsClaimableBalance() public {
        vm.prank(verifier);
        vault.depositStake(CLAIM_A, STAKE);

        vm.prank(settlement);
        vault.releaseStake(CLAIM_A, verifier, STAKE);

        uint256 before = token.balanceOf(verifier);
        vm.prank(verifier);
        vault.withdraw(address(token), STAKE);

        assertEq(token.balanceOf(verifier), before + STAKE);
        assertEq(vault.totalCustody(address(token)), 0);
    }

    function test_slashStake_movesToProtocolAllocation() public {
        vm.prank(verifier);
        vault.depositStake(CLAIM_A, STAKE);

        bytes32 reason = keccak256("misbehavior");
        vm.prank(slashing);
        vault.slashStake(CLAIM_A, verifier, STAKE, reason);

        assertEq(vault.staked(CLAIM_A, verifier), 0);
        assertEq(vault.protocolAllocation(address(token)), STAKE);
        assertEq(vault.claimableBalance(address(token), verifier), 0);
    }

    function test_deposit_lock_unlock_allocate_flow() public {
        vm.prank(verifier);
        vault.deposit(address(token), STAKE);

        vm.prank(settlement);
        vault.lock(address(token), verifier, CLAIM_A, 1, IV2Types.LockCategory.CHALLENGE_BOND, STAKE / 2);

        assertEq(
            vault.lockedPrincipal(address(token), verifier, CLAIM_A, 1, IV2Types.LockCategory.CHALLENGE_BOND),
            STAKE / 2
        );

        vm.prank(settlement);
        vault.unlock(address(token), verifier, CLAIM_A, 1, IV2Types.LockCategory.CHALLENGE_BOND, STAKE / 4);

        vm.prank(slashing);
        vault.allocateLocked(
            address(token), verifier, CLAIM_A, 1, IV2Types.LockCategory.CHALLENGE_BOND, STAKE / 4, bytes32("slash")
        );

        assertEq(vault.protocolAllocation(address(token)), STAKE / 4);
        assertEq(vault.claimableBalance(address(token), verifier), STAKE / 2);
    }

    // -------------------------------------------------------------------------
    // Authorization
    // -------------------------------------------------------------------------

    function test_unauthorizedLockReverts() public {
        vm.prank(verifier);
        vault.deposit(address(token), STAKE);

        vm.prank(verifier2);
        vm.expectRevert(abi.encodeWithSelector(V2Errors.UnauthorizedModule.selector, verifier2));
        vault.lock(address(token), verifier, CLAIM_A, 0, IV2Types.LockCategory.BOUNTY_ESCROW, STAKE);
    }

    function test_explicitLockMutatorAuthorized() public {
        vm.prank(verifier);
        vault.deposit(address(token), STAKE);

        vault.setLockMutator(verifier2, true);

        vm.prank(verifier2);
        vault.lock(address(token), verifier, CLAIM_A, 0, IV2Types.LockCategory.SETTLEMENT_ALLOCATION, STAKE);
        assertEq(
            vault.lockedPrincipal(address(token), verifier, CLAIM_A, 0, IV2Types.LockCategory.SETTLEMENT_ALLOCATION),
            STAKE
        );
    }

    // -------------------------------------------------------------------------
    // Multi-asset and multi-claim isolation
    // -------------------------------------------------------------------------

    function test_multiAssetIsolation() public {
        vm.prank(verifier);
        vault.depositStake(CLAIM_A, STAKE);

        vm.prank(verifier);
        vault.deposit(address(tokenB), STAKE);

        vm.prank(settlement);
        vault.lock(address(tokenB), verifier, CLAIM_A, 0, IV2Types.LockCategory.BOUNTY_ESCROW, STAKE);

        assertEq(vault.totalCustody(address(token)), STAKE);
        assertEq(vault.totalCustody(address(tokenB)), STAKE);
        assertEq(vault.claimableBalance(address(token), verifier), 0);
        assertEq(vault.claimableBalance(address(tokenB), verifier), 0);
    }

    function test_multiClaimIsolation() public {
        vm.prank(verifier);
        vault.depositStake(CLAIM_A, STAKE);

        vm.prank(verifier);
        vault.depositStake(CLAIM_B, STAKE * 2);

        assertEq(vault.staked(CLAIM_A, verifier), STAKE);
        assertEq(vault.staked(CLAIM_B, verifier), STAKE * 2);
        assertEq(vault.totalStaked(CLAIM_A), STAKE);
        assertEq(vault.totalStaked(CLAIM_B), STAKE * 2);

        vm.prank(settlement);
        vault.releaseStake(CLAIM_A, verifier, STAKE);

        assertEq(vault.staked(CLAIM_B, verifier), STAKE * 2);
        assertEq(vault.claimableBalance(address(token), verifier), STAKE);
    }

    function test_withdrawCannotAffectOtherAccount() public {
        vm.prank(verifier);
        vault.depositStake(CLAIM_A, STAKE);

        vm.prank(settlement);
        vault.releaseStake(CLAIM_A, verifier, STAKE);

        vm.prank(verifier2);
        vm.expectRevert(abi.encodeWithSelector(V2Errors.InsufficientClaimable.selector, verifier2, STAKE, 0));
        vault.withdraw(address(token), STAKE);
    }

    // -------------------------------------------------------------------------
    // Reconciliation
    // -------------------------------------------------------------------------

    function test_reconcileMatchesBuckets() public {
        vm.prank(verifier);
        vault.depositStake(CLAIM_A, STAKE);

        (uint256 custody, uint256 obligations) = vault.reconcile(address(token));
        assertEq(custody, STAKE);
        assertEq(obligations, STAKE);
        assertEq(custody, obligations);
    }

    function test_invariant_obligationsNeverExceedCustody() public {
        vm.prank(verifier);
        vault.depositStake(CLAIM_A, STAKE);

        vm.prank(settlement);
        vault.releaseStake(CLAIM_A, verifier, STAKE / 2);

        (uint256 custody, uint256 obligations) = vault.reconcile(address(token));
        assertLe(obligations, custody);
    }

    // -------------------------------------------------------------------------
    // Malicious ERC-20 and exact-balance checks
    // -------------------------------------------------------------------------

    function test_feeOnTransferTokenRejected() public {
        FeeOnTransferERC20 feeToken = new FeeOnTransferERC20("Fee", "FEE", 100);
        feeToken.mint(verifier, STAKE);
        vault.setSupportedAsset(address(feeToken), true);

        vm.startPrank(verifier);
        feeToken.approve(address(vault), STAKE);
        vm.expectRevert(abi.encodeWithSelector(V2Errors.TransferAmountMismatch.selector, STAKE, STAKE * 99 / 100));
        vault.deposit(address(feeToken), STAKE);
        vm.stopPrank();
    }

    function test_failingTransferRejected() public {
        FeeOnTransferERC20 feeToken = new FeeOnTransferERC20("Fee", "FEE", 10_000);
        feeToken.mint(verifier, STAKE);
        vault.setSupportedAsset(address(feeToken), true);

        vm.startPrank(verifier);
        feeToken.approve(address(vault), STAKE);
        vm.expectRevert(abi.encodeWithSelector(V2Errors.TransferAmountMismatch.selector, STAKE, 0));
        vault.deposit(address(feeToken), STAKE);
        vm.stopPrank();
    }

    function test_zeroAmountReverts() public {
        vm.prank(verifier);
        vm.expectRevert(V2Errors.ZeroAmount.selector);
        vault.depositStake(CLAIM_A, 0);
    }

    function test_unsupportedAssetReverts() public {
        MockERC20 unsupported = new MockERC20("X", "X");
        unsupported.mint(verifier, STAKE);

        vm.startPrank(verifier);
        unsupported.approve(address(vault), STAKE);
        vm.expectRevert(abi.encodeWithSelector(V2Errors.UnsupportedAsset.selector, address(unsupported)));
        vault.deposit(address(unsupported), STAKE);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Reentrancy
    // -------------------------------------------------------------------------

    function test_withdrawReentrancyBlocked() public {
        MaliciousERC20 malicious = new MaliciousERC20(0);
        StakeVaultReentrancyAttacker attacker = new StakeVaultReentrancyAttacker(address(vault), address(malicious));
        malicious.mint(address(attacker), STAKE);
        vault.setSupportedAsset(address(malicious), true);
        malicious.setAttacker(address(attacker));
        malicious.enableAttack(true);

        vm.prank(address(attacker));
        malicious.approve(address(vault), STAKE);
        vm.prank(address(attacker));
        vault.deposit(address(malicious), STAKE);

        vm.prank(settlement);
        vault.lock(address(malicious), address(attacker), CLAIM_A, 0, IV2Types.LockCategory.BOUNTY_ESCROW, STAKE);

        vm.prank(settlement);
        vault.unlock(address(malicious), address(attacker), CLAIM_A, 0, IV2Types.LockCategory.BOUNTY_ESCROW, STAKE);

        vm.prank(address(attacker));
        vm.expectRevert();
        attacker.withdraw(STAKE);

        assertEq(malicious.balanceOf(address(vault)), STAKE);
    }

    // -------------------------------------------------------------------------
    // ERC-165 / module version
    // -------------------------------------------------------------------------

    function test_supportsIStakeCustodyInterface() public view {
        assertTrue(vault.supportsInterface(type(IStakeCustody).interfaceId));
        assertTrue(vault.supportsInterface(type(IV2Module).interfaceId));
    }

    function test_protocolVersion() public view {
        (uint16 major, uint16 minor) = vault.protocolVersion();
        assertEq(major, 2);
        assertEq(minor, 0);
    }
}

/// @dev Attempts to reenter `withdraw` during token transfer.
contract StakeVaultReentrancyAttacker {
    StakeVault public vault;
    IERC20 public token;
    bool internal _entered;

    constructor(address vault_, address token_) {
        vault = StakeVault(vault_);
        token = IERC20(token_);
    }

    function withdraw(uint256 amount) external {
        vault.withdraw(address(token), amount);
    }

    function onERC20Received(address, uint256 amount) external {
        if (_entered) return;
        _entered = true;
        vault.withdraw(address(token), amount);
    }
}
