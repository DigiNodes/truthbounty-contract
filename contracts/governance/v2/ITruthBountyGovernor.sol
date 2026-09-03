// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/**
 * @title ITruthBountyGovernor
 * @notice TruthBounty governor surface including proposal-id helpers from {GovernorStorage}.
 */
interface ITruthBountyGovernor is IGovernor {
    function cancel(uint256 proposalId) external;
    function queue(uint256 proposalId) external;
    function execute(uint256 proposalId) external payable;
}
