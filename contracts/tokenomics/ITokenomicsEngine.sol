// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../treasury/ITreasuryAccounting.sol";

/**
 * @title ITokenomicsEngine
 * @notice Interface for the TruthBounty Tokenomics & Incentive Distribution Framework (SC-027)
 * @dev Defines the external API for deterministic protocol revenue allocation.
 *
 * Allocation flow:
 *   Revenue → Treasury → Verifier Rewards → Governance → Ecosystem → Protocol Dev → Emergency Reserve
 *
 * Every allocation must be reproducible and auditable via on-chain events and history records.
 */
interface ITokenomicsEngine {

    // ============ Enums ==========

    enum RevenueSource {
        PROTOCOL_FEES,            // Revenue from FeeManager
        TREASURY_ALLOCATION,      // Direct treasury transfers
        GOVERNANCE_INCENTIVE_POOL,// Governance-controlled incentive pool
        ECOSYSTEM_GRANTS,         // External ecosystem grants
        STAKING_EMISSIONS         // Future staking emissions
    }

    // ============ Structs ==========

    struct SourceAllocation {
        uint256 verifierRewardsBPS;
        uint256 treasuryReserveBPS;
        uint256 ecosystemIncentivesBPS;
        uint256 governanceIncentivesBPS;
        uint256 protocolDevelopmentBPS;
        uint256 emergencyReserveBPS;
        bool active;
    }

    struct AllocationShares {
        uint256 verifierRewards;
        uint256 treasuryReserve;
        uint256 ecosystemIncentives;
        uint256 governanceIncentives;
        uint256 protocolDevelopment;
        uint256 emergencyReserve;
    }

    struct DistributionRecord {
        bytes32 distributionId;
        RevenueSource source;
        uint256 totalAmount;
        uint256 verifierRewards;
        uint256 treasuryReserve;
        uint256 ecosystemIncentives;
        uint256 governanceIncentives;
        uint256 protocolDevelopment;
        uint256 emergencyReserve;
        uint256 timestamp;
        bool executed;
    }

    struct EmissionStats {
        uint256 totalDistributed;
        uint256 emissionLimit;
        uint256 rewardMultiplier;
        uint256 treasuryReserveTargetBPS;
    }

    // ============ Events ==========

    event RevenueReceived(
        RevenueSource indexed source,
        uint256 amount,
        address indexed sender
    );

    event TokenomicsAllocated(
        bytes32 indexed distributionId,
        RevenueSource indexed source,
        uint256 totalAmount
    );

    event IncentiveDistributionCompleted(
        bytes32 indexed distributionId,
        uint256 verifierRewards,
        uint256 ecosystemIncentives,
        uint256 governanceIncentives,
        uint256 protocolDevelopment,
        uint256 emergencyReserve
    );

    event AllocationUpdated(
        RevenueSource indexed source,
        uint256 oldVerifierRewardsBPS,
        uint256 oldTreasuryReserveBPS,
        uint256 oldEcosystemIncentivesBPS,
        uint256 oldGovernanceIncentivesBPS,
        uint256 oldProtocolDevelopmentBPS,
        uint256 oldEmergencyReserveBPS,
        uint256 newVerifierRewardsBPS,
        uint256 newTreasuryReserveBPS,
        uint256 newEcosystemIncentivesBPS,
        uint256 newGovernanceIncentivesBPS,
        uint256 newProtocolDevelopmentBPS,
        uint256 newEmergencyReserveBPS
    );

    event EmissionLimitUpdated(uint256 oldLimit, uint256 newLimit);

    event RewardMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier);

    event TreasuryReserveTargetUpdated(uint256 oldTarget, uint256 newTarget);

    // ============ Core Distribution ==========

    function distributeRevenue(RevenueSource source, uint256 amount)
        external
        returns (bytes32 distributionId);

    function allocateBatch(RevenueSource[] calldata sources, uint256[] calldata amounts)
        external
        returns (bytes32[] memory distributionIds);

    // ============ Governance Controls ==========

    function setSourceAllocation(RevenueSource source, SourceAllocation calldata config)
        external;

    function setEmissionLimit(uint256 _emissionLimit) external;

    function setRewardMultiplier(uint256 _multiplier) external;

    function setTreasuryReserveTarget(uint256 _targetBPS) external;

    // ============ Read Interfaces ==========

    function getAllocationConfig(RevenueSource source)
        external
        view
        returns (SourceAllocation memory);

    function getDistributionRecord(bytes32 distributionId)
        external
        view
        returns (DistributionRecord memory);

    function getEmissionStats()
        external
        view
        returns (EmissionStats memory);

    function getTotalBySource(RevenueSource source)
        external
        view
        returns (uint256);

    function getDistributionHistory(uint256 offset, uint256 limit)
        external
        view
        returns (DistributionRecord[] memory history);

    function getProcessedDistribution(bytes32 distributionId)
        external
        view
        returns (bool);
}
