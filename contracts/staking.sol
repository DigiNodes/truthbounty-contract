// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Staking is ReentrancyGuard, Ownable {
    
    // The token being staked (TruthBountyToken)
    IERC20 public stakingToken;

    // Duration in seconds that tokens must be locked after staking
    uint256 public lockDuration;
    
    // Address authorized to slash stakes (VerifierSlashing contract)
    address public slashingContract;

    struct StakeInfo {
        uint256 amount;      // Total amount currently staked
        uint256 unlockTime;  // Timestamp when the stake allows withdrawal
    }

    // Mapping of user address to their stake details
    mapping(address => StakeInfo) public stakes;

    // Events for frontend indexing
    event Staked(address indexed user, uint256 amount, uint256 totalStaked, uint256 unlockTime);
    event Unstaked(address indexed user, uint256 amount, uint256 remainingStake);
    event LockDurationUpdated(uint256 newDuration);
    event StakeSlashed(address indexed user, uint256 amount, uint256 remainingStake);
    event SlashingContractUpdated(address newSlashingContract);

    /**
     * @param _stakingToken Address of the TruthBountyToken
     * @param _initialLockDuration Initial lock time in seconds (e.g., 86400 for 1 day)
     */
    constructor(address _stakingToken, uint256 _initialLockDuration) Ownable(msg.sender) {
        require(_stakingToken != address(0), "Invalid token address");
        stakingToken = IERC20(_stakingToken);
        lockDuration = _initialLockDuration;
    }

    /**
     * @dev Stake tokens into the contract. 
     * Resets the unlock timer for the ENTIRE balance to prevent manipulation.
     * @param amount The amount of tokens to stake.
     */
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");

        // Transfer tokens from user to contract (requires approve())
        stakingToken.transferFrom(msg.sender, address(this), amount);

        StakeInfo storage info = stakes[msg.sender];
        
        // Update balance
        info.amount += amount;
        
        // Reset lock period based on current time + duration
        info.unlockTime = block.timestamp + lockDuration;

        emit Staked(msg.sender, amount, info.amount, info.unlockTime);
    }

    /**
     * @dev Withdraw staked tokens. Can only be called after lock period expires.
     * @param amount The amount to withdraw.
     */
    function unstake(uint256 amount) external nonReentrant {
        StakeInfo storage info = stakes[msg.sender];
        
        require(info.amount >= amount, "Insufficient staked balance");
        require(block.timestamp >= info.unlockTime, "Stake is still locked");
        require(amount > 0, "Cannot unstake 0");

        // Update balance
        info.amount -= amount;

        // Transfer tokens back to user
        stakingToken.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount, info.amount);
    }

    /**
     * @dev Returns the full stake info for a user.
     */
    function getStakeInfo(address user) external view returns (uint256 amount, uint256 unlockTime, uint256 timeRemaining) {
        StakeInfo memory info = stakes[user];
        
        uint256 remaining = 0;
        if (block.timestamp < info.unlockTime) {
            remaining = info.unlockTime - block.timestamp;
        }

        return (info.amount, info.unlockTime, remaining);
    }

    /**
     * @dev Admin function to update the lock duration for FUTURE stakes.
     */
    function setLockDuration(uint256 _duration) external onlyOwner {
        lockDuration = _duration;
        emit LockDurationUpdated(_duration);
    }
    
    /**
     * @dev Set the authorized slashing contract
     * @param _slashingContract Address of the VerifierSlashing contract
     */
    function setSlashingContract(address _slashingContract) external onlyOwner {
        require(_slashingContract != address(0), "Invalid slashing contract");
        slashingContract = _slashingContract;
        emit SlashingContractUpdated(_slashingContract);
    }
    
    /**
     * @dev Force slash a verifier's stake (only callable by slashing contract)
     * @param user Address of the user to slash
     * @param amount Amount to slash from their stake
     */
    function forceSlash(address user, uint256 amount) external {
        require(msg.sender == slashingContract, "Only slashing contract can slash");
        require(slashingContract != address(0), "Slashing contract not set");
        
        StakeInfo storage info = stakes[user];
        require(info.amount >= amount, "Insufficient stake to slash");
        
        // Reduce the staked amount
        info.amount -= amount;
        
        // Keep the slashed tokens in the contract (effectively burning them from circulation)
        // Alternative: Transfer to a burn address or treasury
        
        emit StakeSlashed(user, amount, info.amount);
    }
}