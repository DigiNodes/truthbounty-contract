// SPDX-License-Identifier: MIT
ppragma solidity ^^0.8.20;

interface IConfigurationRegistry {
    struct ParameterSet {
        address[] supportedAssets;
        uint256 minBounty;
        uint256 maxBounty;
        uint256 maxWeight;
        uint256 challengeDuration;
        uint256 appealDuration;
        uint256 participationThreshold;
        uint256 confidenceBps;
        uint256 challengeBondBps;
        uint256 appealMultiplierBps;
        uint256[] allocationBps;
        uint256 minReputation;
        uint256 maxReputation;
        uint256 pauseCooldown;
    }
    event ParameterSetPublished(bytes32 indexed parameterSetId, address indexed publisher);
    error InvalidParameterSet();
    function publishParameterSet(ParameterSet calldata params) external returns (bytes32 id);
    function getParameterSet(bytes32 id) external view returns (ParameterSet memory);
    function isPublished(bytes32 id) external view returns (bool);
}
