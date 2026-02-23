// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../contracts/IReputationOracle.sol";

/**
 * @title MockReputationOracle
 * @notice Mock implementation of reputation oracle for testing
 */
contract MockReputationOracle is IReputationOracle {
    mapping(address => uint256) public reputationScores;
    bool public active = true;
    
    function setReputationScore(address user, uint256 score) external {
        reputationScores[user] = score;
    }
    
    function setActive(bool _active) external {
        active = _active;
    }
    
    function getReputationScore(address user) external view override returns (uint256) {
        return reputationScores[user];
    }
    
    function isActive() external view override returns (bool) {
        return active;
    }
}
