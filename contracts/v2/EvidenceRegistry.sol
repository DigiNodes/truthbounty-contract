// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IClaimRegistry} from "../interfaces/IClaimRegistry.sol";
import {ITruthBountyEvents} from "../interfaces/ITruthBountyEvents.sol";
import {IEvidence} from "./interfaces/IEvidence.sol";
import {IV2Module} from "./interfaces/IV2Module.sol";
import {IV2Types} from "./interfaces/IV2Types.sol";
import {ProtocolExecutionBounds} from "../performance/ProtocolExecutionBounds.sol";

/// @title EvidenceRegistry
/// @notice Content-addressed V2 evidence commitment registry.
/// @dev Stores only immutable digests and deterministic IDs. Raw evidence
///      content, CIDs, URLs, signatures, and private data stay off-chain.
contract EvidenceRegistry is ERC165, AccessControl, Pausable, IEvidence, ITruthBountyEvents {
    /// @notice Role allowed to change evidence acceptance status.
    bytes32 public constant EVIDENCE_ADMIN_ROLE = keccak256("EVIDENCE_ADMIN_ROLE");
    /// @notice Role allowed to pause and unpause evidence submission.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Version emitted for canonical evidence events.
    uint16 public constant EVENT_SCHEMA_VERSION = 1;
    /// @notice Maximum evidence IDs returned by one pagination query.
    uint256 public constant MAX_PAGE_SIZE = 100;
    uint256 public constant MAX_EVIDENCE_PER_CLAIM = ProtocolExecutionBounds.MAX_EVIDENCE_PER_CLAIM;

    /// @notice Legacy claim registry used to validate claim existence, status, and verification deadlines.
    IClaimRegistry public immutable claimRegistry;

    struct EvidenceCommitment {
        uint256 id;
        uint256 claimId;
        address contributor;
        bytes32 contentDigest;
        bytes32 metadataDigest;
        uint256 nonce;
        uint64 committedAt;
        IV2Types.EvidenceStatus status;
    }

    mapping(uint256 => EvidenceCommitment) private _evidenceById;
    mapping(uint256 => uint256[]) private _claimEvidenceIds;
    mapping(address => uint256) private _nextContributorNonce;
    mapping(bytes32 => bool) private _commitmentExists;

    /// @notice Constructor was given a zero administrator.
    error ZeroAdmin();
    /// @notice Constructor was given a zero claim registry.
    error ZeroClaimRegistry();
    /// @notice Content or metadata digest was zero.
    error ZeroDigest();
    /// @notice Claim does not exist in the configured registry.
    /// @param claimId Claim that was supplied.
    error InvalidClaim(uint256 claimId);
    /// @notice Evidence arrived after the claim verification deadline.
    /// @param claimId Claim that rejected the evidence.
    /// @param deadline Verification deadline in Unix seconds.
    /// @param timestamp Submission timestamp in Unix seconds.
    error EvidenceWindowClosed(uint256 claimId, uint64 deadline, uint64 timestamp);
    /// @notice Claim status does not accept new evidence.
    /// @param claimId Claim that rejected the evidence.
    /// @param status Current claim status.
    error ClaimFinalized(uint256 claimId, IClaimRegistry.ClaimStatus status);
    /// @notice Supplied contributor nonce was not the next expected nonce.
    /// @param contributor Contributor whose nonce was checked.
    /// @param expected Required next nonce.
    /// @param provided Supplied nonce.
    error InvalidNonce(address contributor, uint256 expected, uint256 provided);
    /// @notice Commitment has already been recorded for the claim and contributor.
    /// @param commitmentKey Deterministic duplicate key.
    error DuplicateEvidence(bytes32 commitmentKey);
    /// @notice Evidence ID does not exist.
    /// @param evidenceId Missing evidence identifier.
    error EvidenceNotFound(uint256 evidenceId);
    /// @notice Pagination limit is zero or exceeds the configured maximum.
    /// @param limit Requested page size.
    error InvalidPageLimit(uint256 limit);
    error EvidenceLimitReached(uint256 claimId, uint256 max);

    /// @notice Emitted for every immutable evidence commitment.
    /// @param claimId Claim receiving the evidence.
    /// @param evidenceId Deterministic evidence identifier.
    /// @param contributor Account that committed the evidence.
    /// @param contentDigest Digest of off-chain content.
    /// @param metadataDigest Digest of off-chain metadata.
    /// @param nonce Contributor sequence number used for identity derivation.
    /// @param timestamp Commit timestamp in Unix seconds.
    /// @param version Event schema version.
    event EvidenceCommitted(
        uint256 indexed claimId,
        uint256 indexed evidenceId,
        address indexed contributor,
        bytes32 contentDigest,
        bytes32 metadataDigest,
        uint256 nonce,
        uint64 timestamp,
        uint16 version
    );

    /// @notice Initializes the registry and grants bootstrap roles to the initial administrator.
    /// @param initialAdmin Account receiving default admin, evidence admin, and pauser roles.
    /// @param claimRegistry_ Legacy claim registry consulted for claim existence and deadlines.
    constructor(address initialAdmin, address claimRegistry_) {
        if (initialAdmin == address(0)) revert ZeroAdmin();
        if (claimRegistry_ == address(0)) revert ZeroClaimRegistry();

        claimRegistry = IClaimRegistry(claimRegistry_);

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(EVIDENCE_ADMIN_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);
    }

    /// @notice Returns the immutable EvidenceRegistry V2 ABI version.
    /// @return major ABI major version.
    /// @return minor ABI minor version.
    function protocolVersion() external pure override returns (uint16 major, uint16 minor) {
        return (2, 0);
    }

    /// @notice Reports supported ERC-165 interfaces for evidence and V2 discovery.
    /// @param interfaceId Interface identifier to query.
    /// @return supported True when the interface is implemented.
    function supportsInterface(bytes4 interfaceId) public view override(ERC165, AccessControl, IERC165) returns (bool supported) {
        return
            interfaceId == type(IV2Module).interfaceId ||
            interfaceId == type(IEvidence).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IEvidence
    function submitEvidence(uint256 claimId, bytes32 contentHash, bytes calldata metadata)
        external
        override
        returns (uint256 evidenceId)
    {
        return commitEvidence(claimId, contentHash, keccak256(metadata), _nextContributorNonce[msg.sender]);
    }

    /// @notice Commit evidence digests to an existing claim.
    /// @dev Permissionless when the claim is active and unpaused, but the registry enforces exact nonce sequencing and duplicate rejection. ID derivation is domain-separated by chain, contract, claim, contributor, digests, and nonce; no raw evidence is stored.
    /// @param claimId Existing claim that receives the evidence commitment.
    /// @param contentDigest Digest of the off-chain evidence content.
    /// @param metadataDigest Digest of off-chain evidence metadata.
    /// @param nonce Contributor nonce used in deterministic evidence ID derivation.
    /// @return evidenceId Deterministic ID bound to the commitment and contributor nonce.
    function commitEvidence(uint256 claimId, bytes32 contentDigest, bytes32 metadataDigest, uint256 nonce)
        public
        whenNotPaused
        returns (uint256 evidenceId)
    {
        if (contentDigest == bytes32(0) || metadataDigest == bytes32(0)) revert ZeroDigest();
        if (!claimRegistry.claimExists(claimId)) revert InvalidClaim(claimId);

        IClaimRegistry.Claim memory claim = claimRegistry.getClaim(claimId);
        if (!_acceptsEvidence(claim.status)) revert ClaimFinalized(claimId, claim.status);

        uint64 now_ = uint64(block.timestamp);
        if (now_ > claim.verificationDeadline) {
            revert EvidenceWindowClosed(claimId, claim.verificationDeadline, now_);
        }

        uint256 expectedNonce = _nextContributorNonce[msg.sender];
        if (nonce != expectedNonce) revert InvalidNonce(msg.sender, expectedNonce, nonce);

        bytes32 commitmentKey = keccak256(abi.encode(claimId, msg.sender, contentDigest, metadataDigest));
        if (_commitmentExists[commitmentKey]) revert DuplicateEvidence(commitmentKey);
        if (_claimEvidenceIds[claimId].length >= MAX_EVIDENCE_PER_CLAIM) {
            revert EvidenceLimitReached(claimId, MAX_EVIDENCE_PER_CLAIM);
        }

        evidenceId = computeEvidenceId(claimId, msg.sender, contentDigest, metadataDigest, nonce);
        _commitmentExists[commitmentKey] = true;
        _nextContributorNonce[msg.sender] = nonce + 1;

        _evidenceById[evidenceId] = EvidenceCommitment({
            id: evidenceId,
            claimId: claimId,
            contributor: msg.sender,
            contentDigest: contentDigest,
            metadataDigest: metadataDigest,
            nonce: nonce,
            committedAt: now_,
            status: IV2Types.EvidenceStatus.SUBMITTED
        });
        _claimEvidenceIds[claimId].push(evidenceId);

        emit EvidenceSubmitted(evidenceId, claimId, msg.sender, contentDigest, uint64(block.timestamp), 1);
        emit EvidenceSubmittedV1(claimId, evidenceId, msg.sender, contentDigest, now_, EVENT_SCHEMA_VERSION);
        emit EvidenceCommitted(
            claimId,
            evidenceId,
            msg.sender,
            contentDigest,
            metadataDigest,
            nonce,
            now_,
            EVENT_SCHEMA_VERSION
        );
    }

    /// @inheritdoc IEvidence
    function setEvidenceStatus(uint256 evidenceId, IV2Types.EvidenceStatus status)
        external
        override
        onlyRole(EVIDENCE_ADMIN_ROLE)
    {
        EvidenceCommitment storage evidence = _evidenceById[evidenceId];
        if (evidence.status == IV2Types.EvidenceStatus.NONE) revert EvidenceNotFound(evidenceId);

        IV2Types.EvidenceStatus previous = evidence.status;
        evidence.status = status;
        emit EvidenceStatusChanged(evidenceId, previous, status, msg.sender, uint64(block.timestamp), 1);
    }

    /// @inheritdoc IEvidence
    function getEvidence(uint256 evidenceId) external view override returns (IV2Types.Evidence memory) {
        EvidenceCommitment storage evidence = _existingEvidence(evidenceId);
        return IV2Types.Evidence({
            id: evidence.id,
            claimId: evidence.claimId,
            submitter: evidence.contributor,
            contentHash: evidence.contentDigest,
            submittedAt: evidence.committedAt,
            status: evidence.status
        });
    }

    /// @notice Returns the full digest commitment for an evidence ID.
    /// @param evidenceId Evidence identifier to read.
    /// @return commitment Full commitment including metadata digest and contributor nonce.
    function getEvidenceCommitment(uint256 evidenceId) external view returns (EvidenceCommitment memory commitment) {
        return _existingEvidence(evidenceId);
    }

    /// @inheritdoc IEvidence
    function claimEvidence(uint256 claimId, uint256 cursor, uint256 limit)
        external
        view
        override
        returns (uint256[] memory evidenceIds, uint256 nextCursor)
    {
        if (limit == 0 || limit > MAX_PAGE_SIZE) revert InvalidPageLimit(limit);

        uint256[] storage ids = _claimEvidenceIds[claimId];
        uint256 length = ids.length;
        if (cursor >= length) return (new uint256[](0), length);

        uint256 end = cursor + limit;
        if (end > length) end = length;

        evidenceIds = new uint256[](end - cursor);
        for (uint256 i = cursor; i < end; ) {
            evidenceIds[i - cursor] = ids[i];
            unchecked {
                ++i;
            }
        }

        return (evidenceIds, end);
    }

    /// @notice Computes the deterministic identifier for a commitment without storing it.
    /// @dev The result is a same-width conversion of the domain-separated keccak256 digest; callers must not use it as proof of commitment existence.
    /// @param claimId Claim identifier.
    /// @param contributor Contributor address.
    /// @param contentDigest Content digest.
    /// @param metadataDigest Metadata digest.
    /// @param nonce Contributor sequence number.
    /// @return evidenceId Deterministic identifier.
    function computeEvidenceId(
        uint256 claimId,
        address contributor,
        bytes32 contentDigest,
        bytes32 metadataDigest,
        uint256 nonce
    ) public view returns (uint256) {
        return uint256(keccak256(abi.encode(block.chainid, address(this), claimId, contributor, contentDigest, metadataDigest, nonce)));
    }

    /// @notice Returns the next required nonce for a contributor.
    /// @param contributor Contributor address.
    /// @return nonce Next nonce accepted for that contributor.
    function nextContributorNonce(address contributor) external view returns (uint256 nonce) {
        return _nextContributorNonce[contributor];
    }

    /// @notice Returns the number of evidence commitments associated with a claim.
    /// @param claimId Claim to inspect.
    /// @return count Commitment count.
    function evidenceCount(uint256 claimId) external view returns (uint256 count) {
        return _claimEvidenceIds[claimId].length;
    }

    /// @notice Pauses evidence submission; existing evidence remains readable.
    /// @dev Pausing is fail-closed for commit operations and is restricted to `PAUSER_ROLE`.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resumes evidence submission after the pauser restores the registry.
    /// @dev Unpausing does not bypass claim deadlines, nonce sequencing, or duplicate checks.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _existingEvidence(uint256 evidenceId) private view returns (EvidenceCommitment storage evidence) {
        evidence = _evidenceById[evidenceId];
        if (evidence.status == IV2Types.EvidenceStatus.NONE) revert EvidenceNotFound(evidenceId);
    }

    function _acceptsEvidence(IClaimRegistry.ClaimStatus status) private pure returns (bool) {
        return status == IClaimRegistry.ClaimStatus.Pending || status == IClaimRegistry.ClaimStatus.UnderVerification;
    }
}
