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

    function cancelResolverRoleChange(bytes32 operationId, address account, bool grant) external onlyRole(getRoleAdmin(_resolverRole())) {
        PendingRoleChange storage pendingChange = pendingRoleChanges[operationId];
        if (pendingChange.readyAt == 0) revert ResolverRoleChangeNotPending();
        if (pendingChange.executed) revert ResolverRoleChangeNoop();

        // Remove from storage completely to prevent any future execution
        delete pendingRoleChanges[operationId];
        emit ResolverRoleChangeCancelled(operationId, account, grant);
    }

    function executeResolverRoleGrant(bytes32 operationId, address account) external {
        _executeResolverRoleChange(operationId, account, true);
    }

    function executeResolverRoleRevoke(bytes32 operationId, address account) external {
        _executeResolverRoleChange(operationId, account, false);
    }

    /**
     * @dev Clean up an expired role change. Anyone can call this to free up storage.
     * @param operationId The ID of the expired role change to clean up
     * @param account The account associated with the role change
     * @param grant Whether it was a grant or revoke operation
     */
    function cleanupExpiredRoleChange(bytes32 operationId, address account, bool grant) external {
        PendingRoleChange storage pendingChange = pendingRoleChanges[operationId];
        if (pendingChange.readyAt == 0) revert ResolverRoleChangeNotPending();
        if (block.timestamp <= pendingChange.expireAt) revert ResolverRoleChangeExpired();
        
        // Remove from storage
        delete pendingRoleChanges[operationId];
        emit ResolverRoleChangeExpired(operationId, account, grant);
    }

    function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        if (role == _resolverRole()) revert ResolverRoleChangeRequiresTimelock();
        super.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        if (role == _resolverRole()) revert ResolverRoleChangeRequiresTimelock();
        super.revokeRole(role, account);
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

    function _executeResolverRoleChange(bytes32 operationId, address account, bool grant) internal {
        PendingRoleChange storage pendingChange = pendingRoleChanges[operationId];
        if (pendingChange.readyAt == 0) revert ResolverRoleChangeNotPending();
        if (pendingChange.executed) revert ResolverRoleChangeNoop();
        if (block.timestamp < pendingChange.readyAt) revert ResolverRoleChangeNotReady(pendingChange.readyAt);
        if (block.timestamp > pendingChange.expireAt) {
            // Remove from storage and revert
            delete pendingRoleChanges[operationId];
            emit ResolverRoleChangeExpired(operationId, account, grant);
            revert ResolverRoleChangeExpired();
        }

        // Mark as executed first (reentrancy protection) and then remove from storage completely
        pendingChange.executed = true;
        delete pendingRoleChanges[operationId];

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