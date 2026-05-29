// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title EIP712Verifier
 * @notice Implements EIP-712 typed structured data signing for off-chain message validation
 * @dev Provides secure off-chain signatures with replay protection for claims and verifications
 */
contract EIP712Verifier is EIP712 {
    using ECDSA for bytes32;

    // ============ Type Hashes ============
    
    bytes32 public constant CLAIM_SUBMISSION_TYPEHASH = keccak256(
        "ClaimSubmission(address claimant,uint256 bountyId,bytes32 contentHash,uint256 nonce,uint256 deadline)"
    );

    bytes32 public constant VERIFICATION_INTENT_TYPEHASH = keccak256(
        "VerificationIntent(address verifier,uint256 bountyId,bool approve,string reason,uint256 nonce,uint256 deadline)"
    );

    // ============ State ============

    /// @notice Nonces for replay protection per address
    mapping(address => uint256) public nonces;

    /// @notice Tracks used signatures to prevent replay
    mapping(bytes32 => bool) public usedSignatures;

    // ============ Events ============

    event ClaimSubmissionVerified(
        address indexed claimant,
        uint256 indexed bountyId,
        bytes32 contentHash,
        uint256 nonce
    );

    event VerificationIntentVerified(
        address indexed verifier,
        uint256 indexed bountyId,
        bool approve,
        uint256 nonce
    );

    // ============ Errors ============

    error InvalidSignature();
    error SignatureExpired();
    error SignatureAlreadyUsed();
    error InvalidNonce();

    // ============ Constructor ============

    constructor() EIP712("TruthBounty", "1") {}

    // ============ External Functions ============

    /**
     * @notice Verifies a claim submission signature
     * @param claimant The address making the claim
     * @param bountyId The ID of the bounty being claimed
     * @param contentHash Hash of the claim content
     * @param deadline Signature expiration timestamp
     * @param signature The EIP-712 signature
     * @return True if signature is valid
     */
    function verifyClaimSubmission(
        address claimant,
        uint256 bountyId,
        bytes32 contentHash,
        uint256 deadline,
        bytes calldata signature
    ) external returns (bool) {
        if (block.timestamp > deadline) revert SignatureExpired();

        uint256 currentNonce = nonces[claimant];
        
        bytes32 structHash = keccak256(abi.encode(
            CLAIM_SUBMISSION_TYPEHASH,
            claimant,
            bountyId,
            contentHash,
            currentNonce,
            deadline
        ));

        bytes32 digest = _hashTypedDataV4(structHash);
        
        if (usedSignatures[digest]) revert SignatureAlreadyUsed();
        
        address signer = digest.recover(signature);
        if (signer != claimant) revert InvalidSignature();

        usedSignatures[digest] = true;
        nonces[claimant] = currentNonce + 1;

        emit ClaimSubmissionVerified(claimant, bountyId, contentHash, currentNonce);
        
        return true;
    }

    /**
     * @notice Verifies a verification intent signature
     * @param verifier The address of the verifier
     * @param bountyId The ID of the bounty being verified
     * @param approve Whether the verifier approves the claim
     * @param reason The reason for the verification decision
     * @param deadline Signature expiration timestamp
     * @param signature The EIP-712 signature
     * @return True if signature is valid
     */
    function verifyVerificationIntent(
        address verifier,
        uint256 bountyId,
        bool approve,
        string calldata reason,
        uint256 deadline,
        bytes calldata signature
    ) external returns (bool) {
        if (block.timestamp > deadline) revert SignatureExpired();

        uint256 currentNonce = nonces[verifier];
        
        bytes32 structHash = keccak256(abi.encode(
            VERIFICATION_INTENT_TYPEHASH,
            verifier,
            bountyId,
            approve,
            keccak256(bytes(reason)),
            currentNonce,
            deadline
        ));

        bytes32 digest = _hashTypedDataV4(structHash);
        
        if (usedSignatures[digest]) revert SignatureAlreadyUsed();
        
        address signer = digest.recover(signature);
        if (signer != verifier) revert InvalidSignature();

        usedSignatures[digest] = true;
        nonces[verifier] = currentNonce + 1;

        emit VerificationIntentVerified(verifier, bountyId, approve, currentNonce);
        
        return true;
    }

    /**
     * @notice Returns the current nonce for an address
     * @param account The address to query
     * @return The current nonce
     */
    function getNonce(address account) external view returns (uint256) {
        return nonces[account];
    }

    /**
     * @notice Returns the domain separator for this contract
     * @return The EIP-712 domain separator
     */
    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Computes the hash of a claim submission for off-chain signing
     * @param claimant The address making the claim
     * @param bountyId The ID of the bounty being claimed
     * @param contentHash Hash of the claim content
     * @param nonce The nonce for replay protection
     * @param deadline Signature expiration timestamp
     * @return The typed data hash to sign
     */
    function getClaimSubmissionHash(
        address claimant,
        uint256 bountyId,
        bytes32 contentHash,
        uint256 nonce,
        uint256 deadline
    ) external view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            CLAIM_SUBMISSION_TYPEHASH,
            claimant,
            bountyId,
            contentHash,
            nonce,
            deadline
        ));
        return _hashTypedDataV4(structHash);
    }

    /**
     * @notice Computes the hash of a verification intent for off-chain signing
     * @param verifier The address of the verifier
     * @param bountyId The ID of the bounty being verified
     * @param approve Whether the verifier approves
     * @param reason The reason for the decision
     * @param nonce The nonce for replay protection
     * @param deadline Signature expiration timestamp
     * @return The typed data hash to sign
     */
    function getVerificationIntentHash(
        address verifier,
        uint256 bountyId,
        bool approve,
        string calldata reason,
        uint256 nonce,
        uint256 deadline
    ) external view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            VERIFICATION_INTENT_TYPEHASH,
            verifier,
            bountyId,
            approve,
            keccak256(bytes(reason)),
            nonce,
            deadline
        ));
        return _hashTypedDataV4(structHash);
    }

    /**
     * @notice Checks if a signature has been used
     * @param signatureHash The hash of the signature to check
     * @return True if the signature has been used
     */
    function isSignatureUsed(bytes32 signatureHash) external view returns (bool) {
        return usedSignatures[signatureHash];
    }
}



// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IReputationOracle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockReputationOracle
 * @notice Mock implementation of IReputationOracle for testing and development
 * @dev Allows manual setting of reputation scores for testing weighted staking
 */
contract MockReputationOracle is IReputationOracle, Ownable {

    /// @notice Mapping of user addresses to their reputation scores
    mapping(address => uint256) private reputationScores;

    /// @notice Whether the oracle is active
    bool private _isActive = true;

    /// @notice Default score for users without explicit reputation
    uint256 public defaultScore = 1e18; // 1.0 (100%)

    // ============ Events ============

    event ReputationScoreSet(address indexed user, uint256 score);
    event OracleStatusChanged(bool isActive);
    event DefaultScoreUpdated(uint256 newDefault);

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ IReputationOracle Implementation ============

    /**
     * @notice Get the reputation score for a given address
     * @param user The address to query reputation for
     * @return score The reputation score (scaled by 1e18)
     */
    function getReputationScore(address user) external view override returns (uint256 score) {
        uint256 userScore = reputationScores[user];

        // If no score set, return default
        if (userScore == 0) {
            return defaultScore;
        }

        return userScore;
    }

    /**
     * @notice Check if the oracle is active
     * @return True if the oracle is operational
     */
    function isActive() external view override returns (bool) {
        return _isActive;
    }

    // ============ Admin Functions ============

    /**
     * @notice Set reputation score for a user
     * @param user The address to set reputation for
     * @param score The reputation score (scaled by 1e18)
     */
    function setReputationScore(address user, uint256 score) external onlyOwner {
        require(user != address(0), "Invalid address");
        reputationScores[user] = score;
        emit ReputationScoreSet(user, score);
    }

    /**
     * @notice Batch set reputation scores for multiple users
     * @param users Array of user addresses
     * @param scores Array of reputation scores
     */
    function batchSetReputationScores(
        address[] calldata users,
        uint256[] calldata scores
    ) external onlyOwner {
        require(users.length == scores.length, "Array length mismatch");

        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "Invalid address");
            reputationScores[users[i]] = scores[i];
            emit ReputationScoreSet(users[i], scores[i]);
        }
    }

    /**
     * @notice Set the oracle active status
     * @param active Whether the oracle should be active
     */
    function setActive(bool active) external onlyOwner {
        _isActive = active;
        emit OracleStatusChanged(active);
    }

    /**
     * @notice Set the default score for users without explicit reputation
     * @param _defaultScore The new default score
     */
    function setDefaultScore(uint256 _defaultScore) external onlyOwner {
        defaultScore = _defaultScore;
        emit DefaultScoreUpdated(_defaultScore);
    }

    // ============ Helper Functions for Testing ============

    /**
     * @notice Set high reputation for a user (3x multiplier)
     */
    function setHighReputation(address user) external onlyOwner {
        reputationScores[user] = 3e18; // 3.0 (300%)
        emit ReputationScoreSet(user, 3e18);
    }

    /**
     * @notice Set low reputation for a user (0.5x multiplier)
     */
    function setLowReputation(address user) external onlyOwner {
        reputationScores[user] = 5e17; // 0.5 (50%)
        emit ReputationScoreSet(user, 5e17);
    }

    /**
     * @notice Set neutral reputation for a user (1x multiplier)
     */
    function setNeutralReputation(address user) external onlyOwner {
        reputationScores[user] = 1e18; // 1.0 (100%)
        emit ReputationScoreSet(user, 1e18);
    }

    /**
     * @notice Reset reputation score for a user
     */
    function resetReputationScore(address user) external onlyOwner {
        reputationScores[user] = 0;
        emit ReputationScoreSet(user, 0);
    }
}
