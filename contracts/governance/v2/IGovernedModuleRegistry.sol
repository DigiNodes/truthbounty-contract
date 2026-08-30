// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IGovernedModuleRegistry
 * @notice Canonical registry of module addresses that governance may target.
 */
interface IGovernedModuleRegistry {
    event GovernedModuleRegistered(address indexed module, bytes32 indexed moduleKey);
    event GovernedModuleRemoved(address indexed module, bytes32 indexed moduleKey);

    error ModuleNotRegistered(address module);
    error ModuleAlreadyRegistered(address module);
    error ZeroModuleAddress();

    function registerModule(bytes32 moduleKey, address module) external;
    function removeModule(bytes32 moduleKey) external;
    function isGovernedModule(address module) external view returns (bool);
    function moduleByKey(bytes32 moduleKey) external view returns (address);
    function moduleCount() external view returns (uint256);
    function moduleAt(uint256 index) external view returns (address);
}
