// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IModuleRegistry} from "../v2/interfaces/IModuleRegistry.sol";
import {IV2Module} from "../v2/interfaces/IV2Module.sol";

/// @dev Test helper implementing the module registry surface for StakeVault authorization tests.
contract MockModuleRegistry is ERC165, IModuleRegistry {
    struct ModuleEntry {
        address implementation;
        uint16 major;
        uint16 minor;
        bool registered;
    }

    mapping(bytes32 => ModuleEntry) private _modules;

    function protocolVersion() external pure override returns (uint16 major, uint16 minor) {
        return (2, 0);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IModuleRegistry).interfaceId || interfaceId == type(IV2Module).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function registerModule(bytes32 moduleId, address implementation) external override {
        _modules[moduleId] = ModuleEntry({implementation: implementation, major: 2, minor: 0, registered: true});
        emit ModuleRegistered(moduleId, implementation, 2, 0);
    }

    function removeModule(bytes32 moduleId) external override {
        ModuleEntry memory entry = _modules[moduleId];
        delete _modules[moduleId];
        emit ModuleRemoved(moduleId, entry.implementation);
    }

    function module(bytes32 moduleId) external view override returns (address implementation, uint16 major, uint16 minor) {
        ModuleEntry memory entry = _modules[moduleId];
        return (entry.implementation, entry.major, entry.minor);
    }

    function isRegistered(bytes32 moduleId) external view override returns (bool) {
        return _modules[moduleId].registered;
    }
}
