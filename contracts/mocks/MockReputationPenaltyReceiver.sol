// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IReputationPenaltyReceiver.sol";

contract MockReputationPenaltyReceiver is IReputationPenaltyReceiver {
    address public lastVerifier;
    uint256 public lastClaimId;
    uint256 public lastAmount;
    uint256 public lastPercentage;
    bytes32 public lastReasonHash;
    uint256 public notificationCount;

    function notifySlash(
        address verifier,
        uint256 claimId,
        uint256 slashAmount,
        uint256 slashPercentage,
        bytes32 reasonHash
    ) external override {
        lastVerifier = verifier;
        lastClaimId = claimId;
        lastAmount = slashAmount;
        lastPercentage = slashPercentage;
        lastReasonHash = reasonHash;
        notificationCount++;
    }
}
