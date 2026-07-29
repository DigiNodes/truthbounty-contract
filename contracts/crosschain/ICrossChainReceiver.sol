// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICrossChainReceiver
 * @dev Interface for contracts that can receive cross-chain messages from TruthBounty
 */
interface ICrossChainReceiver {
    /**
     * @dev Handles an incoming cross-chain message.
     * @param sourceChainId The chain ID where the message originated.
     * @param sender The address that sent the message on the source chain.
     * @param payload The encoded message payload.
     */
    function handleCrossChainMessage(
        uint256 sourceChainId,
        address sender,
        bytes calldata payload
    ) external;
}
