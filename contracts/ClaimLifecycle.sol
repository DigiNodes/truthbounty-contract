// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract ClaimLifecycle {
    enum ClaimStatus { Pending, UnderVerification, VerificationEnded, UnderDispute, VerifiedTrue, VerifiedFalse, Inconclusive, Cancelled }

    mapping(uint256 => ClaimStatus) private _status;
    mapping(uint256 => uint256) private _verificationWindowEnd;
    mapping(uint256 => uint256) private _disputeDeadline;

    error InvalidStateTransition(ClaimStatus current, ClaimStatus requested);
    error VerificationDeadlinePassed();
    error VerificationWindowNotEnded();
    error DisputeDeadlinePassed();

    event ClaimStatusChanged(uint256 indexed claimId, ClaimStatus previousStatus, ClaimStatus newStatus, address indexed actor);

    function _canTransition(ClaimStatus current, ClaimStatus next) internal pure returns (bool) {
        if (current == ClaimStatus.Pending) {
            return next == ClaimStatus.UnderVerification || next == ClaimStatus.Cancelled;
        }
        if (current == ClaimStatus.UnderVerification) {
            return next == ClaimStatus.VerificationEnded;
        }
        if (current == ClaimStatus.VerificationEnded) {
            return next == ClaimStatus.VerifiedTrue || next == ClaimStatus.VerifiedFalse || next == ClaimStatus.Inconclusive || next == ClaimStatus.UnderDispute;
        }
        if (current == ClaimStatus.UnderDispute) {
            return next == ClaimStatus.VerifiedTrue || next == ClaimStatus.VerifiedFalse || next == ClaimStatus.Inconclusive;
        }
        return false;
    }

    function _validateTransition(ClaimStatus current, ClaimStatus next) internal pure {
        if (!_canTransition(current, next)) revert InvalidStateTransition(current, next);
    }

    function _changeStatus(uint256 claimId, ClaimStatus newStatus) internal {
        ClaimStatus old = _status[claimId];
        _validateTransition(old, newStatus);
        _status[claimId] = newStatus;
        emit ClaimStatusChanged(claimId, old, newStatus, msg.sender);
    }

    function _startVerification(uint256 claimId, uint256 verificationDeadline, uint256 windowEnd) internal {
        if (block.timestamp > verificationDeadline) revert VerificationDeadlinePassed();
        _verificationWindowEnd[claimId] = windowEnd;
        _changeStatus(claimId, ClaimStatus.UnderVerification);
    }

    function _endVerification(uint256 claimId) internal {
        if (block.timestamp < _verificationWindowEnd[claimId]) revert VerificationWindowNotEnded();
        _changeStatus(claimId, ClaimStatus.VerificationEnded);
    }

    function _markVerifiedTrue(uint256 claimId) internal {
        _changeStatus(claimId, ClaimStatus.VerifiedTrue);
    }

    function _markVerifiedFalse(uint256 claimId) internal {
        _changeStatus(claimId, ClaimStatus.VerifiedFalse);
    }

    function _markInconclusive(uint256 claimId) internal {
        _changeStatus(claimId, ClaimStatus.Inconclusive);
    }

    function _openDispute(uint256 claimId, uint256 deadline) internal {
        if (block.timestamp > deadline) revert DisputeDeadlinePassed();
        _disputeDeadline[claimId] = deadline;
        _changeStatus(claimId, ClaimStatus.UnderDispute);
    }

    function _cancelClaim(uint256 claimId) internal {
        _changeStatus(claimId, ClaimStatus.Cancelled);
    }

    function getClaimStatus(uint256 claimId) public view returns (ClaimStatus) {
        return _status[claimId];
    }

    function isPending(uint256 claimId) public view returns (bool) {
        return _status[claimId] == ClaimStatus.Pending;
    }

    function isUnderVerification(uint256 claimId) public view returns (bool) {
        return _status[claimId] == ClaimStatus.UnderVerification;
    }

    function isResolved(uint256 claimId) public view returns (bool) {
        ClaimStatus s = _status[claimId];
        return s == ClaimStatus.VerifiedTrue || s == ClaimStatus.VerifiedFalse || s == ClaimStatus.Inconclusive || s == ClaimStatus.Cancelled;
    }

    function isDisputed(uint256 claimId) public view returns (bool) {
        return _status[claimId] == ClaimStatus.UnderDispute;
    }

    function canReceiveVotes(uint256 claimId) public view returns (bool) {
        return _status[claimId] == ClaimStatus.UnderVerification;
    }

    function canBeCancelled(uint256 claimId) public view returns (bool) {
        return _status[claimId] == ClaimStatus.Pending;
    }

    function getVerificationWindowEnd(uint256 claimId) public view returns (uint256) {
        return _verificationWindowEnd[claimId];
    }

    function getDisputeDeadline(uint256 claimId) public view returns (uint256) {
        return _disputeDeadline[claimId];
    }

    uint256[50] private __gap;
}
