// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IReputationOracle.sol";

/**
 * @title ReputationSnapshot
 * @notice Creates snapshots of reputation data for cross-chain bridging
 * @dev Generates Merkle trees from reputation data for efficient verification.
 *      Includes double-hashed leaves, sorted-pair tree construction, snapshot
 *      expiry, pagination, and a full user-index registry for O(1) lookups.
 */
contract ReputationSnapshot is AccessControl, Pausable {

    // ----------------------------------------------------------------
    // Roles
    // ----------------------------------------------------------------

    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    struct ReputationData {
        address user;
        uint256 score;
        uint256 timestamp;
        uint256 blockNumber;
    }

    struct SnapshotMeta {
        uint256 id;
        uint256 userCount;
        uint256 createdAt;
        uint256 expiresAt;
        bytes32 root;
        bool    finalized;
    }

    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    /// @notice Snapshot validity window — 7 days
    uint256 public constant SNAPSHOT_TTL = 7 days;

    /// @notice Hard cap on users per snapshot to bound gas
    uint256 public constant MAX_SNAPSHOT_SIZE = 1_000;

    // ----------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------

    /// @notice Auto-incrementing snapshot counter
    uint256 private _snapshotCounter;

    /// @notice snapshotId => reputation entries
    mapping(uint256 => ReputationData[]) private _snapshots;

    /// @notice snapshotId => user => index+1 (0 means not present)
    mapping(uint256 => mapping(address => uint256)) private _userIndex;

    /// @notice snapshotId => metadata
    mapping(uint256 => SnapshotMeta) public snapshotMeta;

    /// @notice snapshotId => cached Merkle tree levels (level => nodes)
    mapping(uint256 => mapping(uint256 => bytes32[])) private _merkleTree;

    /// @notice snapshotId => number of tree levels
    mapping(uint256 => uint256) private _treeLevels;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event SnapshotCreated(
        uint256 indexed snapshotId,
        uint256 userCount,
        bytes32 root,
        uint256 expiresAt
    );

    event SnapshotExpired(
        uint256 indexed snapshotId
    );

    event SnapshotFinalized(
        uint256 indexed snapshotId,
        bytes32 root
    );

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error UserNotInSnapshot(address user, uint256 snapshotId);
    error InvalidSnapshot(uint256 snapshotId);
    error SnapshotExpiredError(uint256 snapshotId, uint256 expiredAt);
    error SnapshotTooLarge(uint256 provided, uint256 max);
    error EmptySnapshot();
    error ZeroAddress();
    error DuplicateUser(address user);
    error AlreadyFinalized(uint256 snapshotId);

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SNAPSHOT_ROLE,      admin);
        _grantRole(PAUSER_ROLE,        admin);
    }

    // ----------------------------------------------------------------
    // Admin
    // ----------------------------------------------------------------

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    // ----------------------------------------------------------------
    // Snapshot Creation
    // ----------------------------------------------------------------

    /**
     * @notice Create a snapshot of reputation scores for given users
     * @param users  Array of user addresses — must be unique, no zero addresses
     * @param oracle The reputation oracle to query scores from
     * @return snapshotId The ID of the created snapshot
     */
    function createSnapshot(
        address[] calldata users,
        IReputationOracle oracle
    )
        external
        onlyRole(SNAPSHOT_ROLE)
        whenNotPaused
        returns (uint256 snapshotId)
    {
        uint256 length = users.length;

        if (length == 0)                        revert EmptySnapshot();
        if (length > MAX_SNAPSHOT_SIZE)         revert SnapshotTooLarge(length, MAX_SNAPSHOT_SIZE);

        // Assign ID
        snapshotId = ++_snapshotCounter;

        // ── Collect reputation data ───────────────────────────────────
        bytes32[] memory leaves = new bytes32[](length);

        for (uint256 i = 0; i < length; i++) {
            address user = users[i];

            if (user == address(0))                     revert ZeroAddress();
            if (_userIndex[snapshotId][user] != 0)      revert DuplicateUser(user);

            uint256 score = oracle.getReputationScore(user);

            ReputationData memory entry = ReputationData({
                user:        user,
                score:       score,
                timestamp:   block.timestamp,
                blockNumber: block.number
            });

            _snapshots[snapshotId].push(entry);

            // 1-based index for existence checks
            _userIndex[snapshotId][user] = i + 1;

            // Double-hash leaf to prevent second pre-image attacks
            leaves[i] = _makeLeaf(user, score, block.timestamp);
        }

        // ── Build and cache the full Merkle tree ──────────────────────
        bytes32 root = _buildAndCacheTree(snapshotId, leaves);

        // ── Store metadata ────────────────────────────────────────────
        uint256 expiresAt = block.timestamp + SNAPSHOT_TTL;

        snapshotMeta[snapshotId] = SnapshotMeta({
            id:        snapshotId,
            userCount: length,
            createdAt: block.timestamp,
            expiresAt: expiresAt,
            root:      root,
            finalized: true
        });

        emit SnapshotCreated(snapshotId, length, root, expiresAt);
    }

    // ----------------------------------------------------------------
    // Proof Generation
    // ----------------------------------------------------------------

    /**
     * @notice Get Merkle proof for a user's reputation in a snapshot
     * @param snapshotId The snapshot ID
     * @param user       The user address
     * @return proof The Merkle proof siblings
     * @return index The leaf index
     */
    function getMerkleProof(
        uint256 snapshotId,
        address user
    )
        external
        view
        returns (bytes32[] memory proof, uint256 index)
    {
        _assertValidSnapshot(snapshotId);

        uint256 raw = _userIndex[snapshotId][user];
        if (raw == 0) revert UserNotInSnapshot(user, snapshotId);

        index = raw - 1; // Convert from 1-based
        proof = _generateProofFromCache(snapshotId, index);
    }

    // ----------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------

    /**
     * @notice Get reputation data for a specific user in a snapshot
     */
    function getSnapshotData(
        uint256 snapshotId,
        address user
    ) external view returns (ReputationData memory) {
        uint256 raw = _userIndex[snapshotId][user];
        if (raw == 0) revert UserNotInSnapshot(user, snapshotId);

        return _snapshots[snapshotId][raw - 1];
    }

    /**
     * @notice Get a paginated slice of snapshot entries
     * @param snapshotId The snapshot ID
     * @param offset     Start index
     * @param limit      Max entries to return
     */
    function getSnapshotPage(
        uint256 snapshotId,
        uint256 offset,
        uint256 limit
    ) external view returns (ReputationData[] memory page) {
        ReputationData[] storage data = _snapshots[snapshotId];
        uint256 total = data.length;

        if (offset >= total) return new ReputationData[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        page = new ReputationData[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = data[i];
        }
    }

    /**
     * @notice Check whether a user is included in a snapshot
     */
    function isUserInSnapshot(
        uint256 snapshotId,
        address user
    ) external view returns (bool) {
        return _userIndex[snapshotId][user] != 0;
    }

    /**
     * @notice Return the number of entries in a snapshot
     */
    function getSnapshotLength(uint256 snapshotId)
        external view returns (uint256)
    {
        return _snapshots[snapshotId].length;
    }

    /**
     * @notice Return the latest snapshot ID
     */
    function latestSnapshotId() external view returns (uint256) {
        return _snapshotCounter;
    }

    /**
     * @notice Check whether a snapshot is still valid (not expired)
     */
    function isSnapshotValid(uint256 snapshotId) public view returns (bool) {
        SnapshotMeta storage meta = snapshotMeta[snapshotId];
        return meta.finalized && block.timestamp <= meta.expiresAt;
    }

    // ----------------------------------------------------------------
    // Internal: Merkle Tree
    // ----------------------------------------------------------------

    /**
     * @dev Build the full Merkle tree bottom-up and cache every level.
     *      Uses sorted-pair hashing so proofs are position-independent.
     *      Odd nodes are promoted (not duplicated) to avoid extension attacks.
     */
    function _buildAndCacheTree(
        uint256 snapshotId,
        bytes32[] memory leaves
    ) internal returns (bytes32 root) {
        uint256 length = leaves.length;

        // Cache level 0 (leaves)
        _merkleTree[snapshotId][0] = leaves;

        uint256 level     = 0;
        uint256 levelSize = length;

        while (levelSize > 1) {
            uint256 nextSize   = (levelSize + 1) / 2;
            bytes32[] memory nextLevel = new bytes32[](nextSize);

            bytes32[] storage current = _merkleTree[snapshotId][level];

            for (uint256 i = 0; i < levelSize; i += 2) {
                bytes32 left  = current[i];
                bytes32 right = (i + 1 < levelSize) ? current[i + 1] : left; // promote last if odd

                // Sorted-pair hash: order by value, not position
                nextLevel[i / 2] = left < right
                    ? keccak256(abi.encodePacked(left, right))
                    : keccak256(abi.encodePacked(right, left));
            }

            level++;
            _merkleTree[snapshotId][level] = nextLevel;
            levelSize = nextSize;
        }

        _treeLevels[snapshotId] = level;
        root = _merkleTree[snapshotId][level][0];
    }

    /**
     * @dev Generate a proof by reading sibling nodes from the cached tree.
     *      Because the tree is cached, proof generation is O(log n) reads
     *      rather than recomputing leaves from storage on every call.
     */
    function _generateProofFromCache(
        uint256 snapshotId,
        uint256 leafIndex
    ) internal view returns (bytes32[] memory proof) {
        uint256 levels = _treeLevels[snapshotId];
        proof = new bytes32[](levels);

        uint256 index = leafIndex;

        for (uint256 level = 0; level < levels; level++) {
            bytes32[] storage current = _merkleTree[snapshotId][level];
            uint256 levelSize = current.length;

            uint256 siblingIndex = (index % 2 == 0) ? index + 1 : index - 1;

            // If sibling is out of bounds (odd node was promoted), use self
            proof[level] = (siblingIndex < levelSize)
                ? current[siblingIndex]
                : current[index];

            index /= 2;
        }
    }

    /**
     * @dev Double-hash leaf construction to prevent second pre-image attacks.
     *      Must match the equivalent function in ReputationReceiver exactly.
     */
    function _makeLeaf(
        address user,
        uint256 score,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                keccak256(abi.encodePacked(user, score, timestamp))
            )
        );
    }

    /**
     * @dev Revert if a snapshot does not exist, is not finalized, or has expired.
     */
    function _assertValidSnapshot(uint256 snapshotId) internal view {
        SnapshotMeta storage meta = snapshotMeta[snapshotId];

        if (!meta.finalized)
            revert InvalidSnapshot(snapshotId);

        if (block.timestamp > meta.expiresAt)
            revert SnapshotExpiredError(snapshotId, meta.expiresAt);
    }
}