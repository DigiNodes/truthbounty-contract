// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./ITokenomicsEngine.sol";

/**
 * @title AllocationPolicies
 * @notice Pure mathematical library for tokenomics distribution policies.
 * @dev Contains deterministic, testable allocation functions.
 *
 * Supported policies:
 * - proportional: equal-percentage split across categories
 * - reputation-weighted: verifier share modulated by reputation score
 * - stake-weighted: verifier share modulated by active stake
 * - governance-incentives: reserved for future governance reward distribution
 *
 * Referral incentives can be added later by extending this library
 * without modifying the core TokenomicsEngine.
 */
library AllocationPolicies {

    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ============ Proportional Allocation ==========

    function calculateProportionalAllocation(
        uint256 amount,
        ITokenomicsEngine.SourceAllocation memory config
    )
        internal
        pure
        returns (ITokenomicsEngine.AllocationShares memory shares)
    {
        uint256 remaining = amount;

        shares.verifierRewards = _bpsShare(amount, config.verifierRewardsBPS);
        remaining -= shares.verifierRewards;

        shares.treasuryReserve = _bpsShare(amount, config.treasuryReserveBPS);
        remaining -= shares.treasuryReserve;

        shares.ecosystemIncentives = _bpsShare(amount, config.ecosystemIncentivesBPS);
        remaining -= shares.ecosystemIncentives;

        shares.governanceIncentives = _bpsShare(amount, config.governanceIncentivesBPS);
        remaining -= shares.governanceIncentives;

        shares.protocolDevelopment = _bpsShare(amount, config.protocolDevelopmentBPS);
        remaining -= shares.protocolDevelopment;

        shares.emergencyReserve = remaining;

        return shares;
    }

    // ============ Reputation-Weighted Allocation ==========

    function calculateReputationWeightedAllocation(
        uint256 amount,
        ITokenomicsEngine.SourceAllocation memory config,
        uint256 totalReputationScore
    )
        internal
        pure
        returns (ITokenomicsEngine.AllocationShares memory shares)
    {
        uint256 remaining = amount;

        shares.verifierRewards = _bpsShare(amount, config.verifierRewardsBPS);
        remaining -= shares.verifierRewards;

        shares.treasuryReserve = _bpsShare(amount, config.treasuryReserveBPS);
        remaining -= shares.treasuryReserve;

        shares.ecosystemIncentives = _bpsShare(amount, config.ecosystemIncentivesBPS);
        remaining -= shares.ecosystemIncentives;

        shares.governanceIncentives = _bpsShare(amount, config.governanceIncentivesBPS);
        remaining -= shares.governanceIncentives;

        shares.protocolDevelopment = _bpsShare(amount, config.protocolDevelopmentBPS);
        remaining -= shares.protocolDevelopment;

        shares.emergencyReserve = remaining;

        if (totalReputationScore > 0) {
            uint256 reputationScaled = (shares.verifierRewards * totalReputationScore) / (totalReputationScore + 1e18);
            shares.verifierRewards = reputationScaled;
        }

        return shares;
    }

    // ============ Stake-Weighted Allocation ==========

    function calculateStakeWeightedAllocation(
        uint256 amount,
        ITokenomicsEngine.SourceAllocation memory config,
        uint256 totalActiveStake
    )
        internal
        pure
        returns (ITokenomicsEngine.AllocationShares memory shares)
    {
        uint256 remaining = amount;

        shares.verifierRewards = _bpsShare(amount, config.verifierRewardsBPS);
        remaining -= shares.verifierRewards;

        shares.treasuryReserve = _bpsShare(amount, config.treasuryReserveBPS);
        remaining -= shares.treasuryReserve;

        shares.ecosystemIncentives = _bpsShare(amount, config.ecosystemIncentivesBPS);
        remaining -= shares.ecosystemIncentives;

        shares.governanceIncentives = _bpsShare(amount, config.governanceIncentivesBPS);
        remaining -= shares.governanceIncentives;

        shares.protocolDevelopment = _bpsShare(amount, config.protocolDevelopmentBPS);
        remaining -= shares.protocolDevelopment;

        shares.emergencyReserve = remaining;

        if (totalActiveStake > 0) {
            uint256 stakeScaled = (shares.verifierRewards * totalActiveStake) / (totalActiveStake + 1e18);
            shares.verifierRewards = stakeScaled;
        }

        return shares;
    }

    // ============ Governance Incentive Allocation ==========

    function calculateGovernanceIncentiveAllocation(
        uint256 amount,
        ITokenomicsEngine.SourceAllocation memory config
    )
        internal
        pure
        returns (ITokenomicsEngine.AllocationShares memory shares)
    {
        uint256 remaining = amount;

        shares.verifierRewards = _bpsShare(amount, config.verifierRewardsBPS);
        remaining -= shares.verifierRewards;

        shares.treasuryReserve = _bpsShare(amount, config.treasuryReserveBPS);
        remaining -= shares.treasuryReserve;

        shares.ecosystemIncentives = _bpsShare(amount, config.ecosystemIncentivesBPS);
        remaining -= shares.ecosystemIncentives;

        shares.governanceIncentives = _bpsShare(amount, config.governanceIncentivesBPS);
        remaining -= shares.governanceIncentives;

        shares.protocolDevelopment = _bpsShare(amount, config.protocolDevelopmentBPS);
        remaining -= shares.protocolDevelopment;

        shares.emergencyReserve = remaining;

        return shares;
    }

    // ============ Validation Helpers ==========

    function validateAllocationConfig(ITokenomicsEngine.SourceAllocation memory config)
        internal
        pure
        returns (bool valid, string memory reason)
    {
        if (!config.active) {
            return (false, "allocation inactive");
        }

        uint256 totalBPS = config.verifierRewardsBPS
            + config.treasuryReserveBPS
            + config.ecosystemIncentivesBPS
            + config.governanceIncentivesBPS
            + config.protocolDevelopmentBPS
            + config.emergencyReserveBPS;

        if (totalBPS != BPS_DENOMINATOR) {
            return (false, "basis points do not sum to 10000");
        }

        return (true, "");
    }

    // ============ Internal Helpers ==========

    function _bpsShare(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / BPS_DENOMINATOR;
    }
}
