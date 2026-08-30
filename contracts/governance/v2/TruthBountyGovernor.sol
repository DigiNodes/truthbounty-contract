// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorStorage} from "@openzeppelin/contracts/governance/extensions/GovernorStorage.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernedModuleRegistry} from "./IGovernedModuleRegistry.sol";
import {GovernanceForbiddenCalls} from "./libraries/GovernanceForbiddenCalls.sol";

/**
 * @title TruthBountyGovernor
 * @notice GovernorBravo-compatible OpenZeppelin governor integrated with {TimelockController}.
 * @dev Proposals may only target registered governed modules and are blocked from claim-outcome calls.
 *      Guardian cancellation is separate from timelock execution authority.
 */
contract TruthBountyGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl,
    GovernorStorage
{
    using GovernanceForbiddenCalls for bytes;

    IGovernedModuleRegistry public immutable moduleRegistry;
    address public guardian;

    event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian);
    event GovernanceManifestPublished(
        address indexed governor,
        address indexed timelock,
        address indexed token,
        address moduleRegistry,
        uint256 votingDelay,
        uint256 votingPeriod,
        uint256 proposalThreshold,
        uint256 quorumNumerator,
        uint256 timelockMinDelay
    );

    error ZeroGuardianAddress();
    error TargetNotGovernedModule(address target);

    constructor(
        IVotes token,
        TimelockController timelock,
        IGovernedModuleRegistry registry,
        address guardian_,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumNumerator_
    )
        Governor("TruthBountyGovernor")
        GovernorSettings(votingDelay_, votingPeriod_, proposalThreshold_)
        GovernorVotes(token)
        GovernorVotesQuorumFraction(quorumNumerator_)
        GovernorTimelockControl(timelock)
    {
        if (guardian_ == address(0)) revert ZeroGuardianAddress();
        moduleRegistry = registry;
        guardian = guardian_;
    }

    /**
     * @notice Publish canonical governance configuration for manifest generation and indexers.
     */
    function publishManifest() external {
        emit GovernanceManifestPublished(
            address(this),
            timelock(),
            address(token()),
            address(moduleRegistry),
            votingDelay(),
            votingPeriod(),
            proposalThreshold(),
            quorumNumerator(),
            TimelockController(payable(timelock())).getMinDelay()
        );
    }

    /**
     * @notice Rotate the guardian address. Callable only through a successful governance proposal.
     */
    function setGuardian(address newGuardian) external onlyGovernance {
        if (newGuardian == address(0)) revert ZeroGuardianAddress();
        address oldGuardian = guardian;
        guardian = newGuardian;
        emit GuardianUpdated(oldGuardian, newGuardian);
    }

    /// @inheritdoc Governor
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256) {
        _validateProposalOperations(targets, calldatas);
        return super.propose(targets, values, calldatas, description);
    }

    /// @inheritdoc Governor
    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal override(Governor, GovernorStorage) returns (uint256) {
        _validateProposalOperations(targets, calldatas);
        return super._propose(targets, values, calldatas, description, proposer);
    }

    /// @inheritdoc Governor
    function _validateCancel(uint256 proposalId, address caller) internal view override returns (bool) {
        return super._validateCancel(proposalId, caller) || caller == guardian;
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }

    function _validateProposalOperations(address[] memory targets, bytes[] memory calldatas) internal view {
        uint256 length = targets.length;
        for (uint256 i = 0; i < length; ++i) {
            if (!moduleRegistry.isGovernedModule(targets[i])) {
                revert TargetNotGovernedModule(targets[i]);
            }
            calldatas[i].enforceAllowed();
        }
    }
}
