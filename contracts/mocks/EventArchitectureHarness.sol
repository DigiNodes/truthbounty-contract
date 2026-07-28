// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/ITruthBountyEvents.sol";

contract EventArchitectureHarness is ITruthBountyEvents {
    uint16 public constant EVENT_SCHEMA_VERSION = 1;

    function emitClaimCreated(
        uint256 claimId,
        address actor,
        bytes32 metadataHash
    ) external {
        emit ClaimCreated(
            claimId,
            actor,
            metadataHash,
            uint64(block.timestamp),
            EVENT_SCHEMA_VERSION
        );
    }

    function emitVerificationSubmitted(
        uint256 claimId,
        address verifier,
        bool support,
        uint256 stakeAmount
    ) external {
        emit VerificationSubmitted(
            claimId,
            verifier,
            support,
            stakeAmount,
            uint64(block.timestamp),
            EVENT_SCHEMA_VERSION
        );
    }

    function emitSlashExecuted(
        uint256 claimId,
        address verifier,
        bytes32 reason,
        uint256 amount
    ) external {
        emit SlashExecuted(
            claimId,
            verifier,
            reason,
            amount,
            uint64(block.timestamp),
            EVENT_SCHEMA_VERSION
        );
    }
}
