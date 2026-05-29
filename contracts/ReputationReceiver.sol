// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IReputationOracle.sol";

/**
 * @title ReputationReceiver
 * @notice Receives and verifies bridged reputation data from other chains
 * @dev Verifies Merkle proofs and updates bridged reputation records
 *      with replay protection, pausability, and reentrancy guards
 */
contract ReputationReceiver is AccessControl, ReentrancyGuard, Pausable {

    // ----------------------------------------------------------------
    // Roles
    // ----------------------------------------------------------------

    bytes32 public constant RECEIVER_ROLE  = keccak256("RECEIVER_ROLE");
    bytes32 public constant PAUSER_ROLE    = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE  = keccak256("UPGRADER_ROLE");

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    IReputationOracle public reputationOracle;

    /// @notice user => sourceChainId => score
    mapping(address => mapping(uint256 => uint256)) public bridgedReputations;

    /// @notice user => sourceChainId => timestamp of last bridge
    mapping(address => mapping(uint256 => uint256)) public lastBridgedAt;

    /// @notice sourceChainId => snapshotId => root
    mapping(uint256 => mapping(uint256 => bytes32)) public verifiedRoots;

    /// @notice Replay protection: tracks already-used proof leaves
    /// leafHash => used
    mapping(bytes32 => bool) public usedLeaves;

    /// @notice Scoring weights per source chain (basis points, 10000 = 100%)
    /// sourceChainId => weight
    mapping(uint256 => uint256) public chainWeights;

    /// @notice Supported source chains
    mapping(uint256 => bool) public supportedChains;

    /// @notice Maximum reputation score accepted from any chain
    uint256 public constant MAX_SCORE = 10_000;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event ReputationBridged(
        address indexed user,
        uint256 indexed sourceChainId,
        uint256 score,
        uint256 timestamp
    );

    event SnapshotRootVerified(
        uint256 indexed sourceChainId,
        uint256 indexed snapshotId,
        bytes32 root
    );

    event OracleUpdated(
        address indexed oldOracle,
        address indexed newOracle
    );

    event ChainWeightUpdated(
        uint256 indexed sourceChainId,
        uint256 weight
    );

    event ChainSupportToggled(
        uint256 indexed sourceChainId,
        bool supported
    );

    event ReputationRevoked(
        address indexed user,
        uint256 indexed sourceChainId
    );

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error InvalidProof();
    error RootNotVerified();
    error LeafAlreadyUsed();
    error UnsupportedChain(uint256 chainId);
    error ScoreExceedsMax(uint256 score);
    error ZeroAddress();
    error InvalidWeight(uint256 weight);
    error InvalidSnapshotId();
    error StaleTimestamp(uint256 provided, uint256 current);

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    constructor(address admin, IReputationOracle _oracle) {
        if (admin == address(0))   revert ZeroAddress();
        if (address(_oracle) == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RECEIVER_ROLE,      admin);
        _grantRole(PAUSER_ROLE,        admin);
        _grantRole(UPGRADER_ROLE,      admin);

        reputationOracle = _oracle;
    }

    // ----------------------------------------------------------------
    // Admin: Configuration
    // ----------------------------------------------------------------

    /**
     * @notice Update the reputation oracle address
     * @param newOracle Address of the new oracle contract
     */
    function setOracle(address newOracle)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newOracle == address(0)) revert ZeroAddress();

        emit OracleUpdated(address(reputationOracle), newOracle);
        reputationOracle = IReputationOracle(newOracle);
    }

    /**
     * @notice Enable or disable a source chain
     * @param sourceChainId The chain ID to toggle
     * @param supported Whether the chain is supported
     */
    function setChainSupport(uint256 sourceChainId, bool supported)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        supportedChains[sourceChainId] = supported;
        emit ChainSupportToggled(sourceChainId, supported);
    }

    /**
     * @notice Set the score weight for a source chain (in basis points)
     * @param sourceChainId The chain ID
     * @param weight Weight in BPS (e.g. 8000 = 80%)
     */
    function setChainWeight(uint256 sourceChainId, uint256 weight)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (weight > BPS) revert InvalidWeight(weight);

        chainWeights[sourceChainId] = weight;
        emit ChainWeightUpdated(sourceChainId, weight);
    }

    /**
     * @notice Revoke a user's bridged reputation from a chain
     * @param user The user address
     * @param sourceChainId The source chain ID
     */
    function revokeReputation(address user, uint256 sourceChainId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        delete bridgedReputations[user][sourceChainId];
        delete lastBridgedAt[user][sourceChainId];

        emit ReputationRevoked(user, sourceChainId);
    }

    /**
     * @notice Pause all bridging operations
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause bridging operations
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ----------------------------------------------------------------
    // Receiver: Root Verification
    // ----------------------------------------------------------------

    /**
     * @notice Verify and store a snapshot root from a source chain
     * @param sourceChainId The ID of the source chain
     * @param snapshotId    The snapshot ID
     * @param root          The Merkle root to store
     */
    function verifySnapshotRoot(
        uint256 sourceChainId,
        uint256 snapshotId,
        bytes32 root
    )
        external
        onlyRole(RECEIVER_ROLE)
        whenNotPaused
    {
        if (!supportedChains[sourceChainId])
            revert UnsupportedChain(sourceChainId);
        if (snapshotId == 0) revert InvalidSnapshotId();

        verifiedRoots[sourceChainId][snapshotId] = root;

        emit SnapshotRootVerified(sourceChainId, snapshotId, root);
    }

    // ----------------------------------------------------------------
    // Receiver: Bridging
    // ----------------------------------------------------------------

    /**
     * @notice Receive bridged reputation with full Merkle proof verification
     * @param user          The user address
     * @param sourceChainId The source chain ID
     * @param snapshotId    The snapshot ID
     * @param score         The reputation score
     * @param timestamp     The timestamp from the snapshot
     * @param proof         The Merkle proof siblings
     * @param proofIndex    The leaf index in the Merkle tree
     */
    function receiveBridgedReputation(
        address user,
        uint256 sourceChainId,
        uint256 snapshotId,
        uint256 score,
        uint256 timestamp,
        bytes32[] calldata proof,
        uint256 proofIndex
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(RECEIVER_ROLE)
    {
        // ── Validate inputs ──────────────────────────────────────────
        if (user == address(0))                  revert ZeroAddress();
        if (!supportedChains[sourceChainId])     revert UnsupportedChain(sourceChainId);
        if (score > MAX_SCORE)                   revert ScoreExceedsMax(score);

        // Reject timestamps more than 1 hour in the future
        if (timestamp > block.timestamp + 1 hours)
            revert StaleTimestamp(timestamp, block.timestamp);

        // ── Root lookup ──────────────────────────────────────────────
        bytes32 root = verifiedRoots[sourceChainId][snapshotId];
        if (root == bytes32(0)) revert RootNotVerified();

        // ── Build and verify leaf ────────────────────────────────────
        bytes32 leaf = _makeLeaf(user, score, timestamp);

        // ── Replay protection ────────────────────────────────────────
        if (usedLeaves[leaf]) revert LeafAlreadyUsed();

        if (!_verifyProof(leaf, proof, root, proofIndex))
            revert InvalidProof();

        // ── Effects (CEI pattern) ────────────────────────────────────
        usedLeaves[leaf]                          = true;
        bridgedReputations[user][sourceChainId]   = score;
        lastBridgedAt[user][sourceChainId]        = block.timestamp;

        emit ReputationBridged(user, sourceChainId, score, block.timestamp);
    }

    // ----------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------

    /**
     * @notice Get bridged reputation for a user from a specific chain
     */
    function getBridgedReputation(
        address user,
        uint256 sourceChainId
    ) external view returns (uint256) {
        return bridgedReputations[user][sourceChainId];
    }

    /**
     * @notice Get the weighted combined reputation across local + bridged sources
     * @dev Local score is weighted at full BPS; bridged score uses per-chain weight
     * @param user          The user address
     * @param sourceChainId The bridged source chain to include
     */
    function getCombinedReputation(
        address user,
        uint256 sourceChainId
    ) external view returns (uint256) {
        uint256 localScore   = reputationOracle.getReputationScore(user);
        uint256 bridgedScore = bridgedReputations[user][sourceChainId];

        if (localScore == 0 && bridgedScore == 0) return 0;
        if (localScore == 0) return _applyWeight(bridgedScore, sourceChainId);
        if (bridgedScore == 0) return localScore;

        uint256 weightedBridged = _applyWeight(bridgedScore, sourceChainId);

        // Weighted average: full local + weighted bridged, divided by 2
        return (localScore + weightedBridged) / 2;
    }

    /**
     * @notice Check whether a leaf has already been used
     * @param user      The user address
     * @param score     The score included in the leaf
     * @param timestamp The timestamp included in the leaf
     */
    function isLeafUsed(
        address user,
        uint256 score,
        uint256 timestamp
    ) external view returns (bool) {
        return usedLeaves[_makeLeaf(user, score, timestamp)];
    }

    /**
     * @notice Check if a root has been verified for a given chain + snapshot
     */
    function isRootVerified(
        uint256 sourceChainId,
        uint256 snapshotId
    ) external view returns (bool) {
        return verifiedRoots[sourceChainId][snapshotId] != bytes32(0);
    }

    // ----------------------------------------------------------------
    // Internal Helpers
    // ----------------------------------------------------------------

    /**
     * @dev Canonical leaf construction — must match off-chain tree builder exactly
     *      Double-hashed to prevent second pre-image attacks
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
     * @dev Standard index-aware Merkle proof verification
     * @param leaf       The leaf hash
     * @param proof      Sibling hashes
     * @param root       The expected root
     * @param index      Leaf position in the tree
     */
    function _verifyProof(
        bytes32 leaf,
        bytes32[] memory proof,
        bytes32 root,
        uint256 index
    ) internal pure returns (bool) {
        bytes32 computed = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            computed = (index % 2 == 0)
                ? keccak256(abi.encodePacked(computed, proof[i]))
                : keccak256(abi.encodePacked(proof[i], computed));

            index /= 2;
        }

        return computed == root;
    }

    /**
     * @dev Apply a chain's configured weight (in BPS) to a score
     *      Falls back to full weight (BPS) if no weight is configured
     */
    function _applyWeight(
        uint256 score,
        uint256 sourceChainId
    ) internal view returns (uint256) {
        uint256 weight = chainWeights[sourceChainId];

        // Default to full weight if not explicitly configured
        if (weight == 0) return score;

        return (score * weight) / BPS;
    }
}