// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
import {IV2Types} from "./IV2Types.sol";
interface IDisputes is IV2Module {
    event DisputeOpened(uint256 indexed disputeId, uint256 indexed claimId, address indexed opener, bytes32 reasonHash);
    event DisputeResolved(uint256 indexed disputeId, IV2Types.DisputeStatus status, address indexed resolver);
    function openDispute(uint256 claimId, bytes32 reasonHash, bytes calldata evidence) external returns (uint256 disputeId);
    function resolveDispute(uint256 disputeId, IV2Types.DisputeStatus status, bytes calldata decision) external;
    function getDispute(uint256 disputeId) external view returns (IV2Types.Dispute memory);
}
