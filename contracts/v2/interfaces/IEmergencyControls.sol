// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IV2Module} from "./IV2Module.sol";

/// @notice Scoped emergency pause interface.
/// @dev Pause state is fail-closed for mutating protocol operations; only the configured emergency authority may change it and unpause must satisfy configured cooldowns.
/// @dev Every pausable mutation is identified by a stable operation ID derived from function/interface authority. Operation IDs are canonical, collision-resistant, and scoped to a single scope so they cannot be aliased or escalated to global pause state.
interface IEmergencyControls is IV2Module {
    /// @notice Enumerates a pausable operation and the contracts/functions it affects.
    /// @param operation Stable operation identifier used as a pause scope.
    /// @param targets Contracts whose functions are gated by the operation scope.
    /// @param selectors Function selectors gated by the operation scope.
    struct OperationScope {
        bytes32 operation;
        address[] targets;
        bytes4[] selectors;
    }

    /// @notice Emitted when the operation-scoped pause matrix is updated.
    /// @param matrixHash Hash of the canonical operation-scope matrix.
    /// @param actor Authority that updated the matrix.
    event PauseMatrixUpdated(bytes32 indexed matrixHash, address indexed actor);

    /// @notice Emitted when a scope is paused.
    /// @param scope Stable module or protocol scope identifier.
    /// @param actor Emergency authority that paused the scope.
    event EmergencyPaused(bytes32 indexed scope, address indexed actor);

    /// @notice Emitted when a scope is unpaused.
    /// @param scope Stable module or protocol scope identifier.
    /// @param actor Emergency authority that unpaused the scope.
    event EmergencyUnpaused(bytes32 indexed scope, address indexed actor);

    /// @notice Emitted when a scope's pause state is reconciled by off-chain consumers.
    /// @param scope Stable module or protocol scope identifier.
    /// @param isPaused Current pause state after the transition.
    /// @param nonce Monotonic per-scope transition nonce for reconciliation.
    event EmergencyPauseStateChanged(
        bytes32 indexed scope,
        bool indexed isPaused,
        uint256 nonce
    );

    /// @notice Emitted when an operation within a scope is paused.
    /// @param scope Stable module or protocol scope identifier.
    /// @param operationId Canonical operation ID derived from function/interface authority.
    /// @param actor Emergency authority that paused the operation.
    event OperationPaused(bytes32 indexed scope, bytes32 indexed operationId, address indexed actor);

    /// @notice Emitted when an operation within a scope is unpaused.
    /// @param scope Stable module or protocol scope identifier.
    /// @param operationId Canonical operation ID derived from function/interface authority.
    /// @param actor Emergency authority that unpaused the operation.
    event OperationUnpaused(bytes32 indexed scope, bytes32 indexed operationId, address indexed actor);

    /// @notice Emitted when a canonical operation ID is registered for a scope.
    /// @param scope Stable module or protocol scope identifier.
    /// @param operationId Canonical operation ID derived from function/interface authority.
    /// @param selector Function selector that the operation ID binds to.
    event OperationRegistered(bytes32 indexed scope, bytes32 indexed operationId, bytes4 indexed selector);

    /// @notice Pauses all protected operations in a scope.
    /// @dev Must require emergency authority and preserve already finalized state while blocking new transitions.
    /// @param scope Stable scope identifier.
    function pause(bytes32 scope) external;

    /// @notice Unpauses a scope after the configured recovery rules are satisfied.
    /// @dev Must require the authorized recovery role and revert while cooldown or governance conditions remain unsatisfied.
    /// @param scope Stable scope identifier.
    function unpause(bytes32 scope) external;

    /// @notice Pauses a single canonical operation within a scope.
    /// @dev Must require emergency authority, reject unknown operation IDs, and never alias another operation or global scope.
    /// @param scope Stable scope identifier.
    /// @param operationId Canonical operation ID derived from function/interface authority.
    function pauseOperation(bytes32 scope, bytes32 operationId) external;

    /// @notice Unpauses a single canonical operation within a scope.
    /// @dev Must require the authorized recovery role and revert while cooldown or governance conditions remain unsatisfied.
    /// @param scope Stable scope identifier.
    /// @param operationId Canonical operation ID derived from function/interface authority.
    function unpauseOperation(bytes32 scope, bytes32 operationId) external;

    /// @notice Reports whether a scope is currently paused.
    /// @param scope Stable scope identifier.
    /// @return isPaused True while new operations must fail closed.
    function paused(bytes32 scope) external view returns (bool isPaused);

    /// @notice Returns the operation-scoped pause matrix entry for an operation.
    /// @dev Reverts if the operation is not declared in the matrix; missing authority fails closed.
    /// @param operation Stable operation identifier.
    /// @return entry Declared targets and selectors gated by the operation.
    function operationScope(bytes32 operation)
        external
        view
        returns (OperationScope memory entry);

    /// @notice Returns whether a specific target/selector pair is gated by an operation.
    /// @param operation Stable operation identifier.
    /// @param target Contract address to check.
    /// @param selector Function selector to check.
    /// @return isGated True if the operation gates the target/selector pair.
    function isOperationGated(
        bytes32 operation,
        address target,
        bytes4 selector
    ) external view returns (bool isGated);

    /// @notice Returns the emergency authority permitted to pause scopes.
    /// @return authority Address of the emergency authority.
    function emergencyAuthority() external view returns (address authority);

    /// @notice Returns the governed recovery authority permitted to unpause scopes.
    /// @return authority Address of the governed recovery authority.
    function recoveryAuthority() external view returns (address authority);

    /// @notice Reports whether a specific operation within a scope is currently paused.
    /// @dev Must fail closed for unknown operation IDs.
    /// @param scope Stable scope identifier.
    /// @param operationId Canonical operation ID derived from function/interface authority.
    /// @return isPaused True while the operation must fail closed.
    function operationPaused(bytes32 scope, bytes32 operationId) external view returns (bool isPaused);

    /// @notice Returns the canonical operation ID for a given scope and function selector.
    /// @dev Must return a stable ID derived from function/interface authority and must revert for unknown or aliased selectors.
    /// @param scope Stable scope identifier.
    /// @param selector Function selector to resolve.
    /// @return operationId Canonical operation ID bound to the scope and selector.
    function operationIdForSelector(bytes32 scope, bytes4 selector) external view returns (bytes32 operationId);

    /// @notice Returns the function selector bound to a canonical operation ID within a scope.
    /// @dev Must revert for unknown operation IDs and must not alias across scopes.
    /// @param scope Stable scope identifier.
    /// @param operationId Canonical operation ID derived from function/interface authority.
    /// @return selector Function selector bound to the operation ID.
    function selectorForOperationId(bytes32 scope, bytes32 operationId) external view returns (bytes4 selector);

    /// @notice Returns the canonical operation IDs registered for a scope.
    /// @dev The returned matrix must match runtime checks and must not include aliases.
    /// @param scope Stable scope identifier.
    /// @return operationIds Canonical operation IDs for the scope.
    function operationIdsForScope(bytes32 scope) external view returns (bytes32[] memory operationIds);

    /// @notice Returns the canonical operation ID for a scope and function signature.
    /// @dev Must be deterministic and must revert for unknown or aliased signatures.
    /// @param scope Stable scope identifier.
    /// @param signature Canonical function signature.
    /// @return operationId Canonical operation ID bound to the scope and signature.
    function operationIdForSignature(bytes32 scope, bytes memory signature) external view returns (bytes32 operationId);
}