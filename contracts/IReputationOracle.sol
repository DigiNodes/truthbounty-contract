// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IReputationOracle
 * @notice Interface for reputation score providers
 * @dev This interface allows the TruthBounty system to accept reputation scores
 *      from external sources (oracles, adapters, or on-chain reputation systems)
 */
interface IReputationOracle {
    /**
     * @notice Get the reputation score for a given address
     * @param user The address to query reputation for
     * @return score The reputation score (scaled by 1e18 for precision)
     * @dev Returns 0 if user has no reputation
     *      A score of 1e18 represents neutral/base reputation (100%)
     *      Scores can range from 0 to type(uint256).max
     */
    function getReputationScore(address user) external view returns (uint256 score);

    /**
     * @notice Check if the oracle is active and providing valid data
     * @return isActive True if the oracle is operational
     */
    function isActive() external view returns (bool isActive);
}
