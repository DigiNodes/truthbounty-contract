// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IV2Module} from "./IV2Module.sol";

/// @notice Scoped emergency pause interface.
/// @dev Pause state is fail-closed for mutating protocol operations; only the configured emergency authority may change it and unpause must satisfy configured cooldowns.
/// @dev Unpause is governed: guardians may pause but must never unpause. Governed unpause requires a timelocked authority, an incident reference, a repaired release, dependency health evidence, and the current pause state.
interface IEmergencyControls is IV2Module {
    /// @notice Emitted when a scope is paused.
    /// @param scope Stable module or protocol scope identifier.
    /// @param actor Emergency authority that paused the scope.
    event EmergencyPaused(bytes32 indexed scope, address indexed actor);

    /// @notice Emitted when a scope is unpaused.
    /// @param scope Stable module or protocol scope identifier.
    /// @param actor Emergency authority that unpaused the scope.
    event EmergencyUnpaused(bytes32 indexed scope, address indexed actor);

    /// @notice Emitted when a governed unpause is scheduled and timelock registered.
    /// @dev Links the original pause incident to the governed resolution effort.
    /// @param scope Stable module or protocol scope identifier.
    /// @param incidentRef Incident reference associated with the pause.
    /// @param release The repaired release identifier authorized for unpause.
    /// @param etaTimestamp Timestamp at which the timelock becomes ready.
    /// @param actor Governed authority that scheduled the unpause.
    event GovernedUnpauseScheduled(
        bytes32 indexed scope,
        bytes32 indexed incidentRef,
        bytes32 indexed release,
        uint64 etaTimestamp,
        address indexed actor
    );

    /// @notice Emitted when a governed unpause is executed and the scope resumes.
    /// @dev Links the governed resolution back to the original pause incident.
    /// @param scope Stable module or protocol scope identifier.
    /// @param incidentRef Incident reference associated with the pause.
    /// @param release The repaired release identifier authorized for unpause.
    /// @param actor Governed authority that executed the unpause.
    event GovernedUnpauseExecuted(bytes32 indexed scope, bytes32 indexed incidentRef, bytes32 indexed release, address indexed actor);

    /// @notice Pauses all protected operations in a scope.
    /// @dev Must require emergency authority and preserve already finalized state while blocking new transitions.
    /// @param scope Stable scope identifier.
    function pause(bytes32 scope) external;

    /// @notice Unpauses a scope after the configured recovery rules are satisfied.
    /// @dev Must require the governed recovery role and revert while cooldown or governance conditions remain unsatisfied.
    /// Guardians must never be able to unpause.
    /// @param scope Stable scope identifier.
    /// @param incidentRef Incident reference associated with the pause being resolved.
    /// @param release Repaired release identifier authorized for this unpause.
    /// @param dependencyHealth Hash of the dependency health evidence for this unpause.
    function unpause(bytes32 scope, bytes32 incidentRef, bytes32 release, bytes32 dependencyHealth) external;

    /// @notice Reports whether a scope is currently paused.
    /// @param scope Stable scope identifier.
    /// @return isPaused True while new operations must fail closed.
    function paused(bytes32 scope) external view returns (bool isPaused);

    /// @notice Reports the timelock readiness of a governed unpause for a scope.
    /// @dev Machine-verifiable precondition for the governed unpause boundary.
    /// @param scope Stable scope identifier.
    /// @return ready True only when all governed unpause preconditions are met.
    function unpauseReady(bytes32 scope) external view returns (bool ready);
}
