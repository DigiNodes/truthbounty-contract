// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../IReputationOracle.sol";

contract MockRewardReputationOracle is IReputationOracle {
    mapping(address => uint256) public scores;
    bool public active = true;

    function setScore(address user, uint256 score) external {
        scores[user] = score;
    }

    function setActive(bool value) external {
        active = value;
    }

    function getReputationScore(address user)
        external
        view
        override
        returns (uint256)
    {
        return scores[user];
    }

    function isActive()
        external
        view
        override
        returns (bool)
    {
        return active;
    }

    function getLastReputationUpdate(address)
        external
        view
        override
        returns (uint256)
    {
        return block.timestamp;
    }
}
