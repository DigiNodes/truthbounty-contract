// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";

/// @notice Operation-scoped emergency control plane for the TruthBounty V2 protocol.
/// @dev Implementations MUST fail closed. A scope that is not part of the canonical manifest is
///      never reported as operable: `requireOperationAllowed` reverts, `paused` reverts, and
///      `isOperationAllowed` returns false. Reopening a scope is impossible until its documented
///      recovery conditions are met, its recovery timelock has elapsed, and governance authorises
///      the lift.
interface IEmergencyControls is IV2Module {
    /// @notice Emitted when a scope becomes paused.
    event EmergencyPaused(bytes32 indexed scope, address indexed actor);
    /// @notice Emitted when a scope is reopened.
    event EmergencyUnpaused(bytes32 indexed scope, address indexed actor);

    /// @notice Emitted with the full audit payload of a pause activation.
    event ScopePauseRecorded(
        bytes32 indexed scope,
        address indexed actor,
        uint256 indexed sequence,
        uint256 unlockReadyAt,
        string reason
    );

    /// @notice Emitted with the full audit payload of a scope reopening.
    event ScopeUnpauseRecorded(
        bytes32 indexed scope,
        address indexed actor,
        uint256 indexed sequence,
        bytes32 proposalRef,
        uint256 pausedDuration
    );

    /// @notice Emitted when governance documents a precondition for reopening a paused scope.
    event RecoveryConditionDeclared(bytes32 indexed scope, bytes32 indexed conditionId, string description);

    /// @notice Emitted when the recovery executor attests that a documented condition is met.
    event RecoveryConditionSatisfied(
        bytes32 indexed scope,
        bytes32 indexed conditionId,
        address indexed actor,
        string evidence
    );

    /// @notice Emitted when governance waives a documented condition with a recorded justification.
    event RecoveryConditionWaived(
        bytes32 indexed scope,
        bytes32 indexed conditionId,
        address indexed actor,
        string justification
    );

    /// @notice Emitted when the recovery timelock duration changes.
    event RecoveryDelayUpdated(uint256 previousDelay, uint256 newDelay);

    /// @notice Emitted when a scope is added to the known-scope set.
    event ScopeRegistered(bytes32 indexed scope, string description);

    /// @notice Pauses a single scope. Unknown scopes revert.
    function pause(bytes32 scope) external;

    /// @notice Reopens a single scope once its recovery prerequisites are met. Unknown scopes revert.
    function unpause(bytes32 scope) external;

    /// @notice Returns whether a scope is paused, including via the global kill switch.
    /// @dev Reverts for an unknown scope rather than reporting `false`.
    function paused(bytes32 scope) external view returns (bool);

    /// @notice Pauses a single scope and records a human-readable reason. Unknown scopes revert.
    function pauseWithReason(bytes32 scope, string calldata reason) external;

    /// @notice Reopens a single scope and records the authorising governance reference.
    function unpauseWithReference(bytes32 scope, bytes32 proposalRef) external;

    /// @notice Reverts unless the scope is canonical and currently operable.
    /// @dev This is the enforcement path used by guarded modules. Unknown scopes revert.
    function requireOperationAllowed(bytes32 scope) external view;

    /// @notice Returns false for a paused scope and for any unknown scope. Never reverts.
    function isOperationAllowed(bytes32 scope) external view returns (bool);

    /// @notice Returns true when the scope is part of the known-scope set.
    function isKnownScope(bytes32 scope) external view returns (bool);

    /// @notice Documents a precondition that must be met before the paused scope may reopen.
    function declareRecoveryCondition(bytes32 scope, bytes32 conditionId, string calldata description) external;

    /// @notice Attests that a documented precondition for the paused scope has been met.
    function satisfyRecoveryCondition(bytes32 scope, bytes32 conditionId, string calldata evidence) external;

    /// @notice Waives a documented precondition with a recorded governance justification.
    function waiveRecoveryCondition(bytes32 scope, bytes32 conditionId, string calldata justification) external;

    /// @notice Returns the earliest timestamp at which the paused scope may reopen.
    function recoveryReadyAt(bytes32 scope) external view returns (uint256);

    /// @notice Returns the timestamp at which the scope was most recently reopened.
    function scopeUnpausedAt(bytes32 scope) external view returns (uint256);

    /// @notice Returns the recovery posture of a scope.
    function recoveryStatus(bytes32 scope)
        external
        view
        returns (bool isPaused, uint256 readyAt, uint256 declaredConditions, uint256 outstandingConditions);

    /// @notice Returns the number of scopes in the known-scope set.
    function scopeCount() external view returns (uint256);

    /// @notice Returns the known scope at a given index of the known-scope set.
    function scopeAt(uint256 index) external view returns (bytes32);

    /// @notice Returns true when the scope belongs to the canonical manifest.
    function isScopeCanonical(bytes32 scope) external pure returns (bool);

    /// @notice Returns the number of recovery conditions declared for a scope.
    function recoveryConditionCount(bytes32 scope) external view returns (uint256);

    /// @notice Returns the recovery condition identifier at an index of a scope's declaration list.
    function recoveryConditionAt(bytes32 scope, uint256 index) external view returns (bytes32);

    /// @notice Returns the full record of a declared recovery condition.
    function recoveryCondition(bytes32 scope, bytes32 conditionId)
        external
        view
        returns (
            bool declared,
            bool satisfied,
            bool waived,
            string memory description,
            address decidedBy,
            uint256 decidedAt
        );

    /// @notice Adds a scope to the known-scope set for a future canonical module.
    function registerScope(bytes32 scope, string calldata description) external;

    /// @notice Updates the recovery timelock applied to newly paused scopes.
    function setRecoveryDelay(uint256 newDelay) external;
}
