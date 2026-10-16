// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IV2Module} from "./IV2Module.sol";

/// @notice Scoped emergency pause interface.
/// @dev Pause state is fail-closed for mutating protocol operations; only the configured emergency authority may change it and unpause must satisfy configured cooldowns.
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

    /// @notice Pauses all protected operations in a scope.
    /// @dev Must require emergency authority and preserve already finalized state while blocking new transitions.
    /// @param scope Stable scope identifier.
    function pause(bytes32 scope) external;

    /// @notice Unpauses a scope after the configured recovery rules are satisfied.
    /// @dev Must require the authorized recovery role and revert while cooldown or governance conditions remain unsatisfied.
    /// @param scope Stable scope identifier.
    function unpause(bytes32 scope) external;

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
}
