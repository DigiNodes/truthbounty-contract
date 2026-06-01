// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/EIP712Verifier.sol";

/**
 * @title EIP712VerifierInvariant
 * @notice Foundry stateful invariant tests for EIP712Verifier (CO-177).
 *
 *  Invariants checked by the fuzzer across arbitrary call sequences:
 *
 *  I1  nonces[addr] is non-decreasing for every address.
 *  I2  getDomainSeparator() always encodes block.chainid.
 *  I3  getDomainSeparator() is never the zero hash.
 *  I4  getChainId() == block.chainid.
 *  I5  usedSignatures[digest] transitions from false → true only (write-once).
 */
contract EIP712VerifierInvariantHandler is Test {

    EIP712Verifier public verifier;

    // Track nonces we have observed to assert monotonicity.
    mapping(address => uint256) public snapshotNonce;
    address[] public touchedAddresses;

    // Track digests we have seen as used so we can assert write-once.
    bytes32[] public usedDigests;
    mapping(bytes32 => bool) public seenUsed;

    constructor(EIP712Verifier _v) {
        verifier = _v;
    }

    // ── ghost-read helpers ────────────────────────────────────────────────

    function touchAddress(address addr) external {
        if (addr == address(0)) return;
        if (snapshotNonce[addr] == 0 && !_known(addr)) {
            touchedAddresses.push(addr);
        }
        snapshotNonce[addr] = verifier.getNonce(addr);
    }

    function _known(address addr) internal view returns (bool) {
        for (uint256 i; i < touchedAddresses.length; i++) {
            if (touchedAddresses[i] == addr) return true;
        }
        return false;
    }

    function recordUsedDigest(bytes32 digest) external {
        if (verifier.isSignatureUsed(digest) && !seenUsed[digest]) {
            seenUsed[digest]  = true;
            usedDigests.push(digest);
        }
    }

    function touchedLength() external view returns (uint256) {
        return touchedAddresses.length;
    }

    function usedDigestsLength() external view returns (uint256) {
        return usedDigests.length;
    }
}

contract EIP712VerifierInvariant is Test {

    EIP712Verifier             public verifier;
    EIP712VerifierInvariantHandler public handler;

    bytes32 constant DOMAIN_TYPE_HASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 constant HASHED_NAME    = keccak256(bytes("TruthBounty"));
    bytes32 constant HASHED_VERSION = keccak256(bytes("1"));

    function setUp() public {
        verifier = new EIP712Verifier();
        handler  = new EIP712VerifierInvariantHandler(verifier);

        // Seed the fuzzer with only the handler as the target so it exercises
        // our ghost functions.
        targetContract(address(handler));
    }

    // ─────────────────────────────────────────────────────────────────────
    // I1  nonce[addr] ≥ snapshotNonce[addr] for every touched address
    // ─────────────────────────────────────────────────────────────────────
    function invariant_I1_NonceMonotone() public {
        uint256 len = handler.touchedLength();
        for (uint256 i; i < len; i++) {
            address addr = handler.touchedAddresses(i);
            assertGe(
                verifier.getNonce(addr),
                handler.snapshotNonce(addr),
                "I1: nonce decreased — violation of monotonicity"
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // I2  getDomainSeparator() encodes block.chainid
    // ─────────────────────────────────────────────────────────────────────
    function invariant_I2_DomainSepEncodesCurrentChainId() public {
        bytes32 expected = keccak256(abi.encode(
            DOMAIN_TYPE_HASH,
            HASHED_NAME,
            HASHED_VERSION,
            block.chainid,
            address(verifier)
        ));
        assertEq(
            verifier.getDomainSeparator(),
            expected,
            "I2: domain separator does not encode current block.chainid"
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    // I3  getDomainSeparator() ≠ bytes32(0)
    // ─────────────────────────────────────────────────────────────────────
    function invariant_I3_DomainSepNonZero() public {
        assertNotEq(
            verifier.getDomainSeparator(),
            bytes32(0),
            "I3: domain separator is zero"
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    // I4  getChainId() == block.chainid
    // ─────────────────────────────────────────────────────────────────────
    function invariant_I4_GetChainIdEqualsBlockChainid() public {
        assertEq(
            verifier.getChainId(),
            block.chainid,
            "I4: getChainId() != block.chainid"
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    // I5  usedSignatures is write-once (once true, stays true)
    // ─────────────────────────────────────────────────────────────────────
    function invariant_I5_UsedSignaturesWriteOnce() public {
        uint256 len = handler.usedDigestsLength();
        for (uint256 i; i < len; i++) {
            bytes32 digest = handler.usedDigests(i);
            assertTrue(
                verifier.isSignatureUsed(digest),
                "I5: a previously used digest is no longer marked as used"
            );
        }
    }
}
