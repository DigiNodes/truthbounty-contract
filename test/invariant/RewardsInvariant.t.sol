// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";

import "../../src/Rewards.sol";
import "../../src/Staking.sol";


contract RewardsInvariant is StdInvariant, Test {

    Rewards rewards;
    Staking staking;

    address[] users;

    function setUp() public {
        staking = new Staking();
        rewards = new Rewards(address(staking));

        users.push(address(0x1));
        users.push(address(0x2));
        users.push(address(0x3));

        targetContract(address(staking));
        targetContract(address(rewards));
    }

    function invariant_TotalRewardsNeverExceedPool() public {
    assertLe(
        rewards.totalDistributed(),
        rewards.rewardPool()
    );
}

function invariant_NoNegativeBalances() public {
    for (uint i = 0; i < users.length; i++) {
        assertGe(staking.balanceOf(users[i]), 0);
        assertGe(rewards.claimed(users[i]), 0);
    }
}

function invariant_NoRewardDuplication() public {
    uint total;

    for (uint i = 0; i < users.length; i++) {
        total += rewards.claimed(users[i]);
    }

    assertEq(total, rewards.totalDistributed());
}

function invariant_RewardsProportionalToStake() public {
    uint stakeA = staking.balanceOf(users[0]);
    uint stakeB = staking.balanceOf(users[1]);

    if (stakeA > 0 && stakeB > 0) {
        uint rewardA = rewards.claimed(users[0]);
        uint rewardB = rewards.claimed(users[1]);

        // Cross multiply to avoid division rounding
        assertApproxEqRel(
            rewardA * stakeB,
            rewardB * stakeA,
            0.05e18 // 5% tolerance
        );
    }
}

}