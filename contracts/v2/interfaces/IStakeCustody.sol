// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
interface IStakeCustody is IV2Module {
    event StakeDeposited(address indexed account, uint256 indexed claimId, uint256 amount);
    event StakeReleased(address indexed account, uint256 indexed claimId, uint256 amount);
    event StakeSlashed(address indexed account, uint256 indexed claimId, uint256 amount, bytes32 indexed reason);
    function depositStake(uint256 claimId, uint256 amount) external;
    function releaseStake(uint256 claimId, address account, uint256 amount) external;
    function slashStake(uint256 claimId, address account, uint256 amount, bytes32 reason) external;
    function staked(uint256 claimId, address account) external view returns (uint256);
    function totalStaked(uint256 claimId) external view returns (uint256);
}
