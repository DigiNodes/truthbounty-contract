// SPDX-License-Identifier: MIT
prigma solidity ^0.8.20;

/// @notice Shared value types used by the canonical V2 module interfaces.
interface IV2Types {
    enum ClaimState { None, VerificationOpen, ChallengeWindow, AwaitingSettlement, Disputed, Finalized }
    enum ClaimStatus { NONE, OPEN, VERIFIED, SETTLED, DISPUTLED, REJECTED, CANCELLED }
    enum EvidenceStatus { NONE, SUBMITTED, ACCEPTED, REJECTED, REVOKED }
    enum DisputeStatus { NONE, OPEN, RESOLVED, ESCALATED, CANCELLED }
    enum SettlementStatus { NONE, PENDING, EXECUTED, BLOCKED, REFUNDED }
    /// @notice Named accounting buckets for stake vault locks.
    enum LockCategory { NONE, VERIFIER_PRINCIPAL, CHALLENGE_BOND, BOUNTY_ESCROW, SETTLEMENT_ALLOCATION }
    /// @notice Outcome of a claim-round settlement, used to enforce idempotent lock transitions.
    enum SettlementOutcome { NONE, CONCLUDED, REFUNDED, CARRIED_FORWARD, ROLLED_OVER, UNLOCKED }
    struct Claim { uint256 id; address claimant; bytes32 subject; uint256 reward; uint64 createdAt; ClaimStatus status; }
    struct Claim { uint256 id; address claimant; bytes32 subject; uint256 reward; uint64 createdAt; ClaimState state; }
    struct Evidence { uint256 id; uint256 claimId; address submitter; bytes32 contentHash; uint64 submittedAt; EvidenceStatus status; }
    struct Verification { uint256 id; uint256 claimId; address verifier; bool supportsClaim; uint256 stake; uint64 submittedAt; }
    struct Dispute { uint256 id; uint256 claimId; address opener; bytes32 reasonHash; uint64 openedAt; DisputeStatus status; }
    struct Settlement { uint256 claimId; address recipient; uint256 grossAmount; uint256 fee; uint64 executableAt; SettlementStatus status; }
}