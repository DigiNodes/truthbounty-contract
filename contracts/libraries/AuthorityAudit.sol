// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AuthorityAudit
/// @notice Canonical emission helpers for access-control mutations that
///         currently change authority state without publishing any event.
/// @dev PREWAVE-SC-071 (#747).
///
///      Scope. This library covers *silent* authority mutations only: states
///      that are not already recorded by an OpenZeppelin `RoleGranted` /
///      `RoleRevoked` emission and had no domain event of their own. Emitting
///      here in addition to an existing event would double-log and is therefore
///      deliberately not done.
///
///      Effectiveness. Every helper reads the pre-state and emits only when the
///      mutation is *effective*. Re-granting an authority that is already held is
///      a no-op and is not logged, so a log replay reconstructs authority exactly
///      rather than approximately. This mirrors OpenZeppelin's `grantRole`,
///      which likewise returns silently on a redundant grant.
///
///      Gas. Events are declared on the library so that the `internal` helpers
///      can emit without every participating contract having to inherit an
///      interface. Internal library calls are inlined, so the log address is
///      the calling contract.
library AuthorityAudit {
    /// @notice Authority source discriminators, mirroring `AuthoritySource`.
    /// @dev Zero is reserved for "unset" so that a default-constructed value is
    ///      never mistaken for a real source.
    uint8 internal constant SOURCE_UNSPECIFIED = 0;
    /// @dev Mutation performed directly by a role holder or the contract owner.
    uint8 internal constant SOURCE_ADMIN = 1;
    /// @dev Mutation performed by an executed timelock operation.
    uint8 internal constant SOURCE_TIMELOCK = 2;
    /// @dev Mutation performed through the on-chain governor.
    uint8 internal constant SOURCE_GOVERNANCE = 3;
    /// @dev Mutation performed by the subject acting on its own authority.
    uint8 internal constant SOURCE_SELF = 4;
    /// @dev Authority established during deployment or a re-initialisation.
    uint8 internal constant SOURCE_INITIALIZATION = 5;
    /// @dev Mutation performed as part of an upgrade or migration.
    uint8 internal constant SOURCE_UPGRADE = 6;

    /// @notice Schema version stamped on the `Authority*V2` events.
    uint16 internal constant EVENT_VERSION = 2;

    /// @notice Authority identifiers for non-`AccessControl` authority state.
    /// @dev Namespaced with a domain prefix to avoid colliding with role
    ///      identifiers such as `keccak256("ADMIN_ROLE")`.
    bytes32 internal constant ROLE_RELAYER = keccak256("AUTHORITY_ROLE_RELAYER");
    bytes32 internal constant ROLE_CHAIN = keccak256("AUTHORITY_ROLE_CHAIN");
    bytes32 internal constant ROLE_SUPPORTED_ASSET = keccak256("AUTHORITY_ROLE_SUPPORTED_ASSET");
    bytes32 internal constant ROLE_PARAMETER_REGISTRY = keccak256("AUTHORITY_ROLE_PARAMETER_REGISTRY");
    bytes32 internal constant ROLE_BOND_TOKEN = keccak256("AUTHORITY_ROLE_BOND_TOKEN");
    bytes32 internal constant ROLE_BOUNTY_TOKEN = keccak256("AUTHORITY_ROLE_BOUNTY_TOKEN");
    bytes32 internal constant ROLE_REPUTATION_ROOTS = keccak256("AUTHORITY_ROLE_REPUTATION_ROOTS");
    bytes32 internal constant ROLE_REPUTATION_ORACLE = keccak256("AUTHORITY_ROLE_REPUTATION_ORACLE");
    bytes32 internal constant ROLE_IMPLEMENTATION = keccak256("AUTHORITY_ROLE_IMPLEMENTATION");
    bytes32 internal constant ROLE_RUNTIME_CODE_HASH = keccak256("AUTHORITY_ROLE_RUNTIME_CODE_HASH");
    bytes32 internal constant ROLE_TIMELOCK_COOLDOWN = keccak256("AUTHORITY_ROLE_TIMELOCK_COOLDOWN");
    bytes32 internal constant ROLE_BOOTSTRAP_CONFIG = keccak256("AUTHORITY_ROLE_BOOTSTRAP_CONFIG");
    bytes32 internal constant ROLE_ASSIGNMENT_ROUND = keccak256("AUTHORITY_ROLE_ASSIGNMENT_ROUND");
    bytes32 internal constant ROLE_ELIGIBILITY_SNAPSHOT = keccak256("AUTHORITY_ROLE_ELIGIBILITY_SNAPSHOT");

    /// @notice Mirrors `ITruthBountyEvents.AuthorityGrantedV2`.
    event AuthorityGrantedV2(
        bytes32 indexed role,
        address indexed account,
        address indexed actor,
        uint8 source,
        uint64 timestamp,
        uint16 version
    );

    /// @notice Mirrors `ITruthBountyEvents.AuthorityRevokedV2`.
    event AuthorityRevokedV2(
        bytes32 indexed role,
        address indexed account,
        address indexed actor,
        uint8 source,
        uint64 timestamp,
        uint16 version
    );

    /// @notice Emits `AuthorityGrantedV2` for a boolean authority flag.
    /// @dev Caller is responsible for writing `flag` before calling.
    function grantFlag(
        bytes32 role,
        address account,
        address actor,
        bool wasHeld
    ) internal {
        if (wasHeld) return;
        emit AuthorityGrantedV2(role, account, actor, SOURCE_ADMIN, uint64(block.timestamp), EVENT_VERSION);
    }

    /// @notice Emits `AuthorityRevokedV2` for a boolean authority flag.
    /// @dev Caller is responsible for writing `flag` before calling.
    function revokeFlag(
        bytes32 role,
        address account,
        address actor,
        bool wasHeld
    ) internal {
        if (!wasHeld) return;
        emit AuthorityRevokedV2(role, account, actor, SOURCE_ADMIN, uint64(block.timestamp), EVENT_VERSION);
    }

    /// @notice Emits `AuthorityRevokedV2` when `previous` differs from `next`.
    /// @dev Used for authority expressed as a single address rather than a flag,
    ///      where the change is identified by the pointer actually moving.
    function revokeIfReplaced(
        bytes32 role,
        address previous,
        address actor,
        address next
    ) internal {
        if (previous == address(0) || previous == next) return;
        emit AuthorityRevokedV2(role, previous, actor, SOURCE_ADMIN, uint64(block.timestamp), EVENT_VERSION);
    }

    /// @notice Emits `AuthorityGrantedV2` when `next` is a new non-zero pointer.
    function grantIfAssigned(
        bytes32 role,
        address previous,
        address account,
        address actor,
        address next
    ) internal {
        if (next == address(0) || next == previous) return;
        emit AuthorityGrantedV2(role, account, actor, SOURCE_ADMIN, uint64(block.timestamp), EVENT_VERSION);
    }
}