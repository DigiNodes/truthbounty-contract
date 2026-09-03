// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../ClaimLifecycle.sol";

contract ClaimLifecycleTestWrapper is ClaimLifecycle {
    function startVerification(uint256 claimId, uint256 verificationDeadline, uint256 windowEnd) external {
        _startVerification(claimId, verificationDeadline, windowEnd);
    }

    function endVerification(uint256 claimId) external {
        _endVerification(claimId);
    }

    function markVerifiedTrue(uint256 claimId) external {
        _markVerifiedTrue(claimId);
    }

    function markVerifiedFalse(uint256 claimId) external {
        _markVerifiedFalse(claimId);
    }

    function markInconclusive(uint256 claimId) external {
        _markInconclusive(claimId);
    }

    function openDispute(uint256 claimId, uint256 deadline) external {
        _openDispute(claimId, deadline);
    }

    function cancelClaim(uint256 claimId) external {
        _cancelClaim(claimId);
    }

    function canTransition(ClaimStatus current, ClaimStatus next) external pure returns (bool) {
        return _canTransition(current, next);
    }

    function validateTransition(ClaimStatus current, ClaimStatus next) external pure {
        _validateTransition(current, next);
    }

    function changeStatus(uint256 claimId, ClaimStatus newStatus) external {
        _changeStatus(claimId, newStatus);
    }
}
