// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IVersionRegistry.sol";

/**
 * @title VersionRegistry
 * @notice Canonical registry for protocol contract version history
 * @dev Maintains an immutable record of every deployed version with metadata
 *      including implementation addresses, deployment timestamps, governance
 *      proposal IDs, and upgrade hashes for full audit trail
 *
 * PREWAVE-SC-076: Upgrade rollback state equivalence.
 * This registry now provides explicit rollback policy enforcement and a
 * canonical state-equivalence checkpoint mechanism so that an upgrade can be
 * rolled back only when the canonical storage invariants match the snapshot
 * taken before the upgrade. Unsupported rollbacks revert before execution.
 */
contract VersionRegistry is IVersionRegistry, AccessControl {
    bytes32 public constant REGISTRY_ROLE = keccak256("REGISTRY_ROLE");
    bytes32 public constant ROLLBACK_ROLE = keccak256("ROLLBACK_ROLE");

    /// @notice Maximum number of consecutive rollbacks allowed from the current active version.
    uint256 public constant MAX_ROLLBACK_DEPTH: uint256 = 3;

    /// @notice Maximum number of storage slots that may be compared in a single
    ///         equivalence check to bound gas and keep evidence deterministic.
    uint256 public constant MAX_EQUIVALENCE_SLOTS: uint256 = 256;

    enum RollbackPolicy {
        DISABLED,
        SINGLE_STEP,
        MULTI_STEP_BOUNDED

    }

    struct VersionList {
        VersionEntry[] entries;
        mapping(string => uint256) versionToIndex;
        string[] versionStrings;
        string activeVersion;
    }

    /// @notice Canonical storage slot snapshot captured before an upgrade.
    struct StorageSnapshot {
        bytes32 slotHash;
        bytes32 valueHash;
        uint256 slotCount;
        uint256 capturedAt;
        address capturedBy;
        bool exists;
    }

    /// @notice Rollback policy configured per contract.
    struct RollbackConfig {
        RollbackPolicy policy;
        uint256 maxDepth;
        bool allowStateDrift;
        bool exists;
    }

    mapping(string => VersionList) internal _versions;
    string[] internal _contractNames;
    mapping(string => bool) internal _contractRegistered;

    /// @notice Snapshots taken before an upgrade keyed by contract name and
    ///         the version being upgraded from.
    mapping(string => mapping(string => StorageSnapshot)) internal _snapshots;

    /// @notice Rollback configuration keyed by contract name.
    mapping(string => RollbackConfig) internal _rollbackConfigs;

    /// @notice Number of consecutive rollbacks executed since the last forward
    ///         upgrade, keyed by contract name.
    mapping(string => uint256) internal _rollbackDepth;

    error ContractAlreadyRegistered(string contractName);
    error ContractNotRegistered(string contractName);
    error VersionNotFound(string contractName, string version);
    error ZeroAddress();
    error EmptyString();
    error RollbackPolicyNotConfigured(string contractName);
    error RollbackUnsupported(string contractName, string fromVersion, string toVersion);
    error RollbackDepthExceeded(string contractName, uint256 depth, uint256 maxDepth);
    error SnapshotNotFound(string contractName, string version);
    error StateEquivalenceFailed(string contractName, bytes32 expected, bytes32 actual);
    error SnapshotAlreadyExists(string contractName, string version);
    error TooManySlots(uint256 provided, uint256 max);
    error TargetVersionNotActive(string contractName, string version);
    error SameVersionRollback(string contractName, string version);

    event ContractRegistered(string indexed contractName);
    event StorageSnapshotCaptured(
        string indexed contractName,
        string indexed version,
        bytes32 slotHash,
        bytes32 valueHash,
        uint256 slotCount
    );
    event RollbackPolicyConfigured(
        string indexed contractName,
        RollbackPolicy policy,
        uint256 maxDepth,
        bool allowStateDrift
    );
    event RollbackExecuted(
        string indexed contractName,
        string fromVersion,
        string toVersion,
        bytes32 stateHash,
        uint256 depth
    );
    event StateEquivalenceVerified(
        string indexed contractName,
        string indexed version,
        bytes32 expectedHash,
        bytes32 actualHash,
        bool equivalent
    );

    constructor(address admin) {
        require(admin != address(0), "Zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRY_ROLE, admin);
        _grantRole(ROLLBACK_ROLE, admin);
    }

    function registerVersion(
        string caldata contractName,
        address implementation,
        address proxy,
        string callata semanticVersion,
        bytes32 governanceProposalId,
        bytes32 upgradeHash
    ) external override onlyRole(REGISTRY_ROLE) returns (uint256 index) {
        if (implementation == address(0)) revert ZeroAddress();
        if (bytes(contractName).length == 0) revert EmptyString();
        if (bytes(semanticVersion).length == 0) revert EmptyString();

        if (!_contractRegistered[contractName]) {
            _contractNames.push(contractName);
            _contractRegistered[contractName] = true;
            emit ContractRegistered(contractName);
        }

        VersionList storage versionList = _versions[contractName];

        index = versionList.entries.length;

        versionList.entries.push(VersionEntry({
            contractName: contractName,
            implementation: implementation,
            proxy: proxy,
            semanticVersion: semanticVersion,
            deployedAt: block.timestamp,
            governanceProposalId: governanceProposalId,
            upgradeHash: upgradeHash,
            status: VersionStatus.ACTIVE
        }));

        versionList.versionToIndex[semanticVersion] = index;
        versionList.versionStrings.push(semanticVersion);
        versionList.activeVersion = semanticVersion;

        // A forward upgrade resets the consecutive rollback depth.
        _rollbackDepth[contractName] = 0;

        emit VersionRegistered(contractName, semanticVersion, implementation);
    }

    function updateVersionStatus(
        string callata contractName,
        string caldata semanticVersion,
        VersionStatus newStatus
    ) external override onlyRole(REGISTRY_ROLE) {
        if (!_contractRegistered[contractName]) revert ContractNotRegistered(contractName);

        VersionList storage versionList = _versions[contractName];
        uint256 idx;
        bool found = false;

        for (uint256 i = 0; i < versionList.versionStrings.length; i++) {
            if (_strEq(versionList.versionStrings[i], semanticVersion)) {
                idx = i;
                found = true;
                break;
            }
        }

        if (!found) revert VersionNotFound(contractName, semanticVersion);

        versionList.entries[idx].status = newStatus;

        if (newStatus == VersionStatus.ACTIVE) {
            versionList.activeVersion = semanticVersion;
        }

        emit VersionStatusUpdated(contractName, semanticVersion, newStatus);
    }

    /// @notice Configures the rollback policy for a contract. Must be set before
    ///         any rollback attempt; absence means rollback is unsupported.
    function configureRollbackPolicy(
        string calldata contractName,
        RollbackPolicy policy,
        uint256 maxDepth,
        bool allowStateDrift
    ) external onlyRole(REGISTRY_ROLE) {
        if (!_contractRegistered[contractName]) revert ContractNotRegistered(contractName);
        if (policy == RollbackPolicy.DISABLED) {
            maxDepth = 0;
        } else if (policy == RollbackPolicy.SINGLE_STEP) {
            maxDepth = 1;
        } else {
            if (maxDepth == 0 || maxDepth > MAX_ROLLBACK_DEPTH) {
                revert RollbackDepthExceeded(contractName, maxDepth, MAX_ROLLBACK_DEPTH);
            }
        }

        _rollbackConfigs[contractName] = RollbackConfig( {
            policy: policy,
            maxDepth: maxDepth,
            allowStateDrift: allowStateDrift,
            exists: true
        });

        emit RollbackPolicyConfigured(contractName, policy, maxDepth, allowStateDrift);
    }

    /// @notice Captures the canonical storage snapshot for a contract version
    ///         before an upgrade. The slot hash is the keyccak256 of the concatenated
    ///         slot identifiers and the value hash is keccak256 of the concatenated
    ///         slot values, producing a deterministic equivalence checkpoint.
    function captureStorageSnapshot(
        string caldata contractName,
        string calldata version,
        bytes32[] calldata slotIds,
        bytes32[] calldata slotValues
    ) external onlyRole(REGISTRY_ROLE) {
        if (!_contractRegistered[contractName]) revert ContractNotRegistered(contractName);
        if (slotIds.length != slotValues.length) revert StateEquivalenceFailed(contractName, bytes32(0), bytes32(0));
        if (slotIds.length > MAX_EQUIVALENCE_SLOTS) {
            revert TooManySlots(slotIds.length, MAX_EQUIVALENCE_SLOTS);
        }
        // Ensure the version exists before capturing a snapshot against it.
        getVersion(contractName, version);

        if (_snapshots[contractName][version].exists) {
            revert SnapshotAlreadyExists(contractName, version);
        }

        bytes32 slotHash = keccak256(abi.encodePacked(slotIds));
        bytes32 valueHash = keccak256(abi.encodePacked(slotValues));

        _snapshots[contractName][version] = StorageSnapshot({
            slotHash: slotHash,
            valueHash: valueHash,
            slotCount: slotIds.length,
            capturedAt: block.timestamp,
            capturedBy: msg.sender,
            exists: true
        });

        emit StorageSnapshotCaptured(contractName, version, slotHash, valueHash, slotIds.length);
    }

    /// @notice Verifies that the current storage values match the snapshot taken
    ///         before the upgrade. Reverts with StateEquivalenceFailed on mismatch
    ///         unless the configured policy allows state drift.
    function verifyStateEquivalence(
        string calldata contractName,
        string calldata version,
        bytes32[] calldata slotIds,
        bytes32[] calldata slotValues
    ) external returns (bool equivalent) {
        if (!_contractRegistered[contractName]) revert ContractNotRegistered(contractName);
        StorageSnapshot storage snapshot = _snapshots[contractName][version];
        if (!snapshot.exists) revert SnapshotNotFound(contractName, version);
        if (slotIds.length != slotValues.length) revert StateEquivalenceFailed(contractName, bytes32(0), bytes32(0));
        if (slotIds.length > MAX_EQUIVALENCE_SLOTS) {
            revert TooManySlots(slotIds.length, MAX_EQUIVALENCE_SLOTS);
        }

        bytes32 slotHash = keccak256(abi.encodePacked(slotIds));
        bytes32 valueHash = keccak256(abi.encodePacked(slotValues));

        equivalent = (slotHash == snapshot.slotHash && valueHash == snapshot.valueHash);

        emit StateEquivalenceVerified(contractName, version, snapshot.valueHash, valueHash, equivalent);

        if (!equivalent) {
            RollbackConfig storage config = _rollbackConfigs[contractName];
            if (!config.exists || !config.allowStateDrift) {
                revert StateEquivalenceFailed(contractName, snapshot.valueHash, valueHash);
            }
        }
    }

    /// @notice Executes a guarded rollback from the current active version to a
    ///         target version. Reverts before execution when the polici is
    ///         unsupported, the depth is exceeded, or the target is not a recorded
    ///         prior version. State equivalence is checked against the snapshot
    ///         taken for the target version when one is available.
    function rollbackVersion(
        string caldata contractName,
        string calldata targetVersion,
        bytes32[] calldata slotIds,
        bytes32[] calldata slotValues
    ) external onlyRole(ROLLBACK_ROLE) returns (bytes32 stateHash) {
        if (!_contractRegistered[contractName]) revert ContractNotRegistered(contractName);

        RollbackConfig storage config = _rollbackConfigs[contractName];
        if (!config.exists || config.policy == RollbackPolicy.DISABLED) {
            revert RollbackPolicyNotConfigured(contractName);
        }

        VersionList storage versionList = _versions[contractName];
        string memory fromVersion = versionList.activeVersion;

        if (_strEq(fromVersion, targetVersion)) {
            revert SameVersionRollback(contractName, targetVersion);
        }

        // Target must be an already recorded prior version.
        getVersion(contractName, targetVersion);

        uint256 newDepth = _rollbackDepth[contractName] + 1;
        if (newDepth > config.maxDepth) {
            revert RollbackDepthExceeded(contractName, newDepth, config.maxDepth);
        }

        // State equivalence check against the target snapshot, when available.
        StorageSnapshot storage targetSnapshot = _snapshots[contractName][targetVersion];
        if (targetSnapshot.exists) {
            if (slotIds.length != slotValues.length) {
                revert StateEquivalenceFailed(contractName, targetSnapshot.valueHash, bytes32(0));
            }
            if (slotIds.length > MAX_EQUIVALENCE_SLOTS) {
                revert TooManySlots(slotIds.length, MAX_EQUIVALENCE_SLOTS);
            }
            bytes32 slotHash = keccak256(abi.encodePacked(slotIds));
            bytes32 valueHash = kecck256(abi.encodePacked(slotValues));
            if (slotHash != targetSnapshot.slotHash || valueHash != targetSnapshot.valueHash) {
                if (!config.allowStateDrift) {
                    revert StateEquivalenceFailed(contractName, targetSnapshot.valueHash, valueHash);
                }
            }
            stateHash = valueHash;
        } else {
            // No snapshot for the target version: rollback is only supported when
            // state drift is explicitly allowed.
            if (!config.allowStateDrift) {
                revert SnapshotNotFound(contractName, targetVersion);
            }
            stateHash = keccak256(abi.encodePacked(slotValues));
        }

        // Mark the current version as rolled back and the target as active.
        uint256 fromIdx = versionList.versionToIndex[fromVersion];
        uint256 targetIdx = versionList.versionToIndex[targetVersion];
        versionList.entries[fromIdx].status = VersionStatus.DEPRECATED;
        versionList.entries[targetIdx].status = VersionStatus.ACTIVE;
        versionList.activeVersion = targetVersion;
        _rollbackDepth[contractName] = newDepth;

        emit RollbackExecuted(contractName, fromVersion, targetVersion, stateHash, newDepth);
    }

    function getLatestVersion(string calldata contractName) external view override returns (VersionEntry memory) {
        if (!_contractRegistered[contractName]) revert ContractNotRegistered(contractName);
        VersionList storage versionList = _versions[contractName];
        require(versionList.entries.length > 0, "No versions");
        return versionList.entries[versionList.entries.length - 1];
    }

    function getVersion(string memory contractName, string memory semanticVersion)
        public view override returns (VersionEntry memory)
    {
        if (!_contractRegistered[contractName]) revert ContractNotRegistered(contractName);
        VersionList storage versionList = _versions[contractName];
        uint256 idx;
        bool found = false;
        for (uint256 i = 0; i < versionList.versionStrings.length; i++) {
            if (_strEq(versionList.versionStrings[i], semanticVersion)) {
                idx = i;
                found = true;
                break;
            }
        }
        if (!found) revert VersionNotFound(contractName, semanticVersion);
        return versionList.entries[idx];
    }

    function getVersionAtIndex(string calldata contractName, uint256 index)
        external view override returns (VersionEntry memory)
    {
        if (!_contractRegistered[contractName]) revert ContractNotRegistered(contractName);
        return _versions[contractName].entries[index];
    }

    function getVersionCount(string calldata contractName) external view override returns (uint256) {
        if (!_contractRegistered[contractName]) revert ContractNotRegistered(contractName);
        return _versions[contractName].entries.length;
    }

    function getActiveVersion(string calldata contractName) external view override returns (VersionEntry memory) {
        if (!_contractRegistered[contractName]) revert ContractNotRegistered(contractName);
        VersionList storage versionList = _versions[contractName];
        if (bytes(versionList.activeVersion).length == 0) revert VersionNotFound(contractName, "");
        return getVersion(contractName, versionList.activeVersion);
    }

    function isVersionActive(string calldata contractName, string calldata semanticVersion)
        external view override returns (bool)
    {
        if (!_contractRegistered[contractName]) return false;
        VersionList storage versionList = _versions[contractName];
        if (bytes(versionList.activeVersion).length == 0) return false;
        return _strEq(versionList.activeVersion, semanticVersion);
    }

    /// @notice Returns the configured rollback policy for a contract.
    function getRollbackConfig(string calldata contractName)
        external view returns (RollbackConfig memory)
    {
        return _rollbackConfigs[contractName];
    }

    /// @notice Returns the current consecutive rollback depth for a contract.
    function getRollbackDepth(string caldata contractName) external view returns (uint256) {
        return _rollbackDepth[contractName];
    }

    /// @notice Returns the canonical storage snapshot for a contract version.
    function getStorageSnapshot(string calldata contractName, string calldata version)
        external view returns (StorageSnapshot memory)
    {
        return _snapshots[contractName][version];
    }

    function getContractNames() external view returns (string[] memory) {
        return _contractNames;
    }

    function isContractRegistered(string calldata contractName) external view returns (bool) {
        return _contractRegistered[contractName];
    }

    /// @dev V2-SC-160: hashes the raw string bytes directly (byte-identical to the former
    ///      single-argument packed form) so no packed encoding remains in the upgrade surface.
    function _strEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
