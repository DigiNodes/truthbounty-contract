// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICrossChainTreasury
 * @dev Interface for cross-chain treasury operations
 */
interface ICrossChainTreasury {
    /**
     * @dev Requests a transfer of funds across chains.
     */
    function requestTransfer(
        uint256 targetChainId,
        address token,
        address recipient,
        uint256 amount
    ) external returns (bytes32 messageId);

    /**
     * @dev Synchronizes treasury accounting across chains.
     */
    function syncAccounting(
        uint256 targetChainId,
        bytes calldata accountingData
    ) external returns (bytes32 messageId);

    /**
     * @dev Receives accounting sync from another chain.
     */
    function receiveAccountingSync(
        uint256 sourceChainId,
        bytes calldata accountingData
    ) external;
}
