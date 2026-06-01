// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../utils/TimeConstants.sol";

contract WeightedStaking {

    struct StakePosition {
        uint256 amount;
        uint256 startTime;
        uint256 unlockTime;
    }

    mapping(address => StakePosition)
        public stakes;

    function stake(
        uint256 amount,
        uint256 duration
    ) external {

        require(
            duration >= TimeConstants.MIN_WINDOW,
            "Duration too small"
        );

        uint256 normalizedTimestamp =
            _normalizedTimestamp();

        stakes[msg.sender] = StakePosition({
            amount: amount,
            startTime: normalizedTimestamp,
            unlockTime:
                normalizedTimestamp + duration
        });
    }

    function canUnstake(
        address user
    ) public view returns (bool) {

        StakePosition memory position =
            stakes[user];

        return
            _normalizedTimestamp() >=
            position.unlockTime;
    }

    function _normalizedTimestamp()
        internal
        view
        returns (uint256)
    {
        return
            (
                block.timestamp /
                TimeConstants.EPOCH_GRANULARITY
            ) *
            TimeConstants.EPOCH_GRANULARITY;
    }
}