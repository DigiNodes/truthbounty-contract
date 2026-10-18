// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IGovernedModuleRegistry} from "./IGovernedModuleRegistry.sol";

/**
 * @title GovernedModuleRegistry
 * @notice Maintains the allowlist of contracts that governance proposals may call.
 * @dev Only the timelock (via governance) or admin may mutate the registry during bootstrap.
 */
contract GovernedModuleRegistry is IGovernedModuleRegistry, AccessControl {
    /// @notice Role permitted to mutate the governed module allowlist.
    bytes32 public constant REGISTRY_ADMIN_ROLE = keccak256("REGISTRY_ADMIN_ROLE");

    mapping(address => bool) private _isRegistered;
    mapping(bytes32 => address) private _moduleByKey;
    address[] private _modules;
    mapping(address => uint256) private _moduleIndex;

    /// @param admin Bootstrap administrator receiving the default admin and registry admin roles.
    constructor(address admin) {
        if (admin == address(0)) revert ZeroModuleAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRY_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IGovernedModuleRegistry
    function registerModule(bytes32 moduleKey, address module) external onlyRole(REGISTRY_ADMIN_ROLE) {
        if (module == address(0)) revert ZeroModuleAddress();
        if (_isRegistered[module]) revert ModuleAlreadyRegistered(module);
        if (_moduleByKey[moduleKey] != address(0)) revert ModuleAlreadyRegistered(module);

        _isRegistered[module] = true;
        _moduleByKey[moduleKey] = module;
        _moduleIndex[module] = _modules.length;
        _modules.push(module);

        emit GovernedModuleRegistered(module, moduleKey);
    }

    /// @inheritdoc IGovernedModuleRegistry
    function removeModule(bytes32 moduleKey) external onlyRole(REGISTRY_ADMIN_ROLE) {
        address module = _moduleByKey[moduleKey];
        if (module == address(0)) revert ModuleNotRegistered(module);
        if (!_isRegistered[module]) revert ModuleNotRegistered(module);

        _isRegistered[module] = false;
        delete _moduleByKey[moduleKey];

        uint256 index = _moduleIndex[module];
        uint256 lastIndex = _modules.length - 1;
        if (index != lastIndex) {
            address lastModule = _modules[lastIndex];
            _modules[index] = lastModule;
            _moduleIndex[lastModule] = index;
        }
        _modules.pop();
        delete _moduleIndex[module];

        emit GovernedModuleRemoved(module, moduleKey);
    }

    /// @inheritdoc IGovernedModuleRegistry
    function isGovernedModule(address module) external view returns (bool) {
        return _isRegistered[module];
    }

    /// @inheritdoc IGovernedModuleRegistry
    function moduleByKey(bytes32 moduleKey) external view returns (address) {
        return _moduleByKey[moduleKey];
    }

    /// @inheritdoc IGovernedModuleRegistry
    function moduleCount() external view returns (uint256) {
        return _modules.length;
    }

    /// @inheritdoc IGovernedModuleRegistry
    function moduleAt(uint256 index) external view returns (address) {
        return _modules[index];
    }

    /// @inheritdoc IGovernedModuleRegistry
    function modulesPage(uint256 offset, uint256 limit) external view returns (address[] memory page) {
        uint256 length = _modules.length;
        if (offset >= length) return new address[](0);
        uint256 end = offset + limit;
        if (end > length) end = length;
        uint256 count = end - offset;
        page = new address[](count);
        for (uint256 i = 0; i < count; ++i) {
            page[i] = _modules[offset + i];
        }
    }

    /// @inheritdoc IGovernedModuleRegistry
    function moduleIndexOf(address module) external view returns (uint256) {
        if (!_isRegistered[module]) return type(uint256).max;
        return _moduleIndex[module];
    }

    /// @inheritdoc IGovernedModuleRegistry
    function getModules() external view returns (address[] memory) {
        return _modules;
    }

    /// @inheritdoc IGovernedModuleRegistry
    function getRoleMemberCount(bytes32 role) external view returns (uint256) {
        return getRoleMembers(role).length;
    }

    /// @inheritdoc IGovernedModuleRegistry
    function getRoleMembers(bytes32 role) public view returns (address[] memory) {
        return _getRoleMembers(role);
    }

    /// @inheritdoc IGovernedModuleRegistry
    function getRoleMembersPaged(bytes32 role, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory page)
    {
        address[] memory members = _getRoleMembers(role);
        uint256 length = members.length;
        if (offset >= length) return new address[](0);
        uint256 end = offset + limit;
        if (end > length) end = length;
        uint256 count = end - offset;
        page = new address[](count);
        for (uint256 i = 0; i < count; ++i) {
            page[i] = members[offset + i];
        }
    }

    /// @inheritdoc IGovernedModuleRegistry
    function hasRole(bytes32 role, address account) public view override returns (bool) {
        return super.hasRole(role, account);
    }

    /// @inheritdoc AccessControl
    function grantRole(bytes32 role, address account) public override onlyRole(getRoleAdmin(role)) {
        if (!hasRole(role, account)) {
            super.grantRole(role, account);
        }
    }

    /// @inheritdoc AccessControl
    function revokeRole(bytes32 role, address account) public override onlyRole(getRoleAdmin(role)) {
        if (hasRole(role, account)) {
            super.revokeRole(role, account);
        }
    }

    /// @inheritdoc AccessControl
    function renounceRole(bytes32 role, address account) public override {
        if (account != _msgSender() && !(hasRole(getRoleAdmin(role), _msgSender()))) {
            revert AccessControlUnauthorizedAccount(_msgSender());
        }
        if (hasRole(role, account)) {
            super.renounceRole(role, account);
        }
    }

    /// @inheritdoc AccessControl
    function _grantRole(bytes32 role, address account) internal override {
        super._grantRole(role, account);
    }

    /// @inheritdoc AccessControl
    function _revokeRole(bytes32 role, address account) internal override {
        super._revokeRole(role, account);
    }
}
