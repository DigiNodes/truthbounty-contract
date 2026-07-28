// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICrossChainGovernance
 * @dev Interface for cross-chain governance operations
 */
interface ICrossChainGovernance {
    /**
     * @dev Broadcasts a governance proposal to a target chain.
     */
    function broadcastProposal(
        uint256 targetChainId,
        address targetContract,
        bytes calldata proposalData
    ) external returns (bytes32 messageId);

    /**
     * @dev Executes an approved cross-chain governance action.
     */
    function executeCrossChainProposal(
        uint256 sourceChainId,
        bytes32 proposalId,
        bytes calldata executionData
    ) external;
}
