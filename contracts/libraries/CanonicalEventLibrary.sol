// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/ITruthBountyEvents.sol";

/// @title CanonicalEventLibrary
/// @notice Helper library providing protocol-wide event schema constants and validation utilities.
library CanonicalEventLibrary {
    /// @notice Canonical schema version for all V1 events.
    uint16 public constant EVENT_SCHEMA_VERSION_V1 = 1;

    /// @notice Protocol release identifier commitment.
    bytes32 public constant PROTOCOL_RELEASE_V2 = keccak256("TRUTH_BOUNTY_V2");

    /// @notice Returns current block timestamp cast to uint64 for event emission.
    function currentTimestamp() internal view returns (uint64) {
        return uint64(block.timestamp);
    }

    /// @notice Computes a deterministic metadata hash for off-chain content references.
    /// @param data Raw payload or URI string bytes.
    /// @return hash Keccak256 commitment of the data.
    function computeMetadataHash(bytes memory data) internal pure returns (bytes32 hash) {
        return keccak256(data);
    }

    /// @notice Computes a deterministic operation identifier for financial/treasury actions.
    /// @param domain Domain separator string (e.g. "TREASURY_TRANSFER", "WITHDRAWAL").
    /// @param nonce Monotonic or unique counter.
    /// @param actor Primary entity or operator address.
    /// @return opId Deterministic 32-byte unique operation identifier.
    function computeOperationId(
        string memory domain,
        uint256 nonce,
        address actor
    ) internal pure returns (bytes32 opId) {
        return keccak256(abi.encodePacked(domain, nonce, actor));
    }
}
