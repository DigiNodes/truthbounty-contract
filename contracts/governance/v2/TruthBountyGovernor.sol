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
import {IGovernanceSnapshot} from "./IGovernanceSnapshot.sol";
import {GovernanceForbiddenCalls} from "./libraries/GovernanceForbiddenCalls.sol";

/**
 * @title TruthBountyGovernor
 * @notice GovernorBravo-compatible OpenZeppelin governor integrated with {TimelockController}.
 * @dev Proposals may only target registered governed modules and are blocked from claim-outcome calls.
 *      Guardian cancellation is separate from timelock execution authority.
 *
 *      ## Canonical Snapshot Integration (V2-SC-063)
 *
 *      At proposal creation, `_propose` calls `governanceSnapshot.registerSnapshot(proposalId)`,
 *      recording the exact `block.timestamp` at which the proposal was created as the
 *      canonical voting-power freeze point. This timestamp is identical to
 *      `proposalSnapshot(proposalId)` used by {GovernorVotes._getVotes} and ensures that
 *      voting-power queries cannot be influenced by token transfers, delegations, or
 *      stake changes that occur after proposal creation.
 *
 *      If `governanceSnapshot` is set (non-zero), snapshot registration is mandatory: a
 *      failed call reverts the entire `_propose` call, preventing proposals from existing
 *      without a canonical snapshot entry (fail-closed).
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

    /**
     * @notice Canonical governance snapshot registry.
     * @dev Set at construction and immutable thereafter. A non-zero address activates
     *      mandatory snapshot registration on every proposal. Zero address disables
     *      the hook (legacy / migration path only; not recommended for production).
     */
    IGovernanceSnapshot public immutable governanceSnapshot;

    address public guardian;
    address public governanceGuardianModule;

    event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian);
    event GovernanceGuardianModuleUpdated(address indexed oldModule, address indexed newModule);
    event GovernanceManifestPublished(
        address indexed governor,
        address indexed timelock,
        address indexed token,
        address moduleRegistry,
        address governanceSnapshot,
        uint256 votingDelay,
        uint256 votingPeriod,
        uint256 proposalThreshold,
        uint256 quorumNumerator,
        uint256 timelockMinDelay
    );

    error ZeroGuardianAddress();
    error TargetNotGovernedModule(address target);
    error GovernanceGuardianModuleAlreadySet(address existingModule);
    error UnauthorizedGuardianModuleSetter(address caller);

    /**
     * @param token_             ERC20Votes governance token (timestamp clock).
     * @param timelock_          Timelock controller for execution delay.
     * @param registry_          Registry of allowed proposal targets.
     * @param snapshot_          Canonical snapshot registry; `address(0)` disables the hook.
     * @param guardian_          Initial guardian address; cannot be `address(0)`.
     * @param votingDelay_       Blocks/seconds before voting opens after proposal.
     * @param votingPeriod_      Duration of the voting window.
     * @param proposalThreshold_ Minimum token balance to submit a proposal.
     * @param quorumNumerator_   Percentage (of total supply) required for quorum.
     */
    constructor(
        IVotes token_,
        TimelockController timelock_,
        IGovernedModuleRegistry registry_,
        IGovernanceSnapshot snapshot_,
        address guardian_,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumNumerator_
    )
        Governor("TruthBountyGovernor")
        GovernorSettings(votingDelay_, votingPeriod_, proposalThreshold_)
        GovernorVotes(token_)
        GovernorVotesQuorumFraction(quorumNumerator_)
        GovernorTimelockControl(timelock_)
    {
        if (guardian_ == address(0)) revert ZeroGuardianAddress();
        moduleRegistry = registry_;
        governanceSnapshot = snapshot_;
        guardian = guardian_;
    }

    /**
     * @notice Publish canonical governance configuration for manifest generation and indexers.
     * @dev Includes the `governanceSnapshot` address so off-chain systems can derive the
     *      canonical snapshot timestamp for any proposal.
     */
    function publishManifest() external {
        emit GovernanceManifestPublished(
            address(this),
            timelock(),
            address(token()),
            address(moduleRegistry),
            address(governanceSnapshot),
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

    /**
     * @notice Wire the external guardian module once after deployment.
     * @dev Callable once by the guardian EOA during bootstrap.
     */
    function setGovernanceGuardianModule(address module) external {
        if (module == address(0)) revert ZeroGuardianAddress();
        if (governanceGuardianModule != address(0)) {
            revert GovernanceGuardianModuleAlreadySet(governanceGuardianModule);
        }
        if (msg.sender != guardian) revert UnauthorizedGuardianModuleSetter(msg.sender);
        governanceGuardianModule = module;
        emit GovernanceGuardianModuleUpdated(address(0), module);
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
        uint256 proposalId = super._propose(targets, values, calldatas, description, proposer);

        // Register the canonical snapshot timestamp for this proposal.
        // proposalSnapshot(proposalId) == clock() + votingDelay() at proposal creation —
        // this is the exact timepoint that GovernorVotes uses for all getPastVotes queries.
        // If governanceSnapshot is configured, registration is mandatory: a revert here
        // propagates upward and prevents the proposal from existing without a snapshot.
        if (address(governanceSnapshot) != address(0)) {
            uint48 snapTs = uint48(proposalSnapshot(proposalId));
            governanceSnapshot.registerSnapshot(proposalId, snapTs);
        }

        return proposalId;
    }

    /// @inheritdoc Governor
    function _validateCancel(uint256 proposalId, address caller) internal view override returns (bool) {
        return super._validateCancel(proposalId, caller) || caller == guardian || caller == governanceGuardianModule;
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function quorum(uint256 timepoint) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(timepoint);
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
