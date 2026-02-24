pragma solidity ^0.8.20;

import "../../src/Staking.sol";
import "../../src/Rewards.sol";

contract Handler {
    Staking staking;
    Rewards rewards;

    address[] users;

    constructor(Staking _staking, Rewards _rewards) {
        staking = _staking;
        rewards = _rewards;

        users.push(address(0x1));
        users.push(address(0x2));
        users.push(address(0x3));
    }

    function stake(uint256 amount, uint8 userIndex) public {
        amount = bound(amount, 1e18, 1000e18);
        address user = users[userIndex % users.length];

        staking.stake(user, amount);
    }

    function claim(uint8 userIndex) public {
        address user = users[userIndex % users.length];
        rewards.claim(user);
    }
}