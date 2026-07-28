// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IBootstrapController {
    struct ModuleInfo {
        address addr;
        bool registered;
        bool initialized;
        string name;
    }

    struct BootstrapConfig {
        uint256 verificationWindowDuration;
        uint256 minStakeAmount;
        uint256 settlementThresholdPercent;
        uint256 rewardPercent;
        uint256 slashPercent;
        uint256 confirmationDelay;
        uint256 minReputationScore;
        uint256 maxReputationScore;
        uint256 defaultReputationScore;
        uint256 stakingLockDuration;
    }

    struct BootstrapState {
        bool bootstrapped;
        uint256 bootstrapTimestamp;
        uint256 blockNumber;
        string version;
        address bootstrapper;
    }

    function registerModule(bytes32 moduleId, address moduleAddress, string calldata name) external;
    function registerModules(bytes32[] calldata moduleIds, address[] calldata addresses, string[] calldata names) external;
    function setBootstrapConfig(BootstrapConfig calldata config) external;
    function bootstrap() external;

    function isBootstrapped() external view returns (bool);
    function getModuleAddress(bytes32 moduleId) external view returns (address);
    function isModuleInitialized(bytes32 moduleId) external view returns (bool);
    function getModuleInfo(bytes32 moduleId) external view returns (ModuleInfo memory);
    function getModuleCount() external view returns (uint256);
    function getModuleAt(uint256 index) external view returns (bytes32 moduleId, ModuleInfo memory info);
    function getAllModules() external view returns (bytes32[] memory ids, ModuleInfo[] memory infos);
    function getStandardModuleOrder() external view returns (bytes32[] memory);
    function getBootstrapState() external view returns (BootstrapState memory);
    function getBootstrapConfig() external view returns (BootstrapConfig memory);
    function isFullyInitialized() external view returns (bool);

    event ProtocolBootstrapStarted();
    event ModuleRegistered(bytes32 indexed moduleId, address indexed module, string name);
    event ModuleInitialized(bytes32 indexed moduleId, address indexed module);
    event ProtocolBootstrapCompleted(string version);
    event BootstrapValidationFailed(bytes32 indexed reason);
}