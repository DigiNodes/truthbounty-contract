// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title EvidenceManager
 * @notice Manages immutable, content-addressed evidence references for TruthBounty claims.
 *
 * @dev Evidence files are stored off-chain using IPFS (or compatible decentralized storage).
 *      This contract stores only the cryptographic Content Identifier (CID) — a hash-derived
 *      reference that binds the on-chain record to the exact off-chain content.
 *
 *      Design principles:
 *      - Immutability: once submitted, a CID can never be changed or removed.
 *      - Integrity:    the keccak256 hash of the CID is stored for efficient duplicate detection.
 *      - Extensibility: the storage layout supports future providers (Arweave, Filecoin, Ceramic).
 *      - No external calls: this contract holds no token balances and makes no outbound calls.
 *
 *      Downstream consumers (Verification Engine, Dispute Resolution, Settlement Engine,
 *      Reputation System, Indexer, Frontend) rely on the events and view functions exposed here.
 *
 * @custom:security-contact security@truthbounty.io
 */
contract EvidenceManager is AccessControl, Pausable {
    // =========================================================================
    // Roles
    // =========================================================================

    /// @notice Role that may pause / unpause the contract.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role held by the protocol's claim registry.
    ///         The registry can signal that a claim is closed and no longer
    ///         accepts new evidence (e.g. after settlement).
    bytes32 public constant CLAIM_REGISTRY_ROLE = keccak256("CLAIM_REGISTRY_ROLE");

    // =========================================================================
    // Constants
    // =========================================================================

    /// @notice Maximum byte-length of an accepted CID string.
    ///         CIDv1 base58btc encoded SHA2-256 is 46 chars; base32 is 59 chars.
    ///         We allow up to 512 bytes to accommodate future multihash formats.
    uint256 public constant MAX_CID_LENGTH = 512;

    /// @notice Maximum evidence records attachable to a single claim (V2-SC-038 DoS bound).
    uint256 public constant MAX_EVIDENCE_PER_CLAIM = 100;

    /// @notice Minimum byte-length: a real CID is at least 2 chars (e.g. "Qm…").
    uint256 public constant MIN_CID_LENGTH = 2;

    // =========================================================================
    // Data model
    // =========================================================================

    /**
     * @notice Canonical evidence record stored per claim.
     *
     * Field packing:
     *   - id          : uint256 (slot 0)
     *   - claimId     : uint256 (slot 1)
     *   - uploader    : address (slot 2, 20 bytes)
     *   - uploadedAt  : uint64  (slot 2, 8 bytes — shares with uploader via packing)
     *   - cidHash     : bytes32 (slot 3)
     *   - cid         : string  (slot 4+, dynamic)
     *
     * The struct is ordered to minimise storage slots.
     */
    struct Evidence {
        uint256 id;
        uint256 claimId;
        address uploader;
        uint64 uploadedAt;
        bytes32 cidHash;
        string cid;
    }

    // =========================================================================
    // Storage
    // =========================================================================

    /// @dev Next global evidence ID (monotonically incrementing).
    uint256 private _evidenceCounter;

    /// @dev claimId => ordered list of Evidence records attached to the claim.
    mapping(uint256 => Evidence[]) private _claimEvidence;

    /// @dev evidenceId => Evidence record for O(1) retrieval by global ID.
    mapping(uint256 => Evidence) private _evidenceById;

    /// @dev claimId => cidHash => true when a CID has already been attached.
    ///      Used for O(1) duplicate detection without iterating the array.
    mapping(uint256 => mapping(bytes32 => bool)) private _cidRegistered;

    /// @dev claimId => true when the claim has been closed and no longer accepts evidence.
    mapping(uint256 => bool) private _claimClosed;

    // =========================================================================
    // Errors
    // =========================================================================

    /// @notice Submitted CID is empty or otherwise invalid.
    error InvalidCID();

    /// @notice Submitted CID exceeds MAX_CID_LENGTH.
    error CIDTooLarge();

    /// @notice Submitted CID begins with an unrecognised version prefix.
    error UnsupportedCIDVersion();

    /// @notice Identical CID already attached to this claim.
    error DuplicateEvidence();

    /// @notice The referenced claim does not exist in the registry.
    error ClaimNotFound();

    /// @notice The referenced claim is closed and no longer accepts evidence.
    error ClaimClosed();

    /// @notice Caller supplied an out-of-range index.
    error IndexOutOfBounds();

    /// @notice Evidence with the given global ID does not exist.
    error EvidenceNotFound();

    /// @notice Claim already has the maximum allowed evidence attachments.
    error EvidenceCapacityExceeded(uint256 claimId, uint256 max);

    // =========================================================================
    // Events
    // =========================================================================

    /**
     * @notice Emitted when evidence is successfully attached to a claim.
     *
     * @param claimId    The claim this evidence belongs to.
     * @param evidenceId The global evidence ID assigned to this record.
     * @param uploader   The address that submitted the evidence.
     * @param cid        The content identifier (CID) of the off-chain file.
     */
    event EvidenceAdded(
        uint256 indexed claimId,
        uint256 indexed evidenceId,
        address indexed uploader,
        string cid
    );

    /**
     * @notice Emitted when the CLAIM_REGISTRY_ROLE closes a claim for new evidence.
     *
     * @param claimId The claim that was closed.
     */
    event ClaimClosedForEvidence(uint256 indexed claimId);

    // =========================================================================
    // Constructor
    // =========================================================================

    /**
     * @param initialAdmin Address granted DEFAULT_ADMIN_ROLE, PAUSER_ROLE, and
     *                     CLAIM_REGISTRY_ROLE on deployment.
     */
    constructor(address initialAdmin) {
        require(initialAdmin != address(0), "EvidenceManager: zero admin address");

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);
        _grantRole(CLAIM_REGISTRY_ROLE, initialAdmin);
    }

    // =========================================================================
    // Claim lifecycle integration
    // =========================================================================

    /**
     * @notice Mark a claim as closed for new evidence.
     * @dev    Called by the Claim Registry (or an authorised admin) after a claim
     *         transitions to a state that no longer accepts evidence (e.g. settled,
     *         expired, or disputed). Idempotent — closing an already-closed claim
     *         emits no event and does not revert.
     *
     * @param claimId The claim to close.
     */
    function closeClaimForEvidence(uint256 claimId) external onlyRole(CLAIM_REGISTRY_ROLE) {
        if (!_claimClosed[claimId]) {
            _claimClosed[claimId] = true;
            emit ClaimClosedForEvidence(claimId);
        }
    }

    // =========================================================================
    // Core write function
    // =========================================================================

    /**
     * @notice Attach evidence to a claim by submitting an IPFS CID.
     *
     * @dev Validation sequence (fail-fast order):
     *   1. Contract not paused.
     *   2. CID is non-empty and within length bounds.
     *   3. CID begins with a supported version prefix ("Qm" for CIDv0,
     *      "b", "B", "z", "Z", "F", "f", "k", "K" for CIDv1 multibase).
     *   4. The claim exists (evidenced by not having been explicitly marked
     *      non-existent — the registry can call `notifyClaimCreated` or the
     *      contract trusts any claimId; see note below).
     *   5. The claim is not closed.
     *   6. The CID has not already been attached to this claim.
     *
     * Note on claim existence: EvidenceManager is intentionally decoupled from
     * the Claim Registry contract to avoid circular dependencies and keep the
     * modules independently upgradeable. The registry SHOULD call
     * `closeClaimForEvidence` to signal lifecycle transitions. A future
     * integration point may add an `IClaimRegistry` interface check.
     *
     * @param claimId The claim to attach evidence to.
     * @param cid     An IPFS (or compatible) Content Identifier string.
     */
    function addEvidence(
        uint256 claimId,
        string calldata cid
    ) external whenNotPaused {
        // ── 1. CID length validation ────────────────────────────────────────
        uint256 cidLen = bytes(cid).length;

        if (cidLen < MIN_CID_LENGTH) revert InvalidCID();
        if (cidLen > MAX_CID_LENGTH) revert CIDTooLarge();

        // ── 2. CID version / multibase prefix validation ─────────────────────
        // CIDv0 always starts with "Qm" (base58btc-encoded SHA2-256 multihash).
        // CIDv1 starts with a multibase prefix character:
        //   b / B = base32, z / Z = base58btc, f / F = base16, k / K = base36.
        // Additional future prefixes will be handled via protocol upgrade.
        _validateCIDPrefix(cid);

        // ── 3. Printable ASCII check (guard against malformed Unicode payloads) ─
        _validateCIDChars(cid);

        // ── 4. Claim state checks ────────────────────────────────────────────
        if (_claimClosed[claimId]) revert ClaimClosed();
        if (_claimEvidence[claimId].length >= MAX_EVIDENCE_PER_CLAIM) {
            revert EvidenceCapacityExceeded(claimId, MAX_EVIDENCE_PER_CLAIM);
        }

        // ── 5. Duplicate detection ───────────────────────────────────────────
        bytes32 cidHash = keccak256(bytes(cid));
        if (_cidRegistered[claimId][cidHash]) revert DuplicateEvidence();

        // ── 6. Store ─────────────────────────────────────────────────────────
        uint256 evidenceId = _evidenceCounter;
        unchecked { _evidenceCounter++; }

        Evidence memory ev = Evidence({
            id: evidenceId,
            claimId: claimId,
            uploader: msg.sender,
            uploadedAt: uint64(block.timestamp),
            cidHash: cidHash,
            cid: cid
        });

        _claimEvidence[claimId].push(ev);
        _evidenceById[evidenceId] = ev;
        _cidRegistered[claimId][cidHash] = true;

        emit EvidenceAdded(claimId, evidenceId, msg.sender, cid);
    }

    // =========================================================================
    // View / retrieval functions
    // =========================================================================

    /**
     * @notice Retrieve a single evidence record by its global ID.
     *
     * @param evidenceId Global evidence ID.
     * @return ev        The Evidence struct.
     */
    function getEvidence(uint256 evidenceId) external view returns (Evidence memory ev) {
        ev = _evidenceById[evidenceId];
        if (ev.uploadedAt == 0) revert EvidenceNotFound();
    }

    /**
     * @notice Retrieve all evidence attached to a specific claim.
     *
     * @param claimId The claim ID.
     * @return        Array of Evidence structs (may be empty).
     */
    function getEvidenceByClaim(uint256 claimId) external view returns (Evidence[] memory) {
        return _claimEvidence[claimId];
    }

    /**
     * @notice Retrieve a single evidence item by its position within a claim's list.
     *
     * @param claimId The claim ID.
     * @param index   Zero-based index into the claim's evidence array.
     * @return        The Evidence struct at that position.
     */
    function getEvidenceAtIndex(
        uint256 claimId,
        uint256 index
    ) external view returns (Evidence memory) {
        Evidence[] storage list = _claimEvidence[claimId];
        if (index >= list.length) revert IndexOutOfBounds();
        return list[index];
    }

    /**
     * @notice Return the number of evidence items attached to a claim.
     *
     * @param claimId The claim ID.
     * @return        Count of attached evidence records.
     */
    function getEvidenceCount(uint256 claimId) external view returns (uint256) {
        return _claimEvidence[claimId].length;
    }

    /**
     * @notice Check whether a claim has at least one evidence item.
     *
     * @param claimId The claim ID.
     * @return        True if the claim has ≥ 1 evidence record.
     */
    function hasEvidence(uint256 claimId) external view returns (bool) {
        return _claimEvidence[claimId].length > 0;
    }

    /**
     * @notice Return the address that uploaded a specific evidence item.
     *
     * @param evidenceId Global evidence ID.
     * @return           Uploader address.
     */
    function getEvidenceUploader(uint256 evidenceId) external view returns (address) {
        Evidence storage ev = _evidenceById[evidenceId];
        if (ev.uploadedAt == 0) revert EvidenceNotFound();
        return ev.uploader;
    }

    /**
     * @notice Return the keccak256 hash of a CID stored for a given evidence record.
     *
     * @param evidenceId Global evidence ID.
     * @return           bytes32 CID hash.
     */
    function getEvidenceCIDHash(uint256 evidenceId) external view returns (bytes32) {
        Evidence storage ev = _evidenceById[evidenceId];
        if (ev.uploadedAt == 0) revert EvidenceNotFound();
        return ev.cidHash;
    }

    /**
     * @notice Check whether a specific CID has already been attached to a claim.
     *
     * @param claimId The claim ID.
     * @param cid     The CID string to check.
     * @return        True if the CID is already registered for the claim.
     */
    function isCIDRegistered(uint256 claimId, string calldata cid) external view returns (bool) {
        bytes32 cidHash = keccak256(bytes(cid));
        return _cidRegistered[claimId][cidHash];
    }

    /**
     * @notice Return whether a claim is currently closed for new evidence submissions.
     *
     * @param claimId The claim ID.
     * @return        True if the claim is closed.
     */
    function isClaimClosed(uint256 claimId) external view returns (bool) {
        return _claimClosed[claimId];
    }

    /**
     * @notice Return the next evidence ID that will be assigned.
     * @return Current evidence counter value.
     */
    function evidenceCounter() external view returns (uint256) {
        return _evidenceCounter;
    }

    // =========================================================================
    // Pausable admin
    // =========================================================================

    /// @notice Pause new evidence submissions.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resume evidence submissions.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /**
     * @dev Validate the CID multibase/version prefix.
     *      Reverts with UnsupportedCIDVersion on an unrecognised first character.
     *
     *      Supported prefixes:
     *        "Q"  → CIDv0 (starts "Qm", base58btc SHA2-256)
     *        "b","B" → CIDv1 base32
     *        "z","Z" → CIDv1 base58btc
     *        "f","F" → CIDv1 base16
     *        "k","K" → CIDv1 base36
     *        "u","U" → CIDv1 base64url
     *        "m","M" → CIDv1 base64
     *        "t","T" → CIDv1 base32hexpad
     */
    function _validateCIDPrefix(string calldata cid) internal pure {
        bytes1 prefix = bytes(cid)[0];

        // CIDv0: starts with 'Q' (full "Qm" checked via second byte)
        if (prefix == "Q") {
            if (bytes(cid).length < 2 || bytes(cid)[1] != "m") revert UnsupportedCIDVersion();
            return;
        }

        // CIDv1 multibase prefixes (case-insensitive pairs)
        if (
            prefix == "b" || prefix == "B" || // base32
            prefix == "z" || prefix == "Z" || // base58btc
            prefix == "f" || prefix == "F" || // base16
            prefix == "k" || prefix == "K" || // base36
            prefix == "u" || prefix == "U" || // base64url
            prefix == "m" || prefix == "M" || // base64
            prefix == "t" || prefix == "T"    // base32hexpad
        ) {
            return;
        }

        revert UnsupportedCIDVersion();
    }

    /**
     * @dev Ensure all bytes in the CID string are printable ASCII (0x20–0x7E).
     *      This guards against malformed Unicode or control-character payloads
     *      that could corrupt storage or mislead off-chain consumers.
     *
     *      Note: IPFS CIDs use a strict subset of printable ASCII (alphanumeric
     *      plus a handful of symbols), so this check is safely conservative.
     */
    function _validateCIDChars(string calldata cid) internal pure {
        bytes memory b = bytes(cid);
        uint256 len = b.length;
        for (uint256 i = 0; i < len; ) {
            uint8 c = uint8(b[i]);
            if (c < 0x21 || c > 0x7E) revert InvalidCID();
            unchecked { i++; }
        }
    }
}
