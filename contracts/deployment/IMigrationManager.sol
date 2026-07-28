// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMigrationManager {
    struct Migration {
        uint256 id;
        string description;
        uint256 timestamp;
        address executor;
        bool executed;
        bytes32 migrationHash;
    }

    function createRelease(string calldata version, bytes32 gitCommit) external;
    function registerModuleInRegistry(bytes32 moduleId, address moduleAddress) external;
    function updateModuleAddress(bytes32 moduleId, address newAddress) external;
    function executeMigration(string calldata description, bytes32 migrationHash) external;
    function verifyDeployment(bool ownershipTransferred, bool allModulesInitialized) external;

    function getModuleAddress(bytes32 moduleId) external view returns (address);
    function getRegisteredModuleCount() external view returns (uint256);
    function getRegisteredModuleAt(uint256 index) external view returns (bytes32 moduleId, address moduleAddress);
    function getAllRegisteredModules() external view returns (bytes32[] memory ids, address[] memory addresses);
    function getMigrationCount() external view returns (uint256);
    function getMigrationAt(uint256 index) external view returns (Migration memory);
    function getAllMigrations() external view returns (Migration[] memory);
    function isModuleRegistered(bytes32 moduleId) external view returns (bool);
    function isDeploymentVerified() external view returns (bool);

    event ReleaseCreated(string indexed version, bytes32 indexed gitCommit, address indexed deployedBy);
    event ModuleRegisteredInRegistry(bytes32 indexed moduleId, address indexed moduleAddress);
    event MigrationExecuted(uint256 indexed migrationId, string description, address indexed executor);
    event DeploymentVerified(bool ownershipTransferred, bool allModulesInitialized);
}