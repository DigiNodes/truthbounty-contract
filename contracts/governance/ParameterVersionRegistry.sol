// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./GovernanceOwnable.sol";
import "../interfaces/IParameterVersionRegistry.sol";

/**
 * @title ParameterVersionRegistry
 * @notice Registry for versioned economic parameter updates with timelock activation
 * @dev Implements atomic version activation, timelock enforcement, and non-retroactivity
 *      for all protocol economic parameters. Ensures existing claims continue using
 *      their frozen version while new claims use the current active version.
 */
contract ParameterVersionRegistry is 
    IParameterVersionRegistry,
    AccessControl,
    ReentrancyGuard,
    GovernanceOwnable
{
    // ============ Roles ============
    
    bytes32 public constant VERSION_PROPOSER_ROLE = keccak256("VERSION_PROPOSER_ROLE");
    bytes32 public constant VERSION_EXECUTOR_ROLE = keccak256("VERSION_EXECUTOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    // ============ Errors ============
    error InvalidAllocationBPS(uint256 sum);
    error InvalidEmissionLimit();
    error InvalidRewardMultiplier();
    error InvalidFee();
    error InvalidBPS();
    error InvalidStakeAmount();
    error InvalidReputationRange();
    error InvalidSlashBPS();

    // ============ Constants ============
    
    /// @notice Minimum timelock required for any parameter version activation (cannot be shortened)
    uint256 public constant MIN_ECONOMIC_PARAMETER_TIMELOCK = 2 days;
    
    /// @notice Maximum timelock allowed
    uint256 public constant MAX_ECONOMIC_PARAMETER_TIMELOCK = 30 days;
    
    /// @notice Basis points denominator for validation
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ============ State Variables ============
    
    /// @notice Current timelock for parameter version activation (never below MIN_ECONOMIC_PARAMETER_TIMELOCK)
    uint256 public parameterTimelock = MIN_ECONOMIC_PARAMETER_TIMELOCK;
    
    /// @notice Counter for version IDs
    uint256 public versionCounter;
    
    /// @notice ID of the currently active version
    uint256 public currentActiveVersionId;
    
    /// @notice ID of the next scheduled version (queued for activation)
    uint256 public scheduledVersionId;
    
    /// @notice All versions mapped by ID
    mapping(uint256 => ParameterVersion) private _versions;
    
    /// @notice Version ID that was active when a claim was created (claimId => versionId)
    mapping(uint256 => uint256) private _claimVersionMap;
    
    /// @notice Whether a version has been superseded
    mapping(uint256 => bool) private _versionSuperseded;

    // ============ Modifiers ============
    
    modifier onlyVersionExecutor() {
        if (!hasRole(VERSION_EXECUTOR_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, VERSION_EXECUTOR_ROLE);
        }
        _;
    }
    
    modifier onlyVersionProposer() {
        if (!hasRole(VERSION_PROPOSER_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, VERSION_PROPOSER_ROLE);
        }
        _;
    }

    // ============ Constructor ============
    
    constructor(address initialAdmin, address governanceController) {
        if (initialAdmin == address(0)) revert ZeroAddress();
        if (governanceController == address(0)) revert ZeroAddress();
        
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(VERSION_PROPOSER_ROLE, initialAdmin);
        _grantRole(VERSION_EXECUTOR_ROLE, initialAdmin);
        _grantRole(GUARDIAN_ROLE, initialAdmin);
        
        _setRoleAdmin(VERSION_PROPOSER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(VERSION_EXECUTOR_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(GUARDIAN_ROLE, DEFAULT_ADMIN_ROLE);
        
        _initializeGovernance(governanceController, initialAdmin, initialAdmin);
        
        // Create genesis version with all default values
        _createGenesisVersion();
    }

    // ============ Internal Initialization ============
    
    function _createGenesisVersion() internal {
        versionCounter = 1;
        
        // Initialize genesis parameters with default values
        EconomicParameters storage genesisParams = _versions[versionCounter].parameters;
        
        // Default tokenomics parameters
        genesisParams.verifierRewardsBPS = 4000;
        genesisParams.treasuryReserveBPS = 2000;
        genesisParams.ecosystemIncentivesBPS = 1500;
        genesisParams.governanceIncentivesBPS = 1000;
        genesisParams.protocolDevelopmentBPS = 1000;
        genesisParams.emergencyReserveBPS = 500;
        genesisParams.emissionLimit = type(uint256).max;
        genesisParams.rewardMultiplier = 1e18;
        genesisParams.treasuryReserveTargetBPS = 2000;
        
        // Default fee parameters
        genesisParams.claimSubmissionFee = 0.001e18;
        genesisParams.verificationSubmissionFee = 0.001e18;
        genesisParams.disputeInitiationFee = 0.002e18;
        genesisParams.protocolReserveFeeBPS = 50; // 0.5%
        
        // Default staking/reputation parameters
        genesisParams.minStakeAmount = 1e18;
        genesisParams.minReputationScore = 0;
        genesisParams.maxReputationScore = 10000;
        genesisParams.defaultReputationScore = 5000;
        genesisParams.slashPercentageBPS = 1000; // 10%
        genesisParams.maxSlashPercentageBPS = 5000; // 50%
        
        // Set genesis version as active
        _versions[versionCounter].status = VersionStatus.ACTIVE;
        _versions[versionCounter].proposedAt = block.timestamp;
        _versions[versionCounter].activatedAt = block.timestamp;
        _versions[versionCounter].versionId = versionCounter;
        
        currentActiveVersionId = versionCounter;
        
        emit VersionProposed(versionCounter, msg.sender, block.timestamp, 0);
        emit VersionActivated(versionCounter, block.timestamp);
    }

    function _validateParameterBounds(EconomicParameters calldata parameters) internal pure {
        // Allocation basis points must total exactly 10,000 (100%)
        uint256 allocationSum = parameters.verifierRewardsBPS
            + parameters.treasuryReserveBPS
            + parameters.ecosystemIncentivesBPS
            + parameters.governanceIncentivesBPS
            + parameters.protocolDevelopmentBPS
            + parameters.emergencyReserveBPS;
        if (allocationSum != BPS_DENOMINATOR) revert InvalidAllocationBPS(allocationSum);

        // Validate emission limit and reward multiplier are non-zero
        if (parameters.emissionLimit == 0) revert InvalidEmissionLimit();
        if (parameters.rewardMultiplier == 0) revert InvalidRewardMultiplier();

        // Validate fee parameters
        if (parameters.claimSubmissionFee == 0) revert InvalidFee();
        if (parameters.verificationSubmissionFee == 0) revert InvalidFee();
        if (parameters.disputeInitiationFee == 0) revert InvalidFee();
        if (parameters.protocolReserveFeeBPS > BPS_DENOMINATOR) revert InvalidBPS();

        // Validate staking bounds
        if (parameters.minStakeAmount == 0) revert InvalidStakeAmount();

        // Validate reputation bounds
        if (parameters.minReputationScore > parameters.maxReputationScore) revert InvalidReputationRange();
        if (parameters.defaultReputationScore < parameters.minReputationScore
            || parameters.defaultReputationScore > parameters.maxReputationScore) revert InvalidReputationRange();

        // Validate slashing bounds
        if (parameters.slashPercentageBPS > parameters.maxSlashPercentageBPS) revert InvalidSlashBPS();
        if (parameters.maxSlashPercentageBPS > BPS_DENOMINATOR) revert InvalidBPS();

        // Validate treasury reserve target
        if (parameters.treasuryReserveTargetBPS > BPS_DENOMINATOR) revert InvalidBPS();
    }

    // ============ External Functions ============
    
    /**
     * @notice Propose a new parameter version
     * @param parameters The complete set of economic parameters for this version
     * @return versionId The ID of the newly proposed version
     */
    function proposeNewVersion(EconomicParameters calldata parameters) 
        external 
        nonReentrant 
        onlyVersionProposer 
        returns (uint256 versionId) 
    {
        // Validate all parameter bounds
        _validateParameterBounds(parameters);
        
        versionCounter++;
        versionId = versionCounter;
        
        uint256 executeAfter = block.timestamp + parameterTimelock;
        
        // Store the new version
        _versions[versionId].versionId = versionId;
        _versions[versionId].parameters = parameters;
        _versions[versionId].status = VersionStatus.PROPOSED;
        _versions[versionId].proposedAt = block.timestamp;
        _versions[versionId].executeAfter = executeAfter;
        _versions[versionId].proposer = msg.sender;
        
        // If there's no scheduled version, queue this one
        if (scheduledVersionId == 0) {
            scheduledVersionId = versionId;
            _versions[versionId].status = VersionStatus.QUEUED;
            emit VersionQueued(versionId, executeAfter);
        }
        
        emit VersionProposed(versionId, msg.sender, block.timestamp, executeAfter);
        
        return versionId;
    }
    
    /**
     * @notice Activate a queued version after timelock has passed
     * @param versionId The ID of the version to activate
     */
    function activateVersion(uint256 versionId) 
        external 
        nonReentrant 
        onlyVersionExecutor 
    {
        ParameterVersion storage version = _versions[versionId];
        
        if (version.versionId == 0) revert VersionNotFound(versionId);
        if (version.status != VersionStatus.QUEUED) revert VersionNotQueued(versionId);
        if (block.timestamp < version.executeAfter) revert TimelockNotExpired(version.executeAfter);
        if (versionId != scheduledVersionId) revert NotScheduledVersion(versionId);
        
        // Mark previous active version as superseded
        if (currentActiveVersionId != 0) {
            _versionSuperseded[currentActiveVersionId] = true;
            emit VersionSuperseded(currentActiveVersionId, versionId);
        }
        
        // Activate the new version
        version.status = VersionStatus.ACTIVE;
        version.activatedAt = block.timestamp;
        currentActiveVersionId = versionId;
        scheduledVersionId = 0;
        
        emit VersionActivated(versionId, block.timestamp);
    }
    
    /**
     * @notice Record that a new claim was created, linking it to the current active version
     * @param claimId The ID of the newly created claim
     */
    function recordClaimCreation(uint256 claimId) external nonReentrant {
        if (claimId == 0) revert InvalidClaimId();
        if (_claimVersionMap[claimId] != 0) revert ClaimAlreadyRegistered(claimId);
        
        // Link this claim to the currently active version
        _claimVersionMap[claimId] = currentActiveVersionId;
        
        emit ClaimLinkedToVersion(claimId, currentActiveVersionId);
    }
    
    /**
     * @notice Update the parameter timelock (can only increase, never decrease below minimum)
     * @param newTimelock The new timelock duration
     */
    function updateParameterTimelock(uint256 newTimelock) external nonReentrant onlyGovernanceOrAdmin {
        if (newTimelock < MIN_ECONOMIC_PARAMETER_TIMELOCK) revert TimelockTooShort(newTimelock, MIN_ECONOMIC_PARAMETER_TIMELOCK);
        if (newTimelock > MAX_ECONOMIC_PARAMETER_TIMELOCK) revert TimelockTooLong(newTimelock, MAX_ECONOMIC_PARAMETER_TIMELOCK);
        
        uint256 oldTimelock = parameterTimelock;
        parameterTimelock = newTimelock;
        
        emit ParameterTimelockUpdated(oldTimelock, newTimelock);
    }

    // ============ View Functions ============
    
    /**
     * @notice Get the parameters that apply to a specific claim (frozen at claim creation)
     * @param claimId The ID of the claim
     * @return The economic parameters active when the claim was created
     */
    function getParametersForClaim(uint256 claimId) external view returns (EconomicParameters memory) {
        uint256 versionId = _claimVersionMap[claimId];
        if (versionId == 0) revert ClaimNotFound(claimId);
        return _versions[versionId].parameters;
    }
    
    /**
     * @notice Get the currently active parameters
     * @return The current economic parameters
     */
    function getCurrentParameters() external view returns (EconomicParameters memory) {
        return _versions[currentActiveVersionId].parameters;
    }
    
    /**
     * @notice Get the scheduled (queued) version if one exists
     * @return The scheduled version details
     */
    function getScheduledVersion() external view returns (ParameterVersion memory) {
        if (scheduledVersionId == 0) revert NoScheduledVersion();
        return _versions[scheduledVersionId];
    }
    
    /**
     * @notice Get a specific version by ID
     * @param versionId The version ID to retrieve
     * @return The version details
     */
    function getVersion(uint256 versionId) external view returns (ParameterVersion memory) {
        if (_versions[versionId].versionId == 0) revert VersionNotFound(versionId);
        return _versions[versionId];
    }
    
    /**
     * @notice Check if a version is still active
     * @param versionId The version ID to check
     * @return True if the version is currently active
     */
    function isVersionActive(uint256 versionId) external view returns (bool) {
        return versionId == currentActiveVersionId;
    }
    
    /**
     * @notice Check if a version has been superseded
     * @param versionId The version ID to check
     * @return True if the version has been superseded by a newer version
     */
    function isVersionSuperseded(uint256 versionId) external view returns (bool) {
        return _versionSuperseded[versionId];
    }ded[versionId];
    }

    // ============ Internal Validation ============
    
    function _validateParameterBounds(EconomicParameters calldata params) internal pure {
        // Validate allocation basis points sum to exactly 10000
        uint256 totalBPS = params.verifierRewardsBPS +
                          params.treasuryReserveBPS +
                          params.ecosystemIncentivesBPS +
                          params.governanceIncentivesBPS +
                          params.protocolDevelopmentBPS +
                          params.emergencyReserveBPS;
                          
        if (totalBPS != BPS_DENOMINATOR) revert InvalidAllocationBPS(totalBPS);
        
        // Validate fee parameters are within reasonable bounds
        if (params.claimSubmissionFee > 100e18) revert InvalidFee("claimSubmissionFee too high");
        if (params.verificationSubmissionFee > 100e18) revert InvalidFee("verificationSubmissionFee too high");
        if (params.disputeInitiationFee > 100e18) revert InvalidFee("disputeInitiationFee too high");
        if (params.protocolReserveFeeBPS > 1000) revert InvalidFee("protocolReserveFeeBPS too high (max 10%)");
        
        // Validate reputation parameters
        if (params.minReputationScore > params.maxReputationScore) revert InvalidReputationBounds();
        if (params.defaultReputationScore < params.minReputationScore || params.defaultReputationScore > params.maxReputationScore) {
            revert InvalidDefaultReputation();
        }
        
        // Validate slashing parameters
        if (params.slashPercentageBPS > params.maxSlashPercentageBPS) revert InvalidSlashBounds();
        if (params.maxSlashPercentageBPS > BPS_DENOMINATOR) revert InvalidMaxSlash();
        
        // Validate staking parameters
        if (params.minStakeAmount == 0) revert InvalidMinStake();
        
        // Validate multiplier parameters
        if (params.rewardMultiplier == 0) revert InvalidRewardMultiplier();
    }

    // ============ Guardian cannot activate or edit versions (security requirement) ===========
    
    /// @notice Guardians can only cancel queued versions, never activate or edit them
    function cancelQueuedVersion(uint256 versionId) external nonReentrant {
        if (!hasRole(GUARDIAN_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, GUARDIAN_ROLE);
        }
        
        ParameterVersion storage version = _versions[versionId];
        if (version.versionId == 0) revert VersionNotFound(versionId);
        if (version.status != VersionStatus.QUEUED) revert VersionNotQueued(versionId);
        if (versionId != scheduledVersionId) revert NotScheduledVersion(versionId);
        
        version.status = VersionStatus.CANCELLED;
        scheduledVersionId = 0;
        
        emit VersionCancelled(versionId, msg.sender);
    }

    // ============ Errors ============
    
    error VersionNotFound(uint256 versionId);
    error VersionNotQueued(uint256 versionId);
    error NotScheduledVersion(uint256 versionId);
    error TimelockNotExpired(uint256 executeAfter);
    error NoScheduledVersion();
    error ClaimNotFound(uint256 claimId);
    error ClaimAlreadyRegistered(uint256 claimId);
    error InvalidClaimId();
    error TimelockTooShort(uint256 provided, uint256 minimum);
    error TimelockTooLong(uint256 provided, uint256 maximum);
    error InvalidAllocationBPS(uint256 total);
    error InvalidFee(string reason);
    error InvalidReputationBounds();
    error InvalidDefaultReputation();
    error InvalidSlashBounds();
    error InvalidMaxSlash();
    error InvalidMinStake();
    error InvalidRewardMultiplier();
}