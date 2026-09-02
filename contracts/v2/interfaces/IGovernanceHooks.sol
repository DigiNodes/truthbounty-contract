// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
interface IGovernanceHooks is IV2Module {
    event GovernanceActionAuthorized(bytes32 indexed actionId, address indexed target, bytes4 indexed selector);
    event GovernanceActionConsumed(bytes32 indexed actionId, address indexed target, bytes4 indexed selector);
    function authorize(bytes32 actionId, address target, bytes4 selector, bytes32 dataHash) external;
    function consume(bytes32 actionId, address target, bytes4 selector, bytes32 dataHash) external;
    function isAuthorized(bytes32 actionId, address target, bytes4 selector, bytes32 dataHash) external view returns (bool);
}
