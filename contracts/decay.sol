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
