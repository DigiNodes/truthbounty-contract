// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IV2Types} from "../interfaces/IV2Types.sol";
import {V2Errors} from "./V2Errors.sol";

/// @title V2Lifecycle
/// @notice Shared lifecycle and state machine logic for the TruthBounty V2 protocol.
/// @dev Provides reusable utilities for managing entity state transitions and lifecycle events.
library V2Lifecycle {
    // =========================================================================
    // Claim Lifecycle Utilities
    // =========================================================================

    /// @notice Validates a claim state transition according to the protocol state machine.
    /// @dev Implements the canonical claim lifecycle:
    ///      NONE -> OPEN -> [VERIFIED | SETTLED | DISPUTED | REJECTED | CANCELLED]
    /// @param currentStatus The current claim status.
    /// @param nextStatus The target claim status.
    /// @return true if the transition is valid, false otherwise.
    function isValidClaimTransition(
        IV2Types.ClaimStatus currentStatus,
        IV2Types.ClaimStatus nextStatus
    ) internal pure returns (bool) {
        // Transition from NONE (initial state)
        if (currentStatus == IV2Types.ClaimStatus.NONE) {
            return nextStatus == IV2Types.ClaimStatus.OPEN;
        }

        // Transition from OPEN
        if (currentStatus == IV2Types.ClaimStatus.OPEN) {
            return nextStatus == IV2Types.ClaimStatus.VERIFIED ||
                   nextStatus == IV2Types.ClaimStatus.SETTLED ||
                   nextStatus == IV2Types.ClaimStatus.DISPUTED ||
                   nextStatus == IV2Types.ClaimStatus.REJECTED ||
                   nextStatus == IV2Types.ClaimStatus.CANCELLED;
        }

        // Transition from VERIFIED
        if (currentStatus == IV2Types.ClaimStatus.VERIFIED) {
            return nextStatus == IV2Types.ClaimStatus.SETTLED ||
                   nextStatus == IV2Types.ClaimStatus.CANCELLED;
        }

        // Transition from SETTLED (terminal state)
        if (currentStatus == IV2Types.ClaimStatus.SETTLED) {
            return false; // No transitions from terminal state
        }

        // Transition from DISPUTED
        if (currentStatus == IV2Types.ClaimStatus.DISPUTED) {
            return nextStatus == IV2Types.ClaimStatus.VERIFIED ||
                   nextStatus == IV2Types.ClaimStatus.REJECTED;
        }

        // Transition from REJECTED (terminal state)
        if (currentStatus == IV2Types.ClaimStatus.REJECTED) {
            return false; // No transitions from terminal state
        }

        // Transition from CANCELLED (terminal state)
        if (currentStatus == IV2Types.ClaimStatus.CANCELLED) {
            return false; // No transitions from terminal state
        }

        return false;
    }

    /// @notice Enforces a claim state transition, reverting if invalid.
    /// @param currentStatus The current claim status.
    /// @param nextStatus The target claim status.
    function enforceValidClaimTransition(
        IV2Types.ClaimStatus currentStatus,
        IV2Types.ClaimStatus nextStatus
    ) internal pure {
        if (!isValidClaimTransition(currentStatus, nextStatus)) {
            revert V2Errors.InvalidClaimStateTransition(0); // claimId would be passed by caller
        }
    }

    /// @notice Checks if a claim is in a terminal state.
    /// @param status The claim status to check.
    /// @return true if the status is terminal (SETTLED, REJECTED, or CANCELLED).
    function isTerminalClaimStatus(IV2Types.ClaimStatus status) internal pure returns (bool) {
        return status == IV2Types.ClaimStatus.SETTLED ||
               status == IV2Types.ClaimStatus.REJECTED ||
               status == IV2Types.ClaimStatus.CANCELLED;
    }

    /// @notice Checks if a claim is still under active consideration (not terminal).
    /// @param status The claim status to check.
    /// @return true if the claim can still transition to other states.
    function isActiveClaimStatus(IV2Types.ClaimStatus status) internal pure returns (bool) {
        return !isTerminalClaimStatus(status);
    }

    // =========================================================================
    // Evidence Lifecycle Utilities
    // =========================================================================

    /// @notice Validates an evidence state transition.
    /// @dev Implements the evidence lifecycle:
    ///      NONE -> SUBMITTED -> [ACCEPTED | REJECTED | REVOKED]
    /// @param currentStatus The current evidence status.
    /// @param nextStatus The target evidence status.
    /// @return true if the transition is valid, false otherwise.
    function isValidEvidenceTransition(
        IV2Types.EvidenceStatus currentStatus,
        IV2Types.EvidenceStatus nextStatus
    ) internal pure returns (bool) {
        // Transition from NONE (initial state)
        if (currentStatus == IV2Types.EvidenceStatus.NONE) {
            return nextStatus == IV2Types.EvidenceStatus.SUBMITTED;
        }

        // Transition from SUBMITTED
        if (currentStatus == IV2Types.EvidenceStatus.SUBMITTED) {
            return nextStatus == IV2Types.EvidenceStatus.ACCEPTED ||
                   nextStatus == IV2Types.EvidenceStatus.REJECTED ||
                   nextStatus == IV2Types.EvidenceStatus.REVOKED;
        }

        // Transition from ACCEPTED
        if (currentStatus == IV2Types.EvidenceStatus.ACCEPTED) {
            return nextStatus == IV2Types.EvidenceStatus.REVOKED;
        }

        // Transitions from terminal states
        if (currentStatus == IV2Types.EvidenceStatus.REJECTED ||
            currentStatus == IV2Types.EvidenceStatus.REVOKED) {
            return false;
        }

        return false;
    }

    // =========================================================================
    // Dispute Lifecycle Utilities
    // =========================================================================

    /// @notice Validates a dispute state transition.
    /// @dev Implements the dispute lifecycle:
    ///      NONE -> OPEN -> [RESOLVED | ESCALATED | CANCELLED]
    /// @param currentStatus The current dispute status.
    /// @param nextStatus The target dispute status.
    /// @return true if the transition is valid, false otherwise.
    function isValidDisputeTransition(
        IV2Types.DisputeStatus currentStatus,
        IV2Types.DisputeStatus nextStatus
    ) internal pure returns (bool) {
        // Transition from NONE (initial state)
        if (currentStatus == IV2Types.DisputeStatus.NONE) {
            return nextStatus == IV2Types.DisputeStatus.OPEN;
        }

        // Transition from OPEN
        if (currentStatus == IV2Types.DisputeStatus.OPEN) {
            return nextStatus == IV2Types.DisputeStatus.RESOLVED ||
                   nextStatus == IV2Types.DisputeStatus.ESCALATED ||
                   nextStatus == IV2Types.DisputeStatus.CANCELLED;
        }

        // Transitions from terminal states
        if (currentStatus == IV2Types.DisputeStatus.RESOLVED ||
            currentStatus == IV2Types.DisputeStatus.ESCALATED ||
            currentStatus == IV2Types.DisputeStatus.CANCELLED) {
            return false;
        }

        return false;
    }

    // =========================================================================
    // Settlement Lifecycle Utilities
    // =========================================================================

    /// @notice Validates a settlement state transition.
    /// @dev Implements the settlement lifecycle:
    ///      NONE -> PENDING -> [EXECUTED | BLOCKED | REFUNDED]
    /// @param currentStatus The current settlement status.
    /// @param nextStatus The target settlement status.
    /// @return true if the transition is valid, false otherwise.
    function isValidSettlementTransition(
        IV2Types.SettlementStatus currentStatus,
        IV2Types.SettlementStatus nextStatus
    ) internal pure returns (bool) {
        // Transition from NONE (initial state)
        if (currentStatus == IV2Types.SettlementStatus.NONE) {
            return nextStatus == IV2Types.SettlementStatus.PENDING;
        }

        // Transition from PENDING
        if (currentStatus == IV2Types.SettlementStatus.PENDING) {
            return nextStatus == IV2Types.SettlementStatus.EXECUTED ||
                   nextStatus == IV2Types.SettlementStatus.BLOCKED ||
                   nextStatus == IV2Types.SettlementStatus.REFUNDED;
        }

        // Transitions from terminal states
        if (currentStatus == IV2Types.SettlementStatus.EXECUTED ||
            currentStatus == IV2Types.SettlementStatus.BLOCKED ||
            currentStatus == IV2Types.SettlementStatus.REFUNDED) {
            return false;
        }

        return false;
    }

    /// @notice Checks if a settlement is in a terminal state.
    /// @param status The settlement status to check.
    /// @return true if the status is terminal (EXECUTED, BLOCKED, or REFUNDED).
    function isTerminalSettlementStatus(IV2Types.SettlementStatus status) internal pure returns (bool) {
        return status == IV2Types.SettlementStatus.EXECUTED ||
               status == IV2Types.SettlementStatus.BLOCKED ||
               status == IV2Types.SettlementStatus.REFUNDED;
    }

    // =========================================================================
    // Status Query Utilities
    // =========================================================================

    /// @notice Checks if a claim is open and accepting verifications.
    /// @param status The claim status.
    /// @return true if the claim is open.
    function isClaimOpen(IV2Types.ClaimStatus status) internal pure returns (bool) {
        return status == IV2Types.ClaimStatus.OPEN;
    }

    /// @notice Checks if a claim has been verified.
    /// @param status The claim status.
    /// @return true if the claim has been verified (VERIFIED status).
    function isClaimVerified(IV2Types.ClaimStatus status) internal pure returns (bool) {
        return status == IV2Types.ClaimStatus.VERIFIED;
    }

    /// @notice Checks if a claim is under dispute.
    /// @param status The claim status.
    /// @return true if the claim is disputed.
    function isClaimDisputed(IV2Types.ClaimStatus status) internal pure returns (bool) {
        return status == IV2Types.ClaimStatus.DISPUTED;
    }

    /// @notice Checks if a settlement can be executed.
    /// @param status The settlement status.
    /// @param currentTime The current block timestamp.
    /// @param executeAfter The settlement execution time.
    /// @return true if the settlement is pending and the timelock has expired.
    function canExecuteSettlement(
        IV2Types.SettlementStatus status,
        uint256 currentTime,
        uint64 executeAfter
    ) internal pure returns (bool) {
        return status == IV2Types.SettlementStatus.PENDING && currentTime >= executeAfter;
    }

    // =========================================================================
    // Time-Based Validation Utilities
    // =========================================================================

    /// @notice Validates that a deadline has not passed.
    /// @param deadline The deadline timestamp.
    /// @return true if the deadline has not passed.
    function isDeadlineValid(uint64 deadline) internal view returns (bool) {
        return block.timestamp <= deadline;
    }

    /// @notice Validates that a deadline has passed.
    /// @param deadline The deadline timestamp.
    /// @return true if the deadline has passed.
    function isDeadlineExpired(uint64 deadline) internal view returns (bool) {
        return block.timestamp > deadline;
    }

    /// @notice Computes the remaining time until a deadline.
    /// @param deadline The deadline timestamp.
    /// @return remaining The remaining time in seconds, or 0 if deadline has passed.
    function timeUntilDeadline(uint64 deadline) internal view returns (uint256 remaining) {
        if (block.timestamp >= deadline) {
            return 0;
        }
        unchecked {
            return deadline - block.timestamp;
        }
    }
}
