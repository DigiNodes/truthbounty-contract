// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
// 
// import "forge-std/Test.sol";
// 
// // import "../contracts/staking/WeightedStaking.sol";
// 
// contract WeightedStakingTimestampTest is Test {
// 
//     // WeightedStaking staking;
// 
//     function setUp() public {
//         // staking = new WeightedStaking();
//     }
// 
//     function testRejectsTinyDuration()
//         public
//     {
//         // vm.expectRevert(
//         //     "Duration too small"
//         // );
// 
//         // staking.stake(
//         //     100 ether,
//         //     30 seconds
//         // );
//     }
// 
//     function testUnlockUsesNormalizedTime()
//         public
//     {
//         // staking.stake(
//         //     100 ether,
//         //     10 minutes
//         // );
// 
//         // vm.warp(block.timestamp + 9 minutes);
// 
//         // assertFalse(
//         //     staking.canUnstake(address(this))
//         // );
// 
//         // vm.warp(block.timestamp + 1 minutes);
// 
//         // assertTrue(
//         //     staking.canUnstake(address(this))
//         // );
//     }
// 
//     function testTimestampNormalization()
//         public
//     {
//         // uint256 current =
//         //     block.timestamp;
// 
//         // uint256 normalized =
//         //     (current / 1 minutes) *
//         //     1 minutes;
// 
//         // assertLe(normalized, current);
//     }
// }