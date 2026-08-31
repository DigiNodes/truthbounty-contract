// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
interface IEmergencyControls is IV2Module {
    event EmergencyPaused(bytes32 indexed scope, address indexed actor);
    event EmergencyUnpaused(bytes32 indexed scope, address indexed actor);
    function pause(bytes32 scope) external;
    function unpause(bytes32 scope) external;
    function paused(bytes32 scope) external view returns (bool);
}
