// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ResolverRoleTimelock
 * @notice Adds a mandatory delay before RESOLVER_ROLE grants and revocations can take effect.
 * @dev Contracts inheriting this module keep normal AccessControl behavior for all other roles.
 *      RESOLVER_ROLE changes must be scheduled, wait for RESOLVER_ROLE_CHANGE_DELAY, then executed.
 */
abstract contract ResolverRoleTimelock is AccessControl {
    uint256 public constant MIN_RESOLVER_ROLE_CHANGE_DELAY = 2 days;
    uint256 public constant MAX_RESOLVER_ROLE_CHANGE_DELAY = 14 days; // Max 14 days for role changes

    struct PendingRoleChange {
        uint256 readyAt;
        uint256 expireAt;
        bool executed;
    }

    mapping(bytes32 => PendingRoleChange) public pendingRoleChanges;
    uint256 private _operationNonce; // Nonce for unique operation IDs

    event ResolverRoleChangeScheduled(
        bytes32 indexed operationId,
        address indexed account,
        bool grant,
        uint256 readyAt,
        uint256 expireAt
    );
    event ResolverRoleChangeCancelled(bytes32 indexed operationId, address indexed account, bool grant);
    event ResolverRoleChangeExecuted(bytes32 indexed operationId, address indexed account, bool grant);
    event ResolverRoleChangeExpired(bytes32 indexed operationId, address indexed account, bool grant);

    error ResolverRoleChangeRequiresTimelock();
    error ResolverRoleChangeAlreadyPending();
    error ResolverRoleChangeNotPending();
    error ResolverRoleChangeNotReady(uint256 readyAt);
    error ResolverRoleChangeExpired();
    error ResolverRoleChangeNoop();
    error InvalidDelay(uint256 delay);
    error OperationIdCollision(bytes32 operationId);

    function _resolverRole() internal pure virtual returns (bytes32);

    function scheduleResolverRoleGrant(address account) external onlyRole(getRoleAdmin(_resolverRole())) returns (bytes32 operationId) {
        if (hasRole(_resolverRole(), account)) revert ResolverRoleChangeNoop();
        operationId = _scheduleResolverRoleChange(account, true);
    }

    function scheduleResolverRoleRevoke(address account) external onlyRole(getRoleAdmin(_resolverRole())) returns (bytes32 operationId) {
        if (!hasRole(_resolverRole(), account)) revert ResolverRoleChangeNoop();
        operationId = _scheduleResolverRoleChange(account, false);
    }

    function cancelResolverRoleChange(address account, bool grant) external onlyRole(getRoleAdmin(_resolverRole())) {
        bytes32 operationId = resolverRoleChangeId(account, grant);
        if (resolverRoleChangeReadyAt[operationId] == 0) revert ResolverRoleChangeNotPending();

        delete resolverRoleChangeReadyAt[operationId];
        emit ResolverRoleChangeCancelled(operationId, account, grant);
    }

    function executeResolverRoleGrant(address account) external {
        _executeResolverRoleChange(account, true);
    }

    function executeResolverRoleRevoke(address account) external {
        _executeResolverRoleChange(account, false);
    }

    function resolverRoleChangeId(address account, bool grant) public view returns (bytes32) {
        return keccak256(abi.encode(address(this), _resolverRole(), account, grant));
    }

    function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        if (role == _resolverRole()) revert ResolverRoleChangeRequiresTimelock();
        super.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        if (role == _resolverRole()) revert ResolverRoleChangeRequiresTimelock();
        super.revokeRole(role, account);
    }

    function _scheduleResolverRoleGrant(address account) internal returns (bytes32 operationId) {
        operationId = _scheduleResolverRoleChange(account, true);
    }

    function _scheduleResolverRoleRevoke(address account) internal returns (bytes32 operationId) {
        operationId = _scheduleResolverRoleChange(account, false);
    }

    function scheduleResolverRoleGrantWithDelay(address account, uint256 delay) external onlyRole(getRoleAdmin(_resolverRole())) returns (bytes32 operationId) {
        if (hasRole(_resolverRole(), account)) revert ResolverRoleChangeNoop();
        operationId = _scheduleResolverRoleChange(account, true, delay);
    }

    function scheduleResolverRoleRevokeWithDelay(address account, uint256 delay) external onlyRole(getRoleAdmin(_resolverRole())) returns (bytes32 operationId) {
        if (!hasRole(_resolverRole(), account)) revert ResolverRoleChangeNoop();
        operationId = _scheduleResolverRoleChange(account, false, delay);
    }

    function _scheduleResolverRoleChange(address account, bool grant, uint256 delay) internal returns (bytes32 operationId) {
        // Validate delay is within bounds
        if (delay < MIN_RESOLVER_ROLE_CHANGE_DELAY || delay > MAX_RESOLVER_ROLE_CHANGE_DELAY) {
            revert InvalidDelay(delay);
        }
        
        // Generate unique operation ID using nonce to prevent collisions
        unchecked {
            _operationNonce++;
        }
        operationId = keccak256(abi.encodePacked(address(this), _resolverRole(), account, grant, block.timestamp, _operationNonce));
        
        // Ensure operation ID is unique (defense in depth)
        if (pendingRoleChanges[operationId].readyAt != 0) {
            revert OperationIdCollision(operationId);
        }

        uint256 readyAt = block.timestamp + delay;
        uint256 expireAt = block.timestamp + MAX_RESOLVER_ROLE_CHANGE_DELAY;

        pendingRoleChanges[operationId] = PendingRoleChange({
            readyAt: readyAt,
            expireAt: expireAt,
            executed: false
        });

        emit ResolverRoleChangeScheduled(operationId, account, grant, readyAt, expireAt);
    }

    // Keep original functions for backward compatibility with default delay
    function scheduleResolverRoleGrant(address account) external onlyRole(getRoleAdmin(_resolverRole())) returns (bytes32 operationId) {
        if (hasRole(_resolverRole(), account)) revert ResolverRoleChangeNoop();
        operationId = _scheduleResolverRoleChange(account, true, MIN_RESOLVER_ROLE_CHANGE_DELAY);
    }

    function scheduleResolverRoleRevoke(address account) external onlyRole(getRoleAdmin(_resolverRole())) returns (bytes32 operationId) {
        if (!hasRole(_resolverRole(), account)) revert ResolverRoleChangeNoop();
        operationId = _scheduleResolverRoleChange(account, false, MIN_RESOLVER_ROLE_CHANGE_DELAY);
    }

    function _executeResolverRoleChange(address account, bool grant) internal {
        bytes32 operationId = resolverRoleChangeId(account, grant);
        uint256 readyAt = resolverRoleChangeReadyAt[operationId];
        if (readyAt == 0) revert ResolverRoleChangeNotPending();
        if (block.timestamp < readyAt) revert ResolverRoleChangeNotReady(readyAt);

        delete resolverRoleChangeReadyAt[operationId];

        if (grant) {
            if (hasRole(_resolverRole(), account)) revert ResolverRoleChangeNoop();
            _grantRole(_resolverRole(), account);
        } else {
            if (!hasRole(_resolverRole(), account)) revert ResolverRoleChangeNoop();
            _revokeRole(_resolverRole(), account);
        }

        emit ResolverRoleChangeExecuted(operationId, account, grant);
    }
}