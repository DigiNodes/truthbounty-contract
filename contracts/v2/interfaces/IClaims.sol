// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
import {IV2Types} from "./IV2Types.sol";
interface IClaims is IV2Module {
    event ClaimCreated(uint256 indexed claimId, address indexed claimant, bytes32 indexed subject, uint256 reward);
    event ClaimStateChanged(uint256 indexed claimId, IV2Types.ClaimState previousState, IV2Types.ClaimState newState, address indexed actor, uint64 timestamp, bytes32 reasonCode);
    function createClaim(bytes32 subject, uint256 reward, bytes calldata metadata) external returns (uint256 claimId);
    function cancelClaim(uint256 claimId) external;
    function getClaim(uint256 claimId) external view returns (IV2Types.Claim memory);
    function stateOf(uint256 claimId) external view returns (IV2Types.ClaimState);
}
