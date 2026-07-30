// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICrossChainReputation
 * @dev Interface for cross-chain reputation synchronization
 */
interface ICrossChainReputation {
    /**
     * @dev Syncs reputation score across chains.
     */
    function syncReputation(
        uint256 targetChainId,
        address user,
        uint256 score
    ) external returns (bytes32 messageId);

    /**
     * @dev Receives synced reputation from another chain.
     */
    function receiveReputationSync(
        uint256 sourceChainId,
        address user,
        uint256 score
    ) external;
}
