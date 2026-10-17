// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TruthBountyGovernor} from "./TruthBountyGovernor.sol";

/**
 * @title GovernanceRoleTopology
 * @notice Wires production role topology between governor and timelock (V2-SC-026 dependency).
 * @dev Guardian receives an individual canceller role grant on the timelock; the governor is the
 *      sole proposer. Execution is permissionless after the timelock delay.
 *
 *      Timelock administration (V2-SC-026 / V2-SC-127 handoff model):
 *      OpenZeppelin `TimelockController >= 5.0` grants `DEFAULT_ADMIN_ROLE` to the timelock itself
 *      (self administration) and, when the constructor `admin` argument is non-zero, to that
 *      bootstrap administrator. `DEFAULT_ADMIN_ROLE` is the admin of every timelock role, so it is
 *      the only authority capable of mutating the timelock role graph. {finalizeTimelockAdmin}
 *      therefore revokes `DEFAULT_ADMIN_ROLE` from the bootstrap administrator so that after
 *      handoff the timelock (i.e. governance) is the sole role-graph authority.
 *
 *      Older OpenZeppelin releases used a bespoke `TIMELOCK_ADMIN_ROLE`. That role no longer exists
 *      in OZ >= 5.0 and is never granted here; {LEGACY_TIMELOCK_ADMIN_ROLE} is retained only so a
 *      handoff can retire a stale grant from a pre-v5 deployment and so enumeration can flag it.
 */
library GovernanceRoleTopology {
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 internal constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    /// @dev Canonical timelock administration role for OpenZeppelin `>= 5.0`.
    ///      Holds the admin of `PROPOSER_ROLE`, `CANCELLER_ROLE` and `EXECUTOR_ROLE`.
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

    /// @dev Retired OpenZeppelin `< 5.0` timelock administration role.
    ///      Never granted by this library; only ever revoked so a legacy authority cannot survive
    ///      a handoff. Kept for enumeration and negative verification.
    bytes32 internal constant LEGACY_TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");

    /// @notice Emitted after the timelock role topology is configured.
    /// @param timelock Timelock receiving roles.
    /// @param governor Governor receiving proposer and canceller rights.
    /// @param guardian Guardian receiving cancellation rights.
    /// @param minDelay Configured timelock minimum delay in seconds.
    event GovernanceTopologyConfigured(
        address indexed timelock,
        address indexed governor,
        address indexed guardian,
        uint256 minDelay
    );

    /// @notice Emitted after timelock administration is handed to the timelock itself.
    /// @param timelock Timelock whose administration was finalized.
    /// @param retiredAdmin Bootstrap administrator that lost `DEFAULT_ADMIN_ROLE`.
    /// @param legacyRoleRetired Whether a stale `TIMELOCK_ADMIN_ROLE` grant was revoked.
    event TimelockAdminFinalized(
        address indexed timelock,
        address indexed retiredAdmin,
        bool legacyRoleRetired
    );

    /**
     * @dev Assign canonical timelock roles after governor deployment.
     * @param timelock Timelock receiving the role topology.
     * @param governor Governor receiving proposer and canceller rights.
     * @param guardian Guardian receiving an individual canceller-only role grant.
     * @param minDelay Configured minimum execution delay in seconds.
     */
    function configure(
        TimelockController timelock,
        TruthBountyGovernor governor,
        address guardian,
        uint256 minDelay
    ) internal {
        timelock.grantRole(PROPOSER_ROLE, address(governor));
        timelock.grantRole(CANCELLER_ROLE, address(governor));
        timelock.grantRole(CANCELLER_ROLE, guardian);
        timelock.grantRole(EXECUTOR_ROLE, address(0));

        emit GovernanceTopologyConfigured(address(timelock), address(governor), guardian, minDelay);
    }

    /**
     * @dev Hand timelock self-administration to the timelock itself after bootstrap.
     * @param timelock Timelock whose administrator role is finalized.
     * @param currentAdmin Bootstrap administrator whose administration is retired.
     *
     *      The timelock already self-holds `DEFAULT_ADMIN_ROLE` from its constructor, so this only
     *      removes the bootstrap authority: the user-supplied `currentAdmin` and any stale legacy
     *      administration grant. Afterwards exactly one account can mutate the timelock role graph:
     *      the timelock itself (governance).
     */
    function finalizeTimelockAdmin(TimelockController timelock, address currentAdmin) internal {
        bool legacyRoleRetired;

        // 1. Retire stale pre-v5 administration before touching the canonical admin role.
        //    `getRoleAdmin(LEGACY_TIMELOCK_ADMIN_ROLE)` defaults to `DEFAULT_ADMIN_ROLE`, so the
        //    caller must still hold administration here — which it does during bootstrap.
        if (currentAdmin != address(0) && timelock.hasRole(LEGACY_TIMELOCK_ADMIN_ROLE, currentAdmin)) {
            timelock.revokeRole(LEGACY_TIMELOCK_ADMIN_ROLE, currentAdmin);
            legacyRoleRetired = true;
        }

        // 2. Revoke the canonical administration role from the bootstrap administrator. The
        //    timelock address is skipped so a caller can never strip the timelock's own
        //    self-administration and brick the role graph.
        if (currentAdmin != address(timelock)) {
            timelock.revokeRole(DEFAULT_ADMIN_ROLE, currentAdmin);
        }

        emit TimelockAdminFinalized(address(timelock), currentAdmin, legacyRoleRetired);
    }
}
