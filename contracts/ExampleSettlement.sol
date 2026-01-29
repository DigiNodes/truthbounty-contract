// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ExampleSettlement
 * @dev Example settlement contract showing integration with VerifierSlashing
 * @notice This is a simplified example for demonstration purposes
 */

// Interface for the slashing contract
interface IVerifierSlashing {
    function slash(address verifier, uint256 percentage, string calldata reason) external;
    function canSlash(address verifier) external view returns (bool);
}

contract ExampleSettlement is Ownable, ReentrancyGuard {
    
    IVerifierSlashing public slashingContract;
    
    // Claim states
    enum ClaimStatus { Pending, Verified, Disputed, Settled }
    
    struct Claim {
        address claimant;
        address verifier;
        string data;
        ClaimStatus status;
        uint256 timestamp;
        bool verificationCorrect;
    }
    
    mapping(uint256 => Claim) public claims;
    uint256 public nextClaimId;
    
    // Slashing configuration
    uint256 public incorrectVerificationSlashPercentage = 20; // 20%
    uint256 public maliciousVerificationSlashPercentage = 50; // 50%
    
    event ClaimSubmitted(uint256 indexed claimId, address indexed claimant, address indexed verifier);
    event ClaimSettled(uint256 indexed claimId, bool verificationCorrect);
    event VerifierSlashed(uint256 indexed claimId, address indexed verifier, uint256 percentage, string reason);
    
    constructor(address _slashingContract) Ownable(msg.sender) {
        require(_slashingContract != address(0), "Invalid slashing contract");
        slashingContract = IVerifierSlashing(_slashingContract);
    }
    
    /**
     * @dev Submit a new claim for verification
     * @param verifier Address of the verifier assigned to this claim
     * @param data Claim data to be verified
     */
    function submitClaim(address verifier, string calldata data) external returns (uint256) {
        require(verifier != address(0), "Invalid verifier");
        
        uint256 claimId = nextClaimId++;
        
        claims[claimId] = Claim({
            claimant: msg.sender,
            verifier: verifier,
            data: data,
            status: ClaimStatus.Pending,
            timestamp: block.timestamp,
            verificationCorrect: false
        });
        
        emit ClaimSubmitted(claimId, msg.sender, verifier);
        return claimId;
    }
    
    /**
     * @dev Settle a claim and potentially slash the verifier if verification was incorrect
     * @param claimId ID of the claim to settle
     * @param verificationWasCorrect Whether the verifier's decision was correct
     * @param isMalicious Whether the incorrect verification appears to be malicious
     */
    function settleClaim(
        uint256 claimId, 
        bool verificationWasCorrect, 
        bool isMalicious
    ) external onlyOwner nonReentrant {
        _settleClaim(claimId, verificationWasCorrect, isMalicious);
    }
    
    /**
     * @dev Internal function to settle a claim
     */
    function _settleClaim(
        uint256 claimId, 
        bool verificationWasCorrect, 
        bool isMalicious
    ) internal {
        Claim storage claim = claims[claimId];
        require(claim.status == ClaimStatus.Pending || claim.status == ClaimStatus.Disputed, "Invalid claim status");
        
        claim.status = ClaimStatus.Settled;
        claim.verificationCorrect = verificationWasCorrect;
        
        // If verification was incorrect, slash the verifier
        if (!verificationWasCorrect) {
            _slashVerifier(claimId, claim.verifier, isMalicious);
        }
        
        emit ClaimSettled(claimId, verificationWasCorrect);
    }
    
    /**
     * @dev Internal function to slash a verifier
     * @param claimId ID of the claim that led to slashing
     * @param verifier Address of the verifier to slash
     * @param isMalicious Whether the verification appears malicious
     */
    function _slashVerifier(uint256 claimId, address verifier, bool isMalicious) internal {
        // Check if verifier can be slashed (cooldown check)
        if (!slashingContract.canSlash(verifier)) {
            // Log that slashing was skipped due to cooldown
            return;
        }
        
        uint256 slashPercentage = isMalicious ? 
            maliciousVerificationSlashPercentage : 
            incorrectVerificationSlashPercentage;
        
        string memory reason = isMalicious ? 
            string(abi.encodePacked("Malicious verification for claim #", _toString(claimId))) :
            string(abi.encodePacked("Incorrect verification for claim #", _toString(claimId)));
        
        try slashingContract.slash(verifier, slashPercentage, reason) {
            emit VerifierSlashed(claimId, verifier, slashPercentage, reason);
        } catch Error(string memory errorReason) {
            // Log slashing failure but don't revert the settlement
            // In production, you might want to emit an event or handle this differently
        } catch {
            // Handle other types of failures
        }
    }
    
    /**
     * @dev Batch settle multiple claims
     * @param claimIds Array of claim IDs to settle
     * @param verificationResults Array of verification correctness results
     * @param maliciousFlags Array indicating if incorrect verifications were malicious
     */
    function batchSettleClaims(
        uint256[] calldata claimIds,
        bool[] calldata verificationResults,
        bool[] calldata maliciousFlags
    ) external onlyOwner nonReentrant {
        require(
            claimIds.length == verificationResults.length && 
            claimIds.length == maliciousFlags.length,
            "Array length mismatch"
        );
        require(claimIds.length > 0 && claimIds.length <= 50, "Invalid batch size");
        
        for (uint256 i = 0; i < claimIds.length; i++) {
            _settleClaim(claimIds[i], verificationResults[i], maliciousFlags[i]);
        }
    }
    
    /**
     * @dev Update slashing percentages
     * @param incorrectPercentage New percentage for incorrect verifications
     * @param maliciousPercentage New percentage for malicious verifications
     */
    function updateSlashingPercentages(
        uint256 incorrectPercentage,
        uint256 maliciousPercentage
    ) external onlyOwner {
        require(incorrectPercentage <= 100 && maliciousPercentage <= 100, "Invalid percentage");
        require(maliciousPercentage >= incorrectPercentage, "Malicious penalty should be higher");
        
        incorrectVerificationSlashPercentage = incorrectPercentage;
        maliciousVerificationSlashPercentage = maliciousPercentage;
    }
    
    /**
     * @dev Update the slashing contract address
     * @param _slashingContract New slashing contract address
     */
    function updateSlashingContract(address _slashingContract) external onlyOwner {
        require(_slashingContract != address(0), "Invalid slashing contract");
        slashingContract = IVerifierSlashing(_slashingContract);
    }
    
    /**
     * @dev Get claim details
     * @param claimId ID of the claim
     * @return Claim struct data
     */
    function getClaim(uint256 claimId) external view returns (Claim memory) {
        return claims[claimId];
    }
    
    /**
     * @dev Check if a verifier can be slashed (not in cooldown)
     * @param verifier Address of the verifier
     * @return True if verifier can be slashed
     */
    function canSlashVerifier(address verifier) external view returns (bool) {
        return slashingContract.canSlash(verifier);
    }
    
    /**
     * @dev Convert uint256 to string (helper function)
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}