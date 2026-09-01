// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
interface IAggregation is IV2Module {
    event AggregationFinalized(uint256 indexed claimId, bool accepted, uint256 supportingWeight, uint256 opposingWeight);
    function finalizeAggregation(uint256 claimId) external;
    function outcome(uint256 claimId) external view returns (bool finalized, bool accepted, uint256 supportingWeight, uint256 opposingWeight);
}
