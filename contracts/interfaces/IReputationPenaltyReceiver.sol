// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Optional adapter used by the slashing engine to notify reputation systems.
interface IReputationPenaltyReceiver {
    function notifySlash(
        address verifier,
        uint256 claimId,
        uint256 slashAmount,
        uint256 slashPercentage,
        bytes32 reasonHash
    ) external;
}
