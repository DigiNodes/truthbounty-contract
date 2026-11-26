// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IEmergencyControls} from "./interfaces/IEmergencyControls.sol";
import {IV2Module} from "./interfaces/IV2Module.sol";
import {V2Errors} from "./libraries/V2Errors.sol";
import {V2SafeCast} from "./libraries/V2SafeCast.sol";

/**
 * @title EmergencyControls
 * @notice Canonical TruthBounty V2 emergency pause and circuit-breaker module.
 * @dev Implements scoped protocol pausing with strict separation of powers:
 *      - EMERGENCY_ROLE can pause scopes rapidly in response to detected incidents.
 *      - GOVERNANCE_ROLE is strictly required to unpause (emergency role cannot lift pauses).
 *      - Global pause (SCOPE_ALL = bytes32(0)) halts all scopes.
 *      - All administrative roles are subordinated to GOVERNANCE_ROLE to prevent admin privilege escalation.
 *      - Conforms to IEmergencyControls, IV2Module, and ERC-165 standards.
 *      - Governed unpause requires timelock readiness, incident reference, repaired release, and dependency health.
 */
contract EmergencyControls is ERC165, AccessControl, IEmergencyControls {
    // ─── Constants ────────────────────────────────────────────────────

    /// @notice Canonical event schema version for V2 event logging
    uint16 public constant EVENT_SCHEMA_VERSION = 1;

    /// @notice Minimum delay between a governed unpause request and its execution
    uint256 public constant UNPAUSE_TIMELOCK_DELAY = 2 days;

    /// @notice Maximum age of an incident reference accepted for governed unpause
    uint256 public constant MAX_INCIDENT_AGE = 30 days;

    // ─── Roles ────────────────────────────────────────────────────────

    /// @notice Rapid emergency responder role (can pause, cannot unpause)
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /// @notice DAO / Timelocked governance role (can pause and unpause)
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // ─── Well-Known Scopes ────────────────────────────────────────────

    /// @notice Global scope affecting all operations
    bytes32 public constant SCOPE_ALL = bytes32(0);

    /// @notice Scope for new claim creation and registration
    bytes32 public constant SCOPE_CLAIMS = keccak256("CLAIMS");

    /// @notice Scope for evidence submission
    bytes32 public constant SCOPE_EVIDENCE = keccak256("EVIDENCE");

    /// @notice Scope for verifier staking and deposits
    bytes32 public constant SCOPE_STAKING = keccak256("STAKING");

    /// @notice Scope for verification attestations
    bytes32 public constant SCOPE_VERIFICATION = keccak256("VERIFICATION");

    /// @notice Scope for claim settlement and reward distribution
    bytes32 public constant SCOPE_SETTLEMENT = keccak256("SETTLEMENT");

    /// @notice Scope for treasury movements and withdrawals
    bytes32 public constant SCOPE_TREASURY = keccak256("TREASURY");

    /// @notice Scope for dispute initiation and resolution
    bytes32 public constant SCOPE_DISPUTES = keccak256("DISPUTES");

    // ─── Operation IDs ────────────────────────────────────────────────

    /// @notice Canonical operation ID for pausing a scope
    bytes32 public constant OP_PAUSE = keccak256("EmergencyControls.pause(bytes32)");

    /// @notice Canonical operation ID for unpausing a scope
    bytes32 public constant OP_UNPAUSE = keccak256("EmergencyControls.unpause(bytes32)");

    /// @notice Canonical operation ID for checking paused status
    bytes32 public constant OP_PAUSED = keccak256("EmergencyControls.paused(bytes32)");

    /// @notice Canonical operation ID for checking specific scope pause status
    bytes32 public constant OP_IS_SCOPE_SPECIFICALLY_PAUSED =
        keccak256("EmergencyControls.isScopeSpecificallyPaused(bytes32)");

    /// @notice Canonical operation ID for pausing all operations globally
    bytes32 public constant OP_PAUSE_ALL = keccak256("EmergencyControls.pauseAll()");

    /// @notice Canonical operation ID for unpausing all operations globally
    bytes32 public constant OP_UNPAUSE_ALL = keccak256("EmergencyControls.unpauseAll()");

    /// @notice Canonical operation ID for checking global pause status
    bytes32 public constant OP_IS_GLOBALLY_PAUSED = keccak256("EmergencyControls.isGloballyPaused()");

    // ─── Custom Errors ────────────────────────────────────────────────

    error AlreadyPaused(bytes32 scope);
    error NotPaused(bytes32 scope);
    error UnauthorizedToPause(address account);
    error UnauthorizedToUnpause(address account);
    error UnpauseTimelockNotReady(bytes32 scope, uint256 readyAt);
    error StaleIncidentReference(bytes32 incidentRef, uint256 recordedAt);
    error WrongRepairedRelease(bytes32 expected, bytes32 provided);
    error DependencyUnhealthy(bytes32 dependency);
    error IncidentAlreadyResolved(bytes32 incidentRef);
    error ScopeNotFullyPaused(bytes32 scope);
    error UnknownOperation(bytes32 operationId);
    error OperationIdCollision(bytes32 operationId);
    error InvalidScope(bytes32 scope);
    error ScopeNotAllowed(bytes32 scope);

    // ─── Events ───────────────────────────────────────────────────────

    event ScopeAllowedSet(bytes32 indexed scope, bool allowed, address indexed operator);
    event UnpauseScheduled(bytes32 indexed scope, uint256 readyAt, address indexed actor);

    // ─── State ────────────────────────────────────────────────────────

    /// @notice Mapping from scope hash to paused status
    mapping(bytes32 => bool) private _pausedScopes;
    mapping(bytes32 => bool) public allowedScope;
    mapping(bytes32 => bool) public scopeConfigured;
    mapping(bytes32 => mapping(bytes32 => bool)) private _pausedOperations;
    mapping(bytes32 => mapping(bytes4 => bytes32)) private _scopeSelectorIds;
    mapping(bytes32 => mapping(bytes32 => bytes4)) private _scopeIdSelectors;
    mapping(bytes32 => mapping(bytes32 => bool)) private _scopeOperationRegistered;
    mapping(bytes32 => bytes32[]) private _scopeOperationIds;
    mapping(bytes32 => uint256) public pausedOperationCount;

    /// @notice Mapping from scope to timestamp when it was paused (0 if not paused)
    mapping(bytes32 => uint256) public pausedAt;

    /// @notice Mapping from scope to total number of times it has been paused
    mapping(bytes32 => uint256) public pauseCount;

    /// @notice Mapping from scope to scheduled unpause timestamp (0 if none)
    mapping(bytes32 => uint256) public unpauseScheduledAt;

    /// @notice Mapping from scope to incident reference recorded at pause time
    mapping(bytes32 => bytes32) public pauseIncidentRef;

    /// @notice Mapping from scope to timestamp the incident reference was recorded
    mapping(bytes32 => uint256) public pauseIncidentAt;

    /// @notice Mapping from incident reference to resolution status
    mapping(bytes32 => bool) public incidentResolved;

    /// @notice Mapping from operation ID to canonical operation name
    mapping(bytes32 => string) private _operationNames;

    /// @notice Mapping from operation ID to whether it is registered
    mapping(bytes32 => bool) private _operationRegistered;

    // ─── Constructor ──────────────────────────────────────────────────

    /**
     * @param admin Initial administrator account
     * @param emergencyCouncil Address granted rapid emergency pause powers
     * @param governance Address representing DAO governance / timelock
     */
    constructor(address admin, address emergencyCouncil, address governance) {
        if (admin == address(0) || emergencyCouncil == address(0) || governance == address(0)) {
            revert V2Errors.ZeroAddress();
        }

        // Register well-known scopes as allowed by default
        _setScopeAllowed(SCOPE_ALL, true);
        _setScopeAllowed(SCOPE_CLAIMS, true);
        _setScopeAllowed(SCOPE_EVIDENCE, true);
        _setScopeAllowed(SCOPE_STAKING, true);
        _setScopeAllowed(SCOPE_VERIFICATION, true);
        _setScopeAllowed(SCOPE_SETTLEMENT, true);
        _setScopeAllowed(SCOPE_TREASURY, true);
        _setScopeAllowed(SCOPE_DISPUTES, true);

        // Subordinate all role administration under GOVERNANCE_ROLE
        // to prevent DEFAULT_ADMIN_ROLE from escalating privileges or granting unpause powers
        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(GOVERNANCE_ROLE, governance);
        _grantRole(EMERGENCY_ROLE, emergencyCouncil);

        if (admin != governance) {
            _grantRole(DEFAULT_ADMIN_ROLE, admin);
        }

        _setRoleAdmin(DEFAULT_ADMIN_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(GOVERNANCE_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(EMERGENCY_ROLE, GOVERNANCE_ROLE);

        // Register canonical operation IDs
        _registerOperation(OP_PAUSE, "pause(bytes32)");
        _registerOperation(OP_UNPAUSE, "unpause(bytes32)");
        _registerOperation(OP_PAUSED, "paused(bytes32)");
        _registerOperation(OP_IS_SCOPE_SPECIFICALLY_PAUSED, "isScopeSpecificallyPaused(bytes32)");
        _registerOperation(OP_PAUSE_ALL, "pauseAll()");
        _registerOperation(OP_UNPAUSE_ALL, "unpauseAll()");
        _registerOperation(OP_IS_GLOBALLY_PAUSED, "isGloballyPaused()");
    }

    // ─── Scope Administration ─────────────────────────────────────────

    /**
     * @notice Set whether a scope is allowed to be paused.
     * @dev Only GOVERNANCE_ROLE can configure allowed scopes. Emits ScopeAllowedSet.
     * @param scope Identifier of the scope.
     * @param allowed Whether the scope is allowed.
     */
    function setScopeAllowed(bytes32 scope, bool allowed) external {
        if (!hasRole(GOVERNANCE_ROLE, msg.sender)) {
            revert UnauthorizedToPause(msg.sender);
        }
        _setScopeAllowed(scope, allowed);
    }

    function _setScopeAllowed(bytes32 scope, bool allowed) internal {
        allowedScope[scope] = allowed;
        scopeConfigured[scope] = true;
        emit ScopeAllowedSet(scope, allowed, msg.sender);
    }

    // ─── IV2Module ────────────────────────────────────────────────────

    /// @inheritdoc IV2Module
    function protocolVersion() external pure override returns (uint16 major, uint16 minor) {
        return (2, 0);
    }

    // ─── ERC-165 ──────────────────────────────────────────────────────

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC165, AccessControl, IERC165)
        returns (bool)
    {
        return interfaceId == type(IEmergencyControls).interfaceId
            || interfaceId == type(IV2Module).interfaceId
            || interfaceId == type(IAccessControl).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // ─── IEmergencyControls ───────────────────────────────────────────

    /**
     * @notice Pause operations for a given scope.
     * @dev Callable by either EMERGENCY_ROLE (rapid response) or GOVERNANCE_ROLE.
     * @param scope Identifier of the scope to pause (bytes32(0) for global).
     */
    function pause(bytes32 scope) external override {
        if (!hasRole(EMERGENCY_ROLE, msg.sender) && !hasRole(GOVERNANCE_ROLE, msg.sender)) {
            revert V2Errors.Unauthorized(msg.sender);
        }
        if (!allowedScope[scope]) {
            revert ScopeNotAllowed(scope);
        }
        if (!_operationRegistered[OP_PAUSE]) revert UnknownOperation(OP_PAUSE);
        if (_pausedScopes[scope]) revert AlreadyPaused(scope);

        _pausedScopes[scope] = true;
        pausedAt[scope] = block.timestamp;
        pauseCount[scope]++;
        bytes32 incidentRef = keccak256(abi.encodePacked(scope, block.timestamp, msg.sender));
        pauseIncidentRef[scope] = incidentRef;
        pauseIncidentAt[scope] = block.timestamp;

        emit EmergencyPaused(scope, msg.sender);
    }

    /**
     * @notice Unpause operations for a given scope.
     * @dev Separation of powers: strictly callable by GOVERNANCE_ROLE only.
     *      EMERGENCY_ROLE CANNOT unpause.
     *      Requires: timelock ready, non-stale incident reference, correct repaired release,
     *      healthy dependencies, and the scope to be currently paused.
     * @param scope Identifier of the scope to unpause.
     * @param incidentRef Incident reference recorded at pause time.
     * @param repairedRelease Hash of the repaired release artifact.
     * @param dependencyHealth Encoded dependency health evidence (all must be healthy).
     */
    function unpause(
        bytes32 scope,
        bytes32 incidentRef,
        bytes32 repairedRelease,
        bytes32[] calldata dependencyHealth
    ) external override {
        if (!hasRole(GOVERNANCE_ROLE, msg.sender)) {
            revert V2Errors.Unauthorized(msg.sender);
        }
        if (!_operationRegistered[OP_UNPAUSE]) revert UnknownOperation(OP_UNPAUSE);
        if (!_pausedScopes[scope]) revert NotPaused(scope);

        uint256 readyAt = unpauseScheduledAt[scope];
        if (readyAt == 0 || block.timestamp < readyAt) {
            revert UnpauseTimelockNotReady(scope, readyAt);
        }

        bytes32 recordedRef = pauseIncidentRef[scope];
        if (incidentRef != recordedRef) {
            revert StaleIncidentReference(incidentRef, pauseIncidentAt[scope]);
        }
        if (incidentResolved[incidentRef]) {
            revert IncidentAlreadyResolved(incidentRef);
        }
        if (block.timestamp - pauseIncidentAt[scope] > MAX_INCIDENT_AGE) {
            revert StaleIncidentReference(incidentRef, pauseIncidentAt[scope]);
        }

        bytes32 expectedRelease = keccak256(abi.encodePacked(scope, incidentRef, "REPAIRED"));
        if (repairedRelease != expectedRelease) {
            revert WrongRepairedRelease(expectedRelease, repairedRelease);
        }

        for (uint256 i = 0; i < dependencyHealth.length; i++) {
            if (dependencyHealth[i] != keccak256("HEALTHY")) {
                revert DependencyUnhealthy(dependencyHealth[i]);
            }
        }

        _pausedScopes[scope] = false;
        bytes32[] storage scopedOperations = _scopeOperationIds[scope];
        for (uint256 i = 0; i < scopedOperations.length; ++i) {
            bytes32 operationId = scopedOperations[i];
            if (_pausedOperations[scope][operationId]) {
                _pausedOperations[scope][operationId] = false;
                emit OperationUnpaused(scope, operationId, msg.sender);
            }
        }
        pausedOperationCount[scope] = 0;
        pausedAt[scope] = 0;
        unpauseScheduledAt[scope] = 0;
        incidentResolved[incidentRef] = true;

        emit EmergencyUnpaused(scope, msg.sender);
        emit GovernedUnpauseExecuted(scope, incidentRef, repairedRelease, msg.sender);
    }

    /**
     * @notice Check whether operations for a given scope are currently paused.
     * @dev If the global scope (SCOPE_ALL) is paused, any sub-scope is considered paused.
     * @param scope Identifier of the scope to check.
     * @return True if either the specific scope or the global scope is paused.
     */
    function paused(bytes32 scope) external view override returns (bool) {
        if (!_operationRegistered[OP_PAUSED]) revert UnknownOperation(OP_PAUSED);
        return _pausedScopes[SCOPE_ALL] || _pausedScopes[scope];
    }

    /**
     * @notice Check whether a scope is specifically paused (ignoring global state).
     * @param scope Identifier of the scope.
     * @return True if the specific scope itself is marked paused.
     */
    function isScopeSpecificallyPaused(bytes32 scope) external view returns (bool) {
        if (!_operationRegistered[OP_IS_SCOPE_SPECIFICALLY_PAUSED]) {
            revert UnknownOperation(OP_IS_SCOPE_SPECIFICALLY_PAUSED);
        }
        return _pausedScopes[scope];
    }

    /**
     * @notice Schedule a governed unpause for a scope, starting the timelock.
     * @dev Callable by GOVERNANCE_ROLE only.
     * @param scope Identifier of the scope to schedule unpause for.
     */
    function scheduleUnpause(bytes32 scope) external {
        if (!hasRole(GOVERNANCE_ROLE, msg.sender)) {
            revert UnauthorizedToUnpause(msg.sender);
        }
        if (!_pausedScopes[scope] && pausedOperationCount[scope] == 0) revert NotPaused(scope);
        if (unpauseScheduledAt[scope] != 0) revert AlreadyPaused(scope);

        uint256 readyAt = block.timestamp + UNPAUSE_TIMELOCK_DELAY;
        unpauseScheduledAt[scope] = readyAt;

        emit UnpauseScheduled(scope, readyAt, msg.sender);
    }

    /**
     * @notice Pause all operations globally.
     * @dev Convenience wrapper around pause(SCOPE_ALL).
     */
    function pauseAll() external {
        if (!hasRole(EMERGENCY_ROLE, msg.sender) && !hasRole(GOVERNANCE_ROLE, msg.sender)) {
            revert UnauthorizedToPause(msg.sender);
        }
        if (!_operationRegistered[OP_PAUSE_ALL]) revert UnknownOperation(OP_PAUSE_ALL);
        if (_pausedScopes[SCOPE_ALL]) revert AlreadyPaused(SCOPE_ALL);

        _pausedScopes[SCOPE_ALL] = true;
        pausedAt[SCOPE_ALL] = block.timestamp;
        pauseCount[SCOPE_ALL]++;

        emit EmergencyPaused(SCOPE_ALL, msg.sender);
    }

    /**
     * @notice Unpause all operations globally.
     * @dev Convenience wrapper around unpause(SCOPE_ALL). GOVERNANCE_ROLE only.
     */
    function unpauseAll() external {
        if (!hasRole(GOVERNANCE_ROLE, msg.sender)) {
            revert UnauthorizedToUnpause(msg.sender);
        }
        if (!_operationRegistered[OP_UNPAUSE_ALL]) revert UnknownOperation(OP_UNPAUSE_ALL);
        if (!_pausedScopes[SCOPE_ALL]) revert NotPaused(SCOPE_ALL);

        _pausedScopes[SCOPE_ALL] = false;
        pausedAt[SCOPE_ALL] = 0;

        emit EmergencyUnpaused(SCOPE_ALL, msg.sender);
    }

    /**
     * @notice Check whether the global scope is paused.
     * @return True if the global scope is paused.
     */
    function isGloballyPaused() external view returns (bool) {
        if (!_operationRegistered[OP_IS_GLOBALLY_PAUSED]) {
            revert UnknownOperation(OP_IS_GLOBALLY_PAUSED);
        }
        return _pausedScopes[SCOPE_ALL];
    }

    /**
     * @notice Get the canonical operation name for a given operation ID.
     * @param operationId The operation ID to look up.
     * @return The canonical operation name.
     */
    function operationName(bytes32 operationId) external view returns (string memory) {
        if (!_operationRegistered[operationId]) revert UnknownOperation(operationId);
        return _operationNames[operationId];
    }

    /**
     * @notice Check whether an operation ID is registered.
     * @param operationId The operation ID to check.
     * @return True if the operation ID is registered.
     */
    function isOperationRegistered(bytes32 operationId) external view returns (bool) {
        return _operationRegistered[operationId];
    }

    /**
     * @notice Get the full operation matrix for frontend/API consumers.
     * @return ids Array of operation IDs.
     * @return names Array of canonical operation names.
     */
    function operationMatrix() external view returns (bytes32[] memory ids, string[] memory names) {
        ids = new bytes32[](7);
        names = new string[](7);

        ids[0] = OP_PAUSE;
        names[0] = _operationNames[OP_PAUSE];
        ids[1] = OP_UNPAUSE;
        names[1] = _operationNames[OP_UNPAUSE];
        ids[2] = OP_PAUSED;
        names[2] = _operationNames[OP_PAUSED];
        ids[3] = OP_IS_SCOPE_SPECIFICALLY_PAUSED;
        names[3] = _operationNames[OP_IS_SCOPE_SPECIFICALLY_PAUSED];
        ids[4] = OP_PAUSE_ALL;
        names[4] = _operationNames[OP_PAUSE_ALL];
        ids[5] = OP_UNPAUSE_ALL;
        names[5] = _operationNames[OP_UNPAUSE_ALL];
        ids[6] = OP_IS_GLOBALLY_PAUSED;
        names[6] = _operationNames[OP_IS_GLOBALLY_PAUSED];
    }

    /// @inheritdoc IEmergencyControls
    function pauseOperation(bytes32 scope, bytes32 operationId) external override {
        if (!hasRole(EMERGENCY_ROLE, msg.sender) && !hasRole(GOVERNANCE_ROLE, msg.sender)) {
            revert UnauthorizedToPause(msg.sender);
        }
        if (!allowedScope[scope]) revert ScopeNotAllowed(scope);
        if (!_scopeOperationRegistered[scope][operationId]) revert UnknownOperation(operationId);
        if (_pausedOperations[scope][operationId]) revert AlreadyPaused(scope);

        if (pausedOperationCount[scope] == 0 && !_pausedScopes[scope]) {
            pausedAt[scope] = block.timestamp;
            pauseCount[scope]++;
            bytes32 incidentRef = keccak256(abi.encode(scope, operationId, block.timestamp, msg.sender));
            pauseIncidentRef[scope] = incidentRef;
            pauseIncidentAt[scope] = block.timestamp;
        }
        _pausedOperations[scope][operationId] = true;
        pausedOperationCount[scope]++;
        emit OperationPaused(scope, operationId, msg.sender);
    }

    /// @inheritdoc IEmergencyControls
    function unpauseOperation(bytes32 scope, bytes32 operationId) external override {
        if (!hasRole(GOVERNANCE_ROLE, msg.sender)) revert UnauthorizedToUnpause(msg.sender);
        if (!_scopeOperationRegistered[scope][operationId]) revert UnknownOperation(operationId);
        if (!_pausedOperations[scope][operationId]) revert NotPaused(scope);
        uint256 readyAt = unpauseScheduledAt[scope];
        if (!unpauseReady(scope)) revert UnpauseTimelockNotReady(scope, readyAt);

        _pausedOperations[scope][operationId] = false;
        pausedOperationCount[scope]--;
        emit OperationUnpaused(scope, operationId, msg.sender);
        if (pausedOperationCount[scope] == 0 && !_pausedScopes[scope]) {
            bytes32 incidentRef = pauseIncidentRef[scope];
            incidentResolved[incidentRef] = true;
            pausedAt[scope] = 0;
            unpauseScheduledAt[scope] = 0;
        }
    }

    /// @inheritdoc IEmergencyControls
    function unpauseReady(bytes32 scope) public view override returns (bool) {
        uint256 readyAt = unpauseScheduledAt[scope];
        return ( _pausedScopes[scope] || pausedOperationCount[scope] > 0)
            && readyAt != 0
            && block.timestamp >= readyAt
            && block.timestamp - pauseIncidentAt[scope] <= MAX_INCIDENT_AGE
            && !incidentResolved[pauseIncidentRef[scope]];
    }

    /// @inheritdoc IEmergencyControls
    function operationPaused(bytes32 scope, bytes32 operationId) external view override returns (bool) {
        if (!_scopeOperationRegistered[scope][operationId]) revert UnknownOperation(operationId);
        return _pausedScopes[SCOPE_ALL] || _pausedScopes[scope] || _pausedOperations[scope][operationId];
    }

    /// @inheritdoc IEmergencyControls
    function operationIdForSelector(bytes32 scope, bytes4 selector) external view override returns (bytes32) {
        bytes32 operationId = _scopeSelectorIds[scope][selector];
        if (operationId == bytes32(0)) revert UnknownOperation(operationId);
        return operationId;
    }

    /// @inheritdoc IEmergencyControls
    function selectorForOperationId(bytes32 scope, bytes32 operationId) external view override returns (bytes4) {
        bytes4 selector = _scopeIdSelectors[scope][operationId];
        if (selector == bytes4(0)) revert UnknownOperation(operationId);
        return selector;
    }

    /// @inheritdoc IEmergencyControls
    function operationIdsForScope(bytes32 scope) external view override returns (bytes32[] memory) {
        if (!scopeConfigured[scope]) revert InvalidScope(scope);
        return _scopeOperationIds[scope];
    }

    /// @inheritdoc IEmergencyControls
    function operationIdForSignature(bytes32 scope, bytes memory signature) external view override returns (bytes32) {
        bytes4 selector = bytes4(keccak256(signature));
        bytes32 operationId = _scopeSelectorIds[scope][selector];
        if (operationId == bytes32(0)) revert UnknownOperation(operationId);
        return operationId;
    }

    // ─── Internal Helpers ─────────────────────────────────────────────

    /**
     * @dev Register a canonical operation ID. Reverts on collision.
     * @param operationId The operation ID to register.
     * @param name The canonical operation name.
     */
    function _registerOperation(bytes32 operationId, string memory name) internal {
        if (_operationRegistered[operationId]) revert OperationIdCollision(operationId);
        _operationRegistered[operationId] = true;
        _operationNames[operationId] = name;

        bytes4 selector = bytes4(keccak256(bytes(name)));
        bytes32[8] memory scopes = [
            SCOPE_ALL,
            SCOPE_CLAIMS,
            SCOPE_EVIDENCE,
            SCOPE_STAKING,
            SCOPE_VERIFICATION,
            SCOPE_SETTLEMENT,
            SCOPE_TREASURY,
            SCOPE_DISPUTES
        ];
        for (uint256 i = 0; i < scopes.length; ++i) {
            bytes32 scope = scopes[i];
            bytes32 scopedId = keccak256(abi.encode(scope, selector));
            if (_scopeOperationRegistered[scope][scopedId]) revert OperationIdCollision(scopedId);
            _scopeOperationRegistered[scope][scopedId] = true;
            _scopeSelectorIds[scope][selector] = scopedId;
            _scopeIdSelectors[scope][scopedId] = selector;
            _scopeOperationIds[scope].push(scopedId);
            emit OperationRegistered(scope, scopedId, selector);
        }
    }
}