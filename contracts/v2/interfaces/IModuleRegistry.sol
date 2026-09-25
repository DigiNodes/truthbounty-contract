// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
interface IModuleRegistry is IV2Module {
    event ModuleRegistered(bytes32 indexed moduleId, address indexed implementation, uint16 major, uint16 minor, uint64 timestamp, uint16 version);
    event ModuleRemoved(bytes32 indexed moduleId, address indexed implementation, uint64 timestamp, uint16 version);
    function registerModule(bytes32 moduleId, address implementation) external;
    function removeModule(bytes32 moduleId) external;
    function module(bytes32 moduleId) external view returns (address implementation, uint16 major, uint16 minor);
    function isRegistered(bytes32 moduleId) external view returns (bool);
}
