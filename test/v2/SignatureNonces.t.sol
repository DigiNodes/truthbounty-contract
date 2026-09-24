// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/v2/SignatureNonces.sol";

contract SignatureNoncesHarness is SignatureNonces {
    function consume(address owner, uint256 nonce, uint256 deadline) external {
        _useCheckedNonce(owner, nonce, deadline);
    }
}

contract SignatureNoncesTest is Test {
    SignatureNoncesHarness internal n;
    address internal owner = address(0xA11CE);

    function setUp() public {
        n = new SignatureNoncesHarness();
    }

    function test_ConsumesOnceAndRejectsReplay() public {
        vm.expectEmit(true, true, false, false);
        emit SignatureNonces.NonceConsumed(owner, 7);
        n.consume(owner, 7, block.timestamp);
        assertTrue(n.isNonceUsed(owner, 7));

        vm.expectRevert(abi.encodeWithSelector(SignatureNonces.NonceAlreadyUsed.selector, owner, 7));
        n.consume(owner, 7, block.timestamp);
    }

    function test_NoncesAreUnorderedAndPerOwner() public {
        n.consume(owner, 300, block.timestamp);
        n.consume(owner, 1, block.timestamp);
        assertFalse(n.isNonceUsed(owner, 2));
        assertFalse(n.isNonceUsed(address(0xB0B), 300));
        n.consume(address(0xB0B), 300, block.timestamp);
    }

    function test_RejectsExpiredSignature() public {
        vm.warp(1000);
        vm.expectRevert(abi.encodeWithSelector(SignatureNonces.SignatureExpired.selector, 999));
        n.consume(owner, 1, 999);
        assertFalse(n.isNonceUsed(owner, 1));
    }

    function test_CancelBlocksLaterUse() public {
        vm.prank(owner);
        n.cancelNonce(5);
        vm.expectRevert(abi.encodeWithSelector(SignatureNonces.NonceAlreadyUsed.selector, owner, 5));
        n.consume(owner, 5, block.timestamp);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(SignatureNonces.NonceAlreadyUsed.selector, owner, 5));
        n.cancelNonce(5);
    }

    function test_CancelOnlyAffectsCaller() public {
        vm.prank(address(0xB0B));
        n.cancelNonce(5);
        n.consume(owner, 5, block.timestamp);
    }

    function testFuzz_SingleUse(uint256 nonce, uint256 other) public {
        vm.assume(nonce != other);
        n.consume(owner, nonce, type(uint256).max);
        assertTrue(n.isNonceUsed(owner, nonce));
        assertFalse(n.isNonceUsed(owner, other));
        vm.expectRevert(abi.encodeWithSelector(SignatureNonces.NonceAlreadyUsed.selector, owner, nonce));
        n.consume(owner, nonce, type(uint256).max);
    }
}
