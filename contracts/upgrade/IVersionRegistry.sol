// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IVersionRegistry
 * @notice Interface for the canonical protocol version registry
 */
interface IVersionRegistry {
    enum VersionStatus {
        ACTIVE,
        DEPRECATED,
        ROLLED_BACK
    }

    struct VersionEntry {
        string contractName;
        address implementation;
        address proxy;
        string semanticVersion;
        uint256 deployedAt;
        bytes32 governanceProposalId;
        bytes32 upgradeHash;
        VersionStatus status;
    }

    event VersionRegistered(
        string indexed contractName,
        string indexed semanticVersion,
        address implementation
    );

    event VersionStatusUpdated(
        string indexed contractName,
        string indexed semanticVersion,
        VersionStatus newStatus
    );

    function registerVersion(
        string calldata contractName,
        address implementation,
        address proxy,
        string calldata semanticVersion,
        bytes32 governanceProposalId,
        bytes32 upgradeHash
    ) external returns (uint256 index);

    function updateVersionStatus(
        string calldata contractName,
        string calldata semanticVersion,
        VersionStatus newStatus
    ) external;

    function getLatestVersion(string calldata contractName) external view returns (VersionEntry memory);
    function getVersion(string calldata contractName, string calldata semanticVersion) external view returns (VersionEntry memory);
    function getVersionAtIndex(string calldata contractName, uint256 index) external view returns (VersionEntry memory);
    function getVersionCount(string calldata contractName) external view returns (uint256);
    function getActiveVersion(string calldata contractName) external view returns (VersionEntry memory);
    function isVersionActive(string calldata contractName, string calldata semanticVersion) external view returns (bool);
}
