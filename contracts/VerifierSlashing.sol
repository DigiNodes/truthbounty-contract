// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title VerifierSlashing
 * @dev Advanced slashing mechanism for TruthBounty protocol verifiers
 * @notice Handles slashing of verifier stakes when incorrect verifications are proven
 */

// Interface for the staking contract
interface IStaking {
    function stakes(address user) external view returns (uint256 amount, uint256 unlockTime);
    function forceSlash(address user, uint256 amount) external;
}

contract VerifierSlashing is AccessControl, ReentrancyGuard, Pausable {
    
    // Role definitions
    bytes32 public constant SETTLEMENT_ROLE = keccak256("SETTLEMENT_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    // Maximum slashing percentage (100%)
    uint256 public constant MAX_SLASH_PERCENTAGE = 100;
    
    // Default maximum slashing percentage per incident
    uint256 public maxSlashPercentage = 50; // 50% max per slash
    
    // Minimum time between slashes for the same verifier (anti-spam)
    uint256 public slashCooldown = 1 hours;
    
    IStaking public stakingContract;
    
    // Slashing tracking
    struct SlashRecord {
        uint256 timestamp;
        uint256 amount;
        uint256 percentage;
        string reason;
        address slashedBy;
    }
    
    // Verifier address => array of slash records
    mapping(address => SlashRecord[]) public slashHistory;
    
    // Verifier address => last slash timestamp
    mapping(address => uint256) public lastSlashTime;
    
    // Total amount slashed per verifier
    mapping(address => uint256) public totalSlashed;
    
    // Events
    event Slashed(
        address indexed verifier,
        uint256 amount,
        uint256 percentage,
        uint256 remainingStake,
        string reason,
        address indexed slashedBy
    );
    
    event SlashingConfigUpdated(
        uint256 newMaxPercentage,
        uint256 newCooldown
    );
    
    event StakingContractUpdated(address newStakingContract);
    
    // Custom errors for gas efficiency
    error UnauthorizedSlashing();
    error InvalidPercentage();
    error NoStakeToSlash();
    error SlashingTooFrequent();
    error InvalidStakingContract();
    error SlashAmountTooHigh();
    
    /**
     * @dev Constructor sets up roles and initial configuration
     * @param _stakingContract Address of the staking contract
     * @param _admin Address that will have admin privileges
     */
    constructor(address _stakingContract, address _admin) {
        if (_stakingContract == address(0) || _admin == address(0)) {
            revert InvalidStakingContract();
        }
        
        stakingContract = IStaking(_stakingContract);
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        
        // Admin can grant/revoke settlement role
        _setRoleAdmin(SETTLEMENT_ROLE, ADMIN_ROLE);
    }
    
    /**
     * @dev Slash a verifier's stake for incorrect verification
     * @param verifier Address of the verifier to slash
     * @param percentage Percentage of stake to slash (1-100)
     * @param reason Human-readable reason for slashing
     */
    function slash(
        address verifier,
        uint256 percentage,
        string calldata reason
    ) external nonReentrant whenNotPaused {
        // Access control check
        if (!hasRole(SETTLEMENT_ROLE, msg.sender)) {
            revert UnauthorizedSlashing();
        }
        
        // Input validation
        if (percentage == 0 || percentage > maxSlashPercentage) {
            revert InvalidPercentage();
        }
        
        if (verifier == address(0)) {
            revert NoStakeToSlash();
        }
        
        // Check cooldown period
        if (block.timestamp < lastSlashTime[verifier] + slashCooldown) {
            revert SlashingTooFrequent();
        }
        
        // Get current stake from staking contract
        (uint256 currentStake,) = stakingContract.stakes(verifier);
        
        if (currentStake == 0) {
            revert NoStakeToSlash();
        }
        
        // Calculate slash amount
        uint256 slashAmount = (currentStake * percentage) / 100;
        
        if (slashAmount == 0) {
            revert SlashAmountTooHigh();
        }
        
        // Update tracking
        lastSlashTime[verifier] = block.timestamp;
        totalSlashed[verifier] += slashAmount;
        
        // Record slash history
        slashHistory[verifier].push(SlashRecord({
            timestamp: block.timestamp,
            amount: slashAmount,
            percentage: percentage,
            reason: reason,
            slashedBy: msg.sender
        }));
        
        // Execute slash through staking contract
        stakingContract.forceSlash(verifier, slashAmount);
        
        // Calculate remaining stake after slash
        uint256 remainingStake = currentStake - slashAmount;
        
        emit Slashed(
            verifier,
            slashAmount,
            percentage,
            remainingStake,
            reason,
            msg.sender
        );
    }
    
    /**
     * @dev Batch slash multiple verifiers (gas efficient for multiple violations)
     * @param verifiers Array of verifier addresses
     * @param percentages Array of slash percentages
     * @param reasons Array of reasons for slashing
     */
    function batchSlash(
        address[] calldata verifiers,
        uint256[] calldata percentages,
        string[] calldata reasons
    ) external nonReentrant whenNotPaused {
        if (!hasRole(SETTLEMENT_ROLE, msg.sender)) {
            revert UnauthorizedSlashing();
        }
        
        uint256 length = verifiers.length;
        require(
            length == percentages.length && length == reasons.length,
            "Array length mismatch"
        );
        require(length > 0 && length <= 50, "Invalid batch size"); // Prevent gas issues
        
        for (uint256 i = 0; i < length;) {
            // Use internal function to avoid duplicate access control checks
            _slashInternal(verifiers[i], percentages[i], reasons[i]);
            
            unchecked {
                ++i;
            }
        }
    }
    
    /**
     * @dev Internal slash function for batch operations
     */
    function _slashInternal(
        address verifier,
        uint256 percentage,
        string calldata reason
    ) internal {
        // Input validation (same as public slash function)
        if (percentage == 0 || percentage > maxSlashPercentage) {
            revert InvalidPercentage();
        }
        
        if (verifier == address(0)) {
            revert NoStakeToSlash();
        }
        
        if (block.timestamp < lastSlashTime[verifier] + slashCooldown) {
            revert SlashingTooFrequent();
        }
        
        (uint256 currentStake,) = stakingContract.stakes(verifier);
        
        if (currentStake == 0) {
            revert NoStakeToSlash();
        }
        
        uint256 slashAmount = (currentStake * percentage) / 100;
        
        if (slashAmount == 0) {
            revert SlashAmountTooHigh();
        }
        
        // Update tracking
        lastSlashTime[verifier] = block.timestamp;
        totalSlashed[verifier] += slashAmount;
        
        slashHistory[verifier].push(SlashRecord({
            timestamp: block.timestamp,
            amount: slashAmount,
            percentage: percentage,
            reason: reason,
            slashedBy: msg.sender
        }));
        
        stakingContract.forceSlash(verifier, slashAmount);
        
        uint256 remainingStake = currentStake - slashAmount;
        
        emit Slashed(
            verifier,
            slashAmount,
            percentage,
            remainingStake,
            reason,
            msg.sender
        );
    }
    
    // === VIEW FUNCTIONS ===
    
    /**
     * @dev Get slash history for a verifier
     * @param verifier Address of the verifier
     * @return Array of slash records
     */
    function getSlashHistory(address verifier) external view returns (SlashRecord[] memory) {
        return slashHistory[verifier];
    }
    
    /**
     * @dev Get slash count for a verifier
     * @param verifier Address of the verifier
     * @return Number of times the verifier has been slashed
     */
    function getSlashCount(address verifier) external view returns (uint256) {
        return slashHistory[verifier].length;
    }
    
    /**
     * @dev Check if a verifier can be slashed (cooldown check)
     * @param verifier Address of the verifier
     * @return True if verifier can be slashed
     */
    function canSlash(address verifier) external view returns (bool) {
        return block.timestamp >= lastSlashTime[verifier] + slashCooldown;
    }
    
    /**
     * @dev Get time remaining until verifier can be slashed again
     * @param verifier Address of the verifier
     * @return Seconds remaining in cooldown period
     */
    function getSlashCooldownRemaining(address verifier) external view returns (uint256) {
        uint256 nextSlashTime = lastSlashTime[verifier] + slashCooldown;
        if (block.timestamp >= nextSlashTime) {
            return 0;
        }
        return nextSlashTime - block.timestamp;
    }
    
    // === ADMIN FUNCTIONS ===
    
    /**
     * @dev Update slashing configuration
     * @param _maxSlashPercentage New maximum slash percentage per incident
     * @param _slashCooldown New cooldown period between slashes
     */
    function updateSlashingConfig(
        uint256 _maxSlashPercentage,
        uint256 _slashCooldown
    ) external onlyRole(ADMIN_ROLE) {
        require(_maxSlashPercentage <= MAX_SLASH_PERCENTAGE, "Percentage too high");
        require(_slashCooldown <= 7 days, "Cooldown too long");
        
        maxSlashPercentage = _maxSlashPercentage;
        slashCooldown = _slashCooldown;
        
        emit SlashingConfigUpdated(_maxSlashPercentage, _slashCooldown);
    }
    
    /**
     * @dev Update the staking contract address
     * @param _stakingContract New staking contract address
     */
    function updateStakingContract(address _stakingContract) external onlyRole(ADMIN_ROLE) {
        if (_stakingContract == address(0)) {
            revert InvalidStakingContract();
        }
        
        stakingContract = IStaking(_stakingContract);
        emit StakingContractUpdated(_stakingContract);
    }
    
    /**
     * @dev Grant settlement role to an address (typically the settlement contract)
     * @param account Address to grant the role to
     */
    function grantSettlementRole(address account) external onlyRole(ADMIN_ROLE) {
        _grantRole(SETTLEMENT_ROLE, account);
    }
    
    /**
     * @dev Revoke settlement role from an address
     * @param account Address to revoke the role from
     */
    function revokeSettlementRole(address account) external onlyRole(ADMIN_ROLE) {
        _revokeRole(SETTLEMENT_ROLE, account);
    }
    
    /**
     * @dev Emergency pause function
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause function
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}