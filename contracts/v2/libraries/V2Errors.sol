// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title V2Errors
/// @notice Canonical custom-error catalog for the TruthBounty V2 protocol.
/// @dev Revert taxonomy (machine-readable, no string reasons):
///
///      | Domain            | Selector family                         | Fail-closed on                          |
///      |-------------------|-----------------------------------------|-----------------------------------------|
///      | Auth / access     | Unauthorized*, ZeroAddress, Zero*       | Missing role, zero identity             |
///      | Claims            | Claim*, CanonicalClaim*, InvalidClaim*  | Missing / duplicate / illegal transition |
///      | Evidence          | Evidence*, DuplicateEvidence, ZeroDigest| Window, digest, nonce, duplicate        |
///      | Verification      | Verification*, AlreadyVerified, Verdict | Window / stake / verdict                |
///      | Settlement        | Settlement*, InvalidRoundTransfer       | Timing, outcome, round integrity        |
///      | Disputes          | Dispute*                                | Window / duplicate / reason             |
///      | Stake / custody   | Insufficient*, UnsupportedAsset, …      | Balances, assets, conservation          |
///      | Aggregation       | InvalidAggregation*, Reputation*        | Score / update failures                 |
///      | Configuration     | Invalid*Range/Duration/Bps, Parameter*  | Invalid set invariants                   |
///      | Governance        | NotGovernance, ZeroGuardian*, Module*   | Authority / allowlist                   |
///      | Slashing          | Slash*, SlashingNotPermitted            | Over-slash / policy                     |
///      | Emergency         | ProtocolPaused, EmergencyAuthority*     | Pause / guardian path                   |
///
///      Modules MUST revert with these selectors (via `V2Errors.<Error>`) instead of
///      `require`/`revert` string reasons or ad-hoc local errors that collide by name
///      but differ by ABI. Prefer typed parameters over `string` reasons.
library V2Errors {
    // =========================================================================
    // Authorization & Access Control
    // =========================================================================

    /// @notice Attempted action by unauthorized caller.
    error Unauthorized();

    /// @notice Attempted action by address(0).
    error ZeroAddress();

    /// @notice Attempted action with zero amount.
    error ZeroAmount();

    /// @notice Attempted action by an unregistered or unauthorized module.
    /// @param caller Address that failed the module authorization check.
    error UnauthorizedModule(address caller);

    /// @notice Zero admin address supplied at construction.
    error ZeroAdmin();

    /// @notice Zero claim-registry address supplied at construction.
    error ZeroClaimRegistry();

    // =========================================================================
    // Claims
    // =========================================================================

    /// @notice Claim not found.
    /// @param claimId Claim identifier that was not found.
    error ClaimNotFound(uint256 claimId);

    /// @notice Canonical claim not found.
    /// @param claimId Canonical claim commitment that was not found.
    error CanonicalClaimNotFound(bytes32 claimId);

    /// @notice Invalid claim state transition.
    /// @param claimId Claim whose requested transition is invalid.
    error InvalidClaimStateTransition(uint256 claimId);

    /// @notice Claim already exists.
    /// @param claimId Existing claim identifier.
    error ClaimAlreadyExists(uint256 claimId);

    /// @notice Canonical claim already exists.
    /// @param claimId Existing canonical claim commitment.
    error CanonicalClaimAlreadyExists(bytes32 claimId);

    /// @notice Invalid claim subject.
    error InvalidClaimSubject();

    /// @notice Invalid claim reward amount.
    error InvalidReward();

    /// @notice Referenced claim id is unknown to the claim registry.
    error InvalidClaim(uint256 claimId);

    /// @notice Claim no longer accepts evidence (finalized / terminal status).
    /// @param status Underlying claim-status enum cast to uint8.
    error ClaimFinalized(uint256 claimId, uint8 status);

    // =========================================================================
    // Evidence
    // =========================================================================

    /// @notice Evidence not found.
    /// @param evidenceId Missing evidence identifier.
    error EvidenceNotFound(uint256 evidenceId);

    /// @notice Invalid evidence content hash.
    error InvalidEvidenceHash();

    /// @notice Evidence submission window closed.
    error EvidenceWindowClosed(uint256 claimId, uint64 deadline, uint64 timestamp);

    /// @notice Duplicate evidence submission.
    error DuplicateEvidence(bytes32 commitmentKey);

    /// @notice Zero content or metadata digest.
    error ZeroDigest();

    /// @notice Contributor nonce mismatch.
    error InvalidNonce(address contributor, uint256 expected, uint256 provided);

    /// @notice Pagination limit out of bounds.
    error InvalidPageLimit(uint256 limit);

    // =========================================================================
    // Verification
    // =========================================================================

    /// @notice Verification not found.
    /// @param verificationId Missing verification identifier.
    error VerificationNotFound(uint256 verificationId);

    /// @notice Verification window closed.
    error VerificationWindowClosed();

    /// @notice Verifier already submitted verification for this claim.
    error AlreadyVerified();

    /// @notice Insufficient stake amount.
    error InsufficientStake();

    /// @notice Invalid verification verdict.
    error InvalidVerdict();

    // =========================================================================
    // Settlement
    // =========================================================================

    /// @notice Settlement not found.
    /// @param claimId Claim without a settlement record.
    error SettlementNotFound(uint256 claimId);

    /// @notice Settlement not executable yet.
    /// @param executeAfter Earliest executable Unix timestamp.
    error SettlementNotExecutable(uint64 executeAfter);

    /// @notice Settlement execution failed.
    error SettlementExecutionFailed();

    /// @notice Invalid settlement amount.
    error InvalidSettlementAmount();

    /// @notice Settlement outcome already recorded for this claim-round.
    /// @param claimId Settlement claim.
    /// @param round Settlement round.
    /// @notice Canonical asset conservation invariant is violated; on-chain balance and accounting buckets must match exactly.
    error ConservationInvariantViolation(address asset, uint256 custody, uint256 obligations, uint256 balance);

    error SettlementAlreadyFinalized(uint256 claimId, uint256 round);

    /// @notice Invalid settlement outcome requested for this claim-round.
    /// @param claimId Settlement claim.
    /// @param round Settlement round.
    error InvalidSettlementOutcome(uint256 claimId, uint256 round);

    /// @notice Round transfer / rollover / carry-forward rejected because from == to.
    error InvalidRoundTransfer(uint256 fromRound, uint256 toRound);

    // =========================================================================
    // Disputes
    // =========================================================================

    /// @notice Dispute not found.
    /// @param disputeId Missing dispute identifier.
    error DisputeNotFound(uint256 disputeId);

    /// @notice Dispute window closed.
    error DisputeWindowClosed();

    /// @notice Dispute already opened.
    error DisputeAlreadyExists();

    /// @notice Invalid dispute reason.
    error InvalidDisputeReason();

    // =========================================================================
    // Stake & Custody
    // =========================================================================

    /// @notice Insufficient stake balance.
    error InsufficientStakeBalance();

    /// @notice Stake withdrawal not permitted.
    error StakeWithdrawalNotPermitted();

    /// @notice Invalid custody reference.
    error InvalidCustodyReference();

    /// @notice Asset is not supported by the custody vault.
    /// @param asset Asset address rejected by configuration.
    error UnsupportedAsset(address asset);

    /// @notice Insufficient claimable balance for the requested operation.
    /// @param account Account whose balance was checked.
    /// @param requested Amount requested.
    /// @param available Available claimable amount.
    error InsufficientClaimable(address account, uint256 requested, uint256 available);

    /// @notice Insufficient locked balance for the requested operation.
    /// @param requested Amount requested.
    /// @param available Available locked amount.
    error InsufficientLocked(uint256 requested, uint256 available);

    /// @notice Insufficient protocol allocation for the requested operation.
    /// @param requested Amount requested.
    /// @param available Available protocol allocation.
    error InsufficientProtocolAllocation(uint256 requested, uint256 available);

    /// @notice Token transfer amount does not match the expected value.
    /// @param expected Amount requested from the token.
    /// @param received Amount actually received.
    error TransferAmountMismatch(uint256 expected, uint256 received);

    /// @notice Recorded obligations exceed on-chain custody for an asset.
    /// @param asset Asset whose accounting failed reconciliation.
    /// @param custody Accounted custody.
    /// @param obligations Sum of recorded obligations.
    error ObligationsExceedCustody(address asset, uint256 custody, uint256 obligations);

    // =========================================================================
    // Aggregation & Reputation
    // =========================================================================

    /// @notice Invalid aggregation result.
    error InvalidAggregationResult();

    /// @notice Reputation update failed.
    error ReputationUpdateFailed();

    /// @notice Invalid reputation score.
    error InvalidReputationScore();

    // =========================================================================
    // Configuration & Parameter Registry
    // =========================================================================

    /// @notice Configuration not found.
    error ConfigurationNotFound();

    /// @notice Invalid parameter version.
    error InvalidParameterVersion();

    /// @notice Parameter update not authorized.
    error ParameterUpdateNotAuthorized();

    /// @notice Caller is not the configured governance authority.
    error NotGovernance(address sender);

    /// @notice Governance address invalid for registry initialization.
    error InvalidGovernance(address governance);

    /// @notice Supported-assets list is empty or otherwise invalid.
    error InvalidSupportedAssets(uint256 assetCount);

    /// @notice Configured asset list exceeds the bounded-execution cap.
    /// @param provided Number of assets supplied.
    /// @param max Maximum assets permitted by ProtocolExecutionBounds.
    error SupportedAssetLimitExceeded(uint256 provided, uint256 max);

    /// @notice Bounty min/max range is inverted or empty.
    error InvalidBountyRange(uint128 minBounty, uint128 maxBounty);

    /// @notice Stake min/max range is inverted or empty.
    error InvalidStakeRange(uint128 minStake, uint128 maxStake);

    /// @notice Duration field is zero or otherwise invalid.
    /// @param field 1=claim, 2=verification, 3=dispute, 4=appeal.
    error InvalidDuration(uint8 field);

    /// @notice Allocation basis-points do not sum to 10_000.
    error InvalidBasisPointsTotal(uint256 totalBps);

    /// @notice Single allocation leg exceeds 10_000 bps.
    error InvalidAllocationBps(uint16 bps);

    /// @notice Weight cap exceeds 10_000 bps.
    error InvalidWeightCap(uint16 weightCapBps);

    /// @notice Participation threshold invalid.
    error InvalidParticipationThreshold(uint24 thresholdBps);

    /// @notice Confidence threshold exceeds 10_000 bps.
    error InvalidConfidenceThreshold(uint16 confidenceBps);

    /// @notice Appeal bond multiplier invalid (zero).
    error InvalidAppealMultiplier(uint24 multiplierBps);

    /// @notice Reputation bound pair invalid.
    error InvalidReputationBounds(uint16 minBps, uint16 maxBps);

    /// @notice Pause / unpause cooldown is zero.
    error InvalidPauseCooldown(uint48 cooldown);

    /// @notice Rounding policy enum out of range.
    error InvalidRoundingPolicy(uint8 roundingPolicy);

    /// @notice Parameter set version already published.
    error ParameterSetAlreadyExists(bytes32 versionId);

    /// @notice Parameter set version not published.
    error ParameterSetNotFound(bytes32 versionId);

    /// @notice Asset adapter already registered.
    error AssetAdapterAlreadySet(address asset);

    // =========================================================================
    // Governance Modules
    // =========================================================================

    /// @notice Zero guardian address.
    error ZeroGuardianAddress();

    /// @notice Zero governor address.
    error ZeroGovernorAddress();

    /// @notice Zero module address in governed registry.
    error ZeroModuleAddress();

    /// @notice Caller is not a guardian.
    error NotGuardian(address caller);

    /// @notice Proposal target is not a governed module.
    error TargetNotGovernedModule(address target);

    /// @notice Guardian module already configured.
    error GovernanceGuardianModuleAlreadySet(address existingModule);

    /// @notice Caller may not set the guardian module.
    error UnauthorizedGuardianModuleSetter(address caller);

    /// @notice Module already registered in the governed allowlist.
    error ModuleAlreadyRegistered(address module);

    /// @notice Module not registered in the governed allowlist.
    error ModuleNotRegistered(address module);

    // =========================================================================
    // Slashing
    // =========================================================================

    /// @notice Slash amount exceeds stake.
    error SlashAmountExceedsStake();

    /// @notice Slashing not permitted for this verifier.
    error SlashingNotPermitted();

    // =========================================================================
    // Emergency Controls
    // =========================================================================

    /// @notice Protocol is paused.
    error ProtocolPaused();

    /// @notice Operation requires emergency authority.
    error EmergencyAuthorityRequired();

    // =========================================================================
    // Generic Validation (typed — avoid string reasons)
    // =========================================================================

    /// @notice Invalid function argument.
    /// @param reason Description of what was invalid.
    error InvalidArgument(string reason);

    /// @notice Operation not supported.
    error NotSupported();

    /// @notice Reentrancy guard detected.
    error ReentrancyDetected();

    // =========================================================================
    // Supply-Chain Attestation Errors (V2-SC-138)
    // =========================================================================

    /// @notice Invalid attestation schema version.
    error InvalidAttestationSchemaVersion();

    /// @notice Empty protocol name in attestation.
    error EmptyProtocolName();

    /// @notice Empty release version in attestation.
    error EmptyReleaseVersion();

    /// @notice Invalid source commit format (must be 40-char lowercase hex).
    error InvalidSourceCommit();

    /// @notice Invalid checksum (zero or malformed).
    error InvalidChecksum();
}
