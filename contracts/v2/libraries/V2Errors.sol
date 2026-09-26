// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title V2Errors
/// @notice Shared error definitions for the TruthBounty V2 protocol.
/// @dev This library centralizes all protocol-level errors to ensure consistency
///      across all V2 modules and improve maintainability.
library V2Errors {
    // =========================================================================
    // Authorization & Access Control Errors
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

    // =========================================================================
    // Claim-Related Errors
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

    // =========================================================================
    // Evidence-Related Errors
    // =========================================================================

    /// @notice Evidence not found.
    /// @param evidenceId Missing evidence identifier.
    error EvidenceNotFound(uint256 evidenceId);

    /// @notice Invalid evidence content hash.
    error InvalidEvidenceHash();

    /// @notice Evidence submission window closed.
    error EvidenceWindowClosed();

    /// @notice Duplicate evidence submission.
    error DuplicateEvidence();

    // =========================================================================
    // Verification-Related Errors
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
    // Settlement-Related Errors
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

    // =========================================================================
    // Dispute-Related Errors
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
    // Stake & Custody-Related Errors
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

    /// @notice Canonical asset conservation invariant is violated; on-chain balance and accounting buckets must match exactly.
    error ConservationInvariantViolation(address asset, uint256 custody, uint256 obligations, uint256 balance);

    /// @notice Settlement outcome already recorded for this claim-round; repeated or conflicting instructions revert.
    /// @param claimId Settlement claim.
    /// @param round Settlement round.
    error SettlementAlreadyFinalized(uint256 claimId, uint256 round);

    /// @notice Invalid settlement outcome requested for this claim-round.
    /// @param claimId Settlement claim.
    /// @param round Settlement round.
    error InvalidSettlementOutcome(uint256 claimId, uint256 round);

    // =========================================================================
    // Aggregation & Reputation Errors
    // =========================================================================

    /// @notice Invalid aggregation result.
    error InvalidAggregationResult();

    /// @notice Reputation update failed.
    error ReputationUpdateFailed();

    /// @notice Invalid reputation score.
    error InvalidReputationScore();

    // =========================================================================
    // Configuration & Governance Errors
    // =========================================================================

    /// @notice Configuration not found.
    error ConfigurationNotFound();

    /// @notice Invalid parameter version.
    error InvalidParameterVersion();

    /// @notice Parameter update not authorized.
    error ParameterUpdateNotAuthorized();

    // =========================================================================
    // Slashing Errors
    // =========================================================================

    /// @notice Slash amount exceeds stake.
    error SlashAmountExceedsStake();

    /// @notice Slashing not permitted for this verifier.
    error SlashingNotPermitted();

    // =========================================================================
    // Emergency Control Errors
    // =========================================================================

    /// @notice Protocol is paused.
    error ProtocolPaused();

    /// @notice Operation requires emergency authority.
    error EmergencyAuthorityRequired();

    // =========================================================================
    // Module Registry Errors
    // =========================================================================

    /// @notice Module key is not part of the canonical manifest.
    error UnknownModuleId(bytes32 moduleId);

    /// @notice Module key already has a pending or active registration.
    error DuplicateModule(bytes32 moduleId);

    /// @notice Module record does not exist.
    error ModuleNotFound(bytes32 moduleId);

    /// @notice Module is registered but not yet active.
    error ModuleNotActive(bytes32 moduleId);

    /// @notice Module is already ACTIVE; activation is a no-op.
    error AlreadyActive(bytes32 moduleId);

    /// @notice Module key has been deprecated and cannot be (re)activated.
    error DeprecatedModule(bytes32 moduleId);

    /// @notice Address carries no code (an EOA or empty address cannot be a module).
    error ModuleNotAContract(address target);

    /// @notice Attempted self-registration: the registry cannot register itself.
    error SelfRegistration();

    /// @notice A proxy is already bound to another module key (prevents circular authority).
    error DuplicateProxy(address proxy);

    /// @notice Module does not implement the expected canonical interface.
    error ModuleInterfaceMismatch(bytes4 expected, bytes4 actual);

    /// @notice Module protocol version is incompatible with the canonical release.
    error ModuleVersionMismatch(uint16 actualMajor, uint16 expectedMajor);

    /// @notice Declared registration version differs from the live module's reported version.
    error DeclaredVersionMismatch(uint16 declaredMajor, uint16 declaredMinor, uint16 actualMajor, uint16 actualMinor);

    /// @notice Address is on the forbidden legacy list.
    error ForbiddenModule(address implementation);

    /// @notice A required canonical dependency is not active.
    error DependencyUnsatisfied(bytes32 moduleId, bytes32 requiredModuleId);

    /// @notice Replacement proposed with identical content to the current module version.
    error ReplacementNoop(bytes32 moduleId);

    /// @notice No replacement is pending for the module key.
    error ReplacementNotPending(bytes32 moduleId);

    /// @notice Replacement timelock has not elapsed.
    error ReplacementNotReady(bytes32 moduleId, uint256 readyAt);

    /// @notice A zero or ERC-165-invalid interface ID was supplied.
    error InvalidInterfaceId(bytes4 interfaceId);

    /// @notice Guardian role is explicitly excluded from registry mutations.
    error GuardianCannotReplaceModule(address caller);

    /// @notice Denied mutator without the required deployer/governance role.
    error RegistryUnauthorized();

    // =========================================================================
    // Generic Validation Errors
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
