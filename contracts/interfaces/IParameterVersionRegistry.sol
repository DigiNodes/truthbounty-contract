// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IParameterVersionRegistry
 * @notice Interface for the versioned economic parameter registry with timelock activation
 * @dev Defines the external API, events, and data structures for parameter version management
 */
interface IParameterVersionRegistry {
    // ============ Enums ============
    
    enum VersionStatus {
        PROPOSED,
        QUEUED,
        ACTIVE,
        SUPERSEDED,
        CANCELLED
    }

    // ============ Data Structures ============
    
    /**
     * @notice Complete set of all economic parameters for a single version
     * @dev All parameters are validated and stored atomically when a version is created
     */
    struct EconomicParameters {
        // Tokenomics allocations (all in basis points)
        uint256 verifierRewardsBPS;
        uint256 treasuryReserveBPS;
        uint256 ecosystemIncentivesBPS;
        uint256 governanceIncentivesBPS;
        uint256 protocolDevelopmentBPS;
        uint256 emergencyReserveBPS;
        
        // Tokenomics limits and multipliers
        uint256 emissionLimit;
        uint256 rewardMultiplier;
        uint256 treasuryReserveTargetBPS;
        
        // Fee parameters
        uint256 claimSubmissionFee;
        uint256 verificationSubmissionFee;
        uint256 disputeInitiationFee;
        uint256 protocolReserveFeeBPS;
        
        // Staking and reputation parameters
        uint256 minStakeAmount;
        uint256 minReputationScore;
        uint256 maxReputationScore;
        uint256 defaultReputationScore;
        
        // Slashing parameters
        uint256 slashPercentageBPS;
        uint256 maxSlashPercentageBPS;
    }
    
    /**
     * @notice Complete version metadata including parameters and lifecycle timestamps
     */
    struct ParameterVersion {
        uint256 versionId;
        EconomicParameters parameters;
        VersionStatus status;
        address proposer;
        uint256 proposedAt;
        uint256 executeAfter;
        uint256 activatedAt;
    }

    // ============ Events ============
    
    /**
     * @notice Emitted when a new parameter version is proposed
     */
    event VersionProposed(
        uint256 indexed versionId,
        address indexed proposer,
        uint256 proposedAt,
        uint256 executeAfter
    );
    
    /**
     * @notice Emitted when a version is queued for activation after timelock
     */
    event VersionQueued(
        uint256 indexed versionId,
        uint256 executeAfter
    );
    
    /**
     * @notice Emitted when a version is successfully activated
     */
    event VersionActivated(
        uint256 indexed versionId,
        uint256 activatedAt
    );
    
    /**
     * @notice Emitted when an active version is superseded by a new version
     */
    event VersionSuperseded(
        uint256 indexed oldVersionId,
        uint256 indexed newVersionId
    );
    
    /**
     * @notice Emitted when a queued version is cancelled
     */
    event VersionCancelled(
        uint256 indexed versionId,
        address indexed canceller
    );
    
    /**
     * @notice Emitted when a claim is created and linked to its frozen version
     */
    event ClaimLinkedToVersion(
        uint256 indexed claimId,
        uint256 indexed versionId
    );
    
    /**
     * @notice Emitted when the global parameter timelock is updated
     */
    event ParameterTimelockUpdated(
        uint256 oldTimelock,
        uint256 newTimelock
    );

    // ============ External Functions ============
    
    function proposeNewVersion(EconomicParameters calldata parameters) 
        external 
        returns (uint256 versionId);
    
    function activateVersion(uint256 versionId) external;
    
    function recordClaimCreation(uint256 claimId) external;
    
    function updateParameterTimelock(uint256 newTimelock) external;
    
    function cancelQueuedVersion(uint256 versionId) external;
    
    // ============ View Functions ============
    
    function getParametersForClaim(uint256 claimId) external view returns (EconomicParameters memory);
    function getCurrentParameters() external view returns (EconomicParameters memory);
    function getScheduledVersion() external view returns (ParameterVersion memory);
    function getVersion(uint256 versionId) external view returns (ParameterVersion memory);
    function isVersionActive(uint256 versionId) external view returns (bool);
    function isVersionSuperseded(uint256 versionId) external view returns (bool);
    
    function MIN_ECONOMIC_PARAMETER_TIMELOCK() external view returns (uint256);
    function currentActiveVersionId() external view returns (uint256);
    function scheduledVersionId() external view returns (uint256);
    function parameterTimelock() external view returns (uint256);
}