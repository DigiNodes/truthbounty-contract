// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IV2Module} from "./IV2Module.sol";

/// @notice Registry mapping canonical module identifiers to their current implementations.
/// @dev Registration and removal are governance-controlled; query functions are permissionless and must fail closed for unknown modules.
interface IModuleRegistry is IV2Module {
    /// @notice Emitted when a module implementation is registered.
    /// @param moduleId Stable canonical module identifier.
    /// @param implementation Contract authorized for the module identifier.
    /// @param major Module ABI major version.
    /// @param minor Module ABI minor version.
    event ModuleRegistered(bytes32 indexed moduleId, address indexed implementation, uint16 major, uint16 minor);

    /// @notice Emitted when a module identifier is removed.
    /// @param moduleId Stable canonical module identifier.
    /// @param implementation Implementation removed at the time of removal.
    event ModuleRemoved(bytes32 indexed moduleId, address indexed implementation);

    /// @notice Registers or replaces a module implementation under the canonical registry authority.
    /// @dev Must enforce the registry's governance authorization and version compatibility rules; unknown implementations must never become authorized.
    /// @param moduleId Stable module identifier.
    /// @param implementation Non-zero contract implementing the module interface.
    function registerModule(bytes32 moduleId, address implementation) external;

    /// @notice Removes a module from the authorization registry.
    /// @dev Must revert for an unknown module and must not mutate unrelated identifiers.
    /// @param moduleId Stable module identifier to remove.
    function removeModule(bytes32 moduleId) external;

    /// @notice Reads the current implementation and ABI version.
    /// @dev Unknown identifiers must revert or return zero values as defined by the implementation; callers must not infer authorization from an empty result.
    /// @param moduleId Stable module identifier.
    /// @return implementation Registered implementation address.
    /// @return major ABI major version.
    /// @return minor ABI minor version.
    function module(bytes32 moduleId) external view returns (address implementation, uint16 major, uint16 minor);

    /// @notice Reports whether an identifier currently has an authorized implementation.
    /// @param moduleId Stable module identifier.
    /// @return registered True only when the module is currently registered.
    function isRegistered(bytes32 moduleId) external view returns (bool registered);
}
