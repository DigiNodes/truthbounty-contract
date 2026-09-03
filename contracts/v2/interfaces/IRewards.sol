// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
interface IRewards is IV2Module {
    event RewardAccrued(uint256 indexed claimId, address indexed account, uint256 amount);
    event RewardClaimed(address indexed account, uint256 amount);
    function accrue(uint256 claimId, address account, uint256 amount) external;
    function claimRewards(address account) external returns (uint256 amount);
    function claimable(address account) external view returns (uint256);
}
