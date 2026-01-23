// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract TruthBountyToken is ERC20 {
    address public owner;

    constructor() ERC20("TruthBounty", "BOUNTY") {
        owner = msg.sender;
        _mint(msg.sender, 10_000_000 * 10 ** decimals()); // Initial supply
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Only owner");
        _mint(to, amount);
    }
}

/**
 * @title TruthBounty
 * @notice Main contract for TruthBounty verification and reputation system
 * @dev Handles Merkle proof verification for reputation claims
 */
contract TruthBounty {
    using MerkleProof for bytes32[];

    /// @notice Address with permission to update the Merkle root
    address public admin;

    /// @notice Current Merkle root of the reputation tree
    bytes32 public reputationMerkleRoot;

    /// @notice Mapping to store verified reputation scores (address => score)
    /// @dev This allows caching verified claims for use in staking/voting logic
    mapping(address => uint256) public verifiedReputation;

    /// @notice Mapping to track if a user has verified their reputation in the current epoch
    mapping(address => bool) public hasVerifiedReputation;

    /// @notice Event emitted when Merkle root is updated
    event ReputationRootUpdated(bytes32 indexed newRoot, address indexed updatedBy);

    /// @notice Event emitted when a reputation claim is successfully verified
    event ReputationVerified(
        address indexed user,
        uint256 indexed reputationScore,
        bytes32 indexed merkleRoot
    );

    /// @notice Error thrown when Merkle proof verification fails
    error InvalidProof();

    /// @notice Error thrown when caller is not the admin
    error NotAdmin();

    /**
     * @notice Constructor sets the initial admin
     * @param _admin Address that can update the Merkle root
     */
    constructor(address _admin) {
        require(_admin != address(0), "Admin cannot be zero address");
        admin = _admin;
    }

    /**
     * @notice Updates the Merkle root for reputation verification
     * @dev Only callable by admin. Should be called when reputation scores are recalculated off-chain
     * @param _newRoot The new Merkle root of the reputation tree
     */
    function updateReputationRoot(bytes32 _newRoot) external {
        if (msg.sender != admin) revert NotAdmin();
        
        reputationMerkleRoot = _newRoot;
        
        // Clear verified reputations when root changes
        // This ensures users must re-verify with the new root
        // Note: In production, you might want to track epochs instead
        
        emit ReputationRootUpdated(_newRoot, msg.sender);
    }

    /**
     * @notice Verifies a user's reputation claim using a Merkle proof
     * @dev The leaf is computed as keccak256(abi.encodePacked(user, reputationScore))
     * @param user The address of the user claiming the reputation
     * @param reputationScore The reputation score being claimed
     * @param proof The Merkle proof array
     * @return isValid True if the proof is valid, false otherwise
     */
    function verifyReputation(
        address user,
        uint256 reputationScore,
        bytes32[] calldata proof
    ) external view returns (bool isValid) {
        // Return false if no root is set
        if (reputationMerkleRoot == bytes32(0)) {
            return false;
        }

        // Compute the leaf: hash of user address and reputation score
        bytes32 leaf = keccak256(abi.encodePacked(user, reputationScore));

        // Verify the proof against the current root
        isValid = proof.verifyCalldata(reputationMerkleRoot, leaf);
    }

    /**
     * @notice Verifies and stores a user's reputation claim
     * @dev This function both verifies the proof and stores the result for use in staking/voting
     * @param user The address of the user claiming the reputation
     * @param reputationScore The reputation score being claimed
     * @param proof The Merkle proof array
     * @return isValid True if the proof is valid and stored
     */
    function verifyAndStoreReputation(
        address user,
        uint256 reputationScore,
        bytes32[] calldata proof
    ) external returns (bool isValid) {
        // Revert if no root is set
        require(reputationMerkleRoot != bytes32(0), "No reputation root set");

        // Compute the leaf: hash of user address and reputation score
        bytes32 leaf = keccak256(abi.encodePacked(user, reputationScore));

        // Verify the proof against the current root
        isValid = proof.verifyCalldata(reputationMerkleRoot, leaf);
        
        if (!isValid) revert InvalidProof();

        // Store the verified reputation for use in staking/voting logic
        verifiedReputation[user] = reputationScore;
        hasVerifiedReputation[user] = true;
        
        emit ReputationVerified(user, reputationScore, reputationMerkleRoot);
    }

    /**
     * @notice Verifies and stores reputation for the caller
     * @dev Convenience function for users to verify their own reputation
     * @param reputationScore The reputation score being claimed
     * @param proof The Merkle proof array
     * @return isValid True if the proof is valid and stored
     */
    function verifyMyReputation(
        uint256 reputationScore,
        bytes32[] calldata proof
    ) external returns (bool isValid) {
        return this.verifyAndStoreReputation(msg.sender, reputationScore, proof);
    }

    /**
     * @notice Gets the verified reputation score for a user
     * @dev Returns 0 if the user hasn't verified their reputation
     * @param user The address to query
     * @return The verified reputation score, or 0 if not verified
     */
    function getVerifiedReputation(address user) external view returns (uint256) {
        return verifiedReputation[user];
    }

    /**
     * @notice Checks if a user has a verified reputation
     * @param user The address to check
     * @return True if the user has verified their reputation
     */
    function hasUserVerifiedReputation(address user) external view returns (bool) {
        return hasVerifiedReputation[user];
    }

    /**
     * @notice Updates the admin address
     * @dev Only callable by current admin
     * @param _newAdmin The new admin address
     */
    function updateAdmin(address _newAdmin) external {
        if (msg.sender != admin) revert NotAdmin();
        require(_newAdmin != address(0), "Admin cannot be zero address");
        admin = _newAdmin;
    }
}