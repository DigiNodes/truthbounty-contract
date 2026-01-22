// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
 * @title ReputationTierSystem
 * @dev Manages reputation tiers for verifiers
 */
contract ReputationTierSystem {
    // ==================== Enum & Events ====================
    
    enum ReputationTier {
        BRONZE,  // 0-999 reputation points
        SILVER,  // 1000-4999 reputation points
        GOLD     // 5000+ reputation points
    }

    event TierChanged(
        address indexed user,
        ReputationTier indexed newTier,
        uint256 reputationScore,
        uint256 timestamp
    );

    event TierThresholdsUpdated(
        uint256 silverThreshold,
        uint256 goldThreshold,
        uint256 timestamp
    );

    // ==================== State Variables ====================
    
    address public owner;
    
    uint256 public silverThreshold = 1000;
    uint256 public goldThreshold = 5000;
    
    mapping(address => uint256) public reputationScores;
    mapping(address => ReputationTier) public userTiers;

    // ==================== Constructor ====================
    
    constructor() {
        owner = msg.sender;
    }

    // ==================== Modifiers ====================
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    // ==================== Internal Helper Functions ====================
    
    function _getTierFromScore(uint256 score) internal view returns (ReputationTier) {
        if (score >= goldThreshold) {
            return ReputationTier.GOLD;
        } else if (score >= silverThreshold) {
            return ReputationTier.SILVER;
        } else {
            return ReputationTier.BRONZE;
        }
    }

    function _getTierMetadata(ReputationTier tier) 
        internal 
        pure 
        returns (string memory name, uint256 influenceMultiplier) 
    {
        if (tier == ReputationTier.GOLD) {
            return ("GOLD", 300);      // 3x influence
        } else if (tier == ReputationTier.SILVER) {
            return ("SILVER", 150);    // 1.5x influence
        } else {
            return ("BRONZE", 100);    // 1x influence
        }
    }

    // ==================== Core Functions ====================
    
    function getTierFromScore(uint256 score) external view returns (ReputationTier) {
        return _getTierFromScore(score);
    }

    function updateReputationScore(address user, uint256 newScore) external onlyOwner {
        require(user != address(0), "Invalid user address");
        
        ReputationTier newTier = _getTierFromScore(newScore);
        ReputationTier oldTier = userTiers[user];
        
        reputationScores[user] = newScore;
        
        if (oldTier != newTier) {
            userTiers[user] = newTier;
            emit TierChanged(user, newTier, newScore, block.timestamp);
        }
    }

    function getUserTier(address user) external view returns (ReputationTier) {
        return userTiers[user];
    }

    function getReputationScore(address user) external view returns (uint256) {
        return reputationScores[user];
    }

    function getUserReputationInfo(address user) 
        external 
        view 
        returns (ReputationTier tier, uint256 score) 
    {
        return (userTiers[user], reputationScores[user]);
    }

    function getTierName(ReputationTier tier) external pure returns (string memory) {
        (string memory name, ) = _getTierMetadata(tier);
        return name;
    }

    function getTierInfluenceMultiplier(ReputationTier tier) external pure returns (uint256) {
        (, uint256 multiplier) = _getTierMetadata(tier);
        return multiplier;
    }

    function getTierInfo(ReputationTier tier) 
        external 
        pure 
        returns (string memory name, uint256 influenceMultiplier) 
    {
        return _getTierMetadata(tier);
    }

    // ==================== Admin Functions ====================
    
    function updateTierThresholds(
        uint256 newSilverThreshold,
        uint256 newGoldThreshold
    ) external onlyOwner {
        require(newSilverThreshold < newGoldThreshold, "Silver threshold must be less than Gold");
        require(newSilverThreshold > 0, "Silver threshold must be greater than 0");
        
        silverThreshold = newSilverThreshold;
        goldThreshold = newGoldThreshold;
        
        emit TierThresholdsUpdated(newSilverThreshold, newGoldThreshold, block.timestamp);
    }
}