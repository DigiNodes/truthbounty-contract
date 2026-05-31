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

    /// @notice Mapping of user addresses to their last reputation update time
    mapping(address => uint256) private lastUpdateTimestamp;

    /// @notice Whether the oracle is active
    bool private _isActive = true;

    /// @notice Default score for users without explicit reputation
    uint256 public defaultScore = 1e18; // 1.0 (100%)

    /// @notice Maximum number of scores that can be set in a single batch.
    /// @dev Bounds the loop to avoid out-of-gas. Mirrors the production batch
    ///      caps for consistency. (Audit #156)
    uint256 public constant MAX_BATCH_SIZE = 200;

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
        lastUpdateTimestamp[user] = block.timestamp;
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
        uint256 length = users.length;
        require(length == scores.length, "Array length mismatch");
        require(length > 0, "Empty batch");
        require(length <= MAX_BATCH_SIZE, "Batch size too large");

        for (uint256 i = 0; i < length; i++) {
            require(users[i] != address(0), "Invalid address");
            reputationScores[users[i]] = scores[i];
            lastUpdateTimestamp[users[i]] = block.timestamp;
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
        lastUpdateTimestamp[user] = block.timestamp;
        emit ReputationScoreSet(user, 3e18);
    }

    /**
     * @notice Set low reputation for a user (0.5x multiplier)
     */
    function setLowReputation(address user) external onlyOwner {
        reputationScores[user] = 5e17; // 0.5 (50%)
        lastUpdateTimestamp[user] = block.timestamp;
        emit ReputationScoreSet(user, 5e17);
    }

    /**
     * @notice Set neutral reputation for a user (1x multiplier)
     */
    function setNeutralReputation(address user) external onlyOwner {
        reputationScores[user] = 1e18; // 1.0 (100%)
        lastUpdateTimestamp[user] = block.timestamp;
        emit ReputationScoreSet(user, 1e18);
    }

    /**
     * @notice Reset reputation score for a user
     */
    function resetReputationScore(address user) external onlyOwner {
        reputationScores[user] = 0;
        lastUpdateTimestamp[user] = block.timestamp;
        emit ReputationScoreSet(user, 0);
    }

    function getLastReputationUpdate(address user) external view override returns (uint256 timestamp) {
        return lastUpdateTimestamp[user];
    }
}
