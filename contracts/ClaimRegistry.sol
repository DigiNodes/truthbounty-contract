// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IClaimRegistry.sol";
import "./interfaces/IParameterVersionRegistry.sol;

/**
 * @title ClaimRegistry
 * @author TruthBounty Protocol
 * @notice Foundational on-chain claim registry for TruthBounty V2.
 *
 * @dev Every claim submitted to the TruthBounty protocol must originate from
 *      this registry. It is the canonical, immutable source of truth for claim
 *      existence, ownership, metadata, and lifecycle state.
 *
 *      Architecture position:
 *      ┌─────────────────────────────────────────────────────────────────┐
 *      │  ClaimRegistry  ← all downstream modules depend on this layer  │
 *      │                                                                 │
 *      │  Depends on:  none (foundational contract)                     │
 *      │  Depended on: Verification Engine, Settlement Engine,          │
 *      │               Reward Distribution, Reputation Engine,          │
 *      │               Dispute Resolution, Indexer, Frontend dApp       │
 *      └─────────────────────────────────────────────────────────────────┘
 *
 *      Design principles:
 *      - No business logic beyond claim creation and retrieval.
 *      - No external calls during claim creation (reentrancy-safe by design).
 *      - Claims are permanently immutable once created.
 *      - Only status transitions are permitted post-creation.
 *      - AccessControl gates status updates to authorised downstream modules.
 *      - Compatible with upgradeable proxy patterns (no constructor state beyond
 *        role setup; storage layout is append-only safe).
 *
 *      Storage layout (v1):
 *      ┌─────────────────────────────────────────────────────────────────┐
 *      │  Slot 0        inherited (AccessControl._roles mapping root)    │
 *      │  ...           inherited OpenZeppelin slots                     │
 *      │  _nextClaimId  uint256  — starts at 1, monotonically growing   │
 *      │  _claims       mapping(uint256 => Claim) — primary store       │
 *      └─────────────────────────────────────────────────────────────────┘
 *      Future fields must be appended after `_claims` to preserve layout.
 *
 *      Input validation limits:
 *      ┌───────────────┬──────────┬──────────┐
 *      │ Field         │ Min      │ Max      │
 *      ├───────────────┼──────────┼──────────┤
 *      │ statement     │ 10 chars │ 2000 ch  │
 *      │ evidenceCID   │ 46 chars │ 128 ch   │
 *      │ deadline      │ now+1s   │ now+MAX  │
 *      └───────────────┴──────────┴──────────┘
 */
contract ClaimRegistry is AccessControl, IClaimRegistry {
    // =========================================================================
    // Roles
    // =========================================================================

    /// @notice Default admin role — can grant and revoke all other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /**
     * @notice Role required to transition a claim's status.
     * @dev Granted to authorised downstream protocol modules (e.g. Verification
     *      Engine, Settlement Engine). Never granted to EOAs in production.
     */
    bytes32 public constant REGISTRY_UPDATER_ROLE = keccak256("REGISTRY_UPDATER_ROLE");

    /// @notice ParameterVersionRegistry instance that tracks versioned economic parameters
    IParameterVersionRegistry public parameterVersionRegistry;

    // =========================================================================
    // Constants — Input Validation
    // =========================================================================

    /// @notice Minimum byte length for a valid claim statement.
    uint256 public constant STATEMENT_MIN_LENGTH = 10;

    /// @notice Maximum byte length for a valid claim statement.
    uint256 public constant STATEMENT_MAX_LENGTH = 2000;

    /// @notice Minimum byte length for a valid IPFS CID.
    /// @dev A base-32 CIDv1 is 59 chars; a base-58 CIDv0 is 46 chars.
    uint256 public constant CID_MIN_LENGTH = 46;

    /// @notice Maximum byte length for an IPFS CID.
    uint256 public constant CID_MAX_LENGTH = 128;

    /**
     * @notice Maximum allowed duration from now to the verification deadline.
     * @dev 365 days — prevents claims with unreasonably distant deadlines that
     *      would lock verifier participation indefinitely.
     */
    uint64 public constant MAX_DEADLINE_HORIZON = 365 days;

    // =========================================================================
    // Storage
    // =========================================================================

    /**
     * @notice Counter tracking the next claim ID to be assigned.
     * @dev Starts at 1 so that ID 0 is always treated as "no claim".
     *      Monotonically increasing; never decremented or reset.
     *      SSTORE occurs once per {createClaim} call.
     */
    uint256 private _nextClaimId;

    /**
     * @notice Primary claim store, keyed by claim ID.
     * @dev Access via {getClaim} / {claimExists} / {getClaimCreator} /
     *      {getClaimStatus} rather than directly to keep downstream modules
     *      decoupled from storage layout.
     */
    mapping(uint256 => Claim) private _claims;

    // =========================================================================
    // Constructor
    // =========================================================================

    /**
     * @param initialAdmin Address that receives DEFAULT_ADMIN_ROLE and ADMIN_ROLE.
     *                     Must be non-zero.
     * @param parameterVersionRegistry_ Address of the deployed ParameterVersionRegistry
     * @dev Sets _nextClaimId = 1 so the first created claim has ID = 1.
     */
    constructor(address initialAdmin, address parameterVersionRegistry_) {
        require(initialAdmin != address(0), "ClaimRegistry: zero admin address");
        require(parameterVersionRegistry_ != address(0), "ClaimRegistry: zero registry address");

        _nextClaimId = 1;
        parameterVersionRegistry = IParameterVersionRegistry(parameterVersionRegistry_);

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);

        // Allow admin to manage REGISTRY_UPDATER_ROLE
        _setRoleAdmin(REGISTRY_UPDATER_ROLE, ADMIN_ROLE);
    }

    // =========================================================================
    // Write Functions
    // =========================================================================

    /**
     * @inheritdoc IClaimRegistry
     *
     * @dev Gas notes:
     *      - Two dynamic strings are stored via SSTORE; this is the most
     *        expensive part of claim creation.
     *      - Struct fields packed in slot 4 (status + createdAt + deadline)
     *        reduce storage cost compared to three separate slots.
     *      - No external calls are made; reentrancy is not possible.
     *
     * @custom:emits ClaimCreated(claimId, msg.sender, evidenceCID)
     */
    function createClaim(
        string calldata statement,
        string calldata evidenceCID,
        uint64 verificationDeadline
    ) external override returns (uint256 claimId) {
        // --- Input validation (revert early to minimise wasted gas) ----------

        uint256 statLen = bytes(statement).length;
        if (statLen < STATEMENT_MIN_LENGTH || statLen > STATEMENT_MAX_LENGTH) {
            revert InvalidStatement();
        }

        uint256 cidLen = bytes(evidenceCID).length;
        if (cidLen < CID_MIN_LENGTH || cidLen > CID_MAX_LENGTH) {
            revert InvalidCID();
        }

        uint64 now_ = uint64(block.timestamp);
        if (verificationDeadline <= now_ || verificationDeadline > now_ + MAX_DEADLINE_HORIZON) {
            revert InvalidDeadline();
        }

        // --- ID assignment ----------------------------------------------------

        claimId = _nextClaimId;
        // Unchecked: uint256 overflow of _nextClaimId would require 2^256
        // claim creations — physically impossible.
        unchecked {
            _nextClaimId = claimId + 1;
        }

        // --- Claim initialisation --------------------------------------------

        // Writing fields individually is more gas-efficient than constructing
        // a memory struct first and then copying it to storage.
        Claim storage c = _claims[claimId];
        c.id = claimId;
        c.creator = msg.sender;
        c.statement = statement;
        c.evidenceCID = evidenceCID;
        // c.status defaults to ClaimStatus.Pending (== 0) — no SSTORE needed.
        c.createdAt = now_;
        c.verificationDeadline = verificationDeadline;

        // --- Link claim to current parameter version for non-retroactivity ----
        parameterVersionRegistry.recordClaimCreation(claimId);

        // --- Event emission --------------------------------------------------

        emit ClaimCreated(claimId, msg.sender, evidenceCID);
    }

    /**
     * @notice Update the ParameterVersionRegistry address (only callable by admin)
     * @param newRegistry The new ParameterVersionRegistry address
     */
    function setParameterVersionRegistry(address newRegistry) external onlyRole(ADMIN_ROLE) {
        if (newRegistry == address(0)) revert("ClaimRegistry: zero address");
        parameterVersionRegistry = IParameterVersionRegistry(newRegistry);
    }

    /**
     * @inheritdoc IClaimRegistry
     *
     * @dev Only accounts holding REGISTRY_UPDATER_ROLE may call this function.
     *      This role is intended for authorised downstream protocol modules only.
     *
     * @custom:emits ClaimStatusUpdated(claimId, oldStatus, newStatus)
     */
    function updateClaimStatus(
        uint256 claimId,
        ClaimStatus newStatus
    ) external override onlyRole(REGISTRY_UPDATER_ROLE) {
        if (_claims[claimId].createdAt == 0) {
            revert ClaimNotFound(claimId);
        }

        ClaimStatus current = _claims[claimId].status;

        // Prevent no-op transitions that waste gas and pollute event logs.
        if (current == newStatus) {
            revert InvalidStatusTransition(current, newStatus);
        }

        _claims[claimId].status = newStatus;

        emit ClaimStatusUpdated(claimId, current, newStatus);
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /**
     * @inheritdoc IClaimRegistry
     */
    function getClaim(uint256 claimId) external view override returns (Claim memory claim) {
        if (_claims[claimId].createdAt == 0) {
            revert ClaimNotFound(claimId);
        }
        return _claims[claimId];
    }

    /**
     * @inheritdoc IClaimRegistry
     */
    function claimExists(uint256 claimId) external view override returns (bool exists) {
        return _claims[claimId].createdAt != 0;
    }

    /**
     * @inheritdoc IClaimRegistry
     */
    function totalClaims() external view override returns (uint256 total) {
        // _nextClaimId starts at 1 and increments per creation, so
        // total = _nextClaimId - 1 (0 before any claims are created).
        unchecked {
            return _nextClaimId - 1;
        }
    }

    /**
     * @inheritdoc IClaimRegistry
     */
    function getClaimCreator(uint256 claimId) external view override returns (address creator) {
        if (_claims[claimId].createdAt == 0) {
            revert ClaimNotFound(claimId);
        }
        return _claims[claimId].creator;
    }

    /**
     * @inheritdoc IClaimRegistry
     */
    function getClaimStatus(uint256 claimId) external view override returns (ClaimStatus status) {
        if (_claims[claimId].createdAt == 0) {
            revert ClaimNotFound(claimId);
        }
        return _claims[claimId].status;
    }
}