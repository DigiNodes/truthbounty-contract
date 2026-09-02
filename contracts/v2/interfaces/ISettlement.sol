// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
import {IV2Types} from "./IV2Types.sol";
interface ISettlement is IV2Module {
    event SettlementQueued(uint256 indexed claimId, address indexed recipient, uint256 grossAmount, uint256 fee, uint64 executableAt);
    event SettlementExecuted(uint256 indexed claimId, address indexed recipient, uint256 netAmount);
    function queueSettlement(uint256 claimId) external;
    function executeSettlement(uint256 claimId) external;
    function getSettlement(uint256 claimId) external view returns (IV2Types.Settlement memory);
}
