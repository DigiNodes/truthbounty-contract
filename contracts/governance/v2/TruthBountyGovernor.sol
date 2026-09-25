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
 *
 *      Cancellation semantics (V2-SC-066): a proposal may only be cancelled while it is in a
 *      non-terminal state (Pending, Active, Succeeded, or Queued) and only under one of the four
 *      explicit {CancelAuthority} conditions — proposer withdrawal, proposer-below-threshold
 *      invalidation, guardian veto, or governed-module invalidation. Every other path fails closed
 *      with {ProposalCancellationUnauthorized}. Cancellation decisions are evaluated freshly on
 *      every call against canonical state, so no authorisation can be stored, replayed, or reused
 *      after the proposal it was granted for has left the cancelable window.
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

    /// @notice Explicit, exhaustive conditions under which a governance proposal may be cancelled (V2-SC-066).
    enum CancelAuthority {
        /// @dev No cancellation condition satisfied — every cancel attempt fails closed.
        NONE,
        /// @dev The original proposer withdraws their own proposal while it is Pending or Active.
        PROPOSER,
        /// @dev Permissionless: the proposer's live voting power fell below `proposalThreshold()`
        ///      while the proposal is still Pending, so the proposal no longer meets the spam bar
        ///      that allowed it to be created.
        THRESHOLD,
        /// @dev The guardian (or the wired guardian module) vetoes before execution.
        GUARDIAN,
        /// @dev Permissionless: at least one proposal target was removed from the governed module
        ///      registry after creation, so the proposal no longer targets canonical modules.
        INVALIDATED
    }

    IGovernedModuleRegistry public immutable moduleRegistry;
    address public guardian;
    address public governanceGuardianModule;

    /// @notice Emitted alongside {Governor-ProposalCanceled} recording who cancelled and under which condition.
    event ProposalCancellationAuthorized(
        uint256 indexed proposalId,
        address indexed caller,
        CancelAuthority authority
    );

    event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian);
    event GovernanceGuardianModuleUpdated(address indexed oldModule, address indexed newModule);
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
    error GovernanceGuardianModuleAlreadySet(address existingModule);
    error UnauthorizedGuardianModuleSetter(address caller);
    /// @dev Thrown when a cancel attempt satisfies none of the explicit {CancelAuthority} conditions.
    error ProposalCancellationUnauthorized(uint256 proposalId, address caller);

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
        return super._propose(targets, values, calldatas, description, proposer);
    }

    /**
     * @notice Cancel a proposal under the explicit V2-SC-066 cancellation conditions.
     * @dev Reverts with {ProposalCancellationUnauthorized} unless `caller` satisfies one of the
     *      {CancelAuthority} conditions for the proposal's current state. Emits
     *      {ProposalCancellationAuthorized} before {Governor-ProposalCanceled} so indexers can
     *      attribute every cancellation to its condition. Unknown proposal ids revert with
     *      {Governor-GovernorNonexistentProposal}.
     * @param targets Proposal target contracts (must hash to a known proposal id).
     * @param values ETH value per target.
     * @param calldatas Encoded calls per target.
     * @param descriptionHash keccak256 hash of the proposal description.
     * @return proposalId The cancelled proposal id.
     */
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public override returns (uint256) {
        uint256 proposalId = getProposalId(targets, values, calldatas, descriptionHash);
        address caller = _msgSender();

        if (proposalSnapshot(proposalId) != 0) {
            CancelAuthority authority = cancellationAuthority(proposalId, caller);
            if (authority == CancelAuthority.NONE) {
                revert ProposalCancellationUnauthorized(proposalId, caller);
            }
            emit ProposalCancellationAuthorized(proposalId, caller, authority);
        }

        return super.cancel(targets, values, calldatas, descriptionHash);
    }

    /// @inheritdoc Governor
    function _validateCancel(uint256 proposalId, address caller) internal view override returns (bool) {
        return _cancellationAuthority(proposalId, caller, state(proposalId)) != CancelAuthority.NONE;
    }

    /**
     * @notice Return the explicit condition under which `caller` may cancel `proposalId` right now.
     * @dev Conditions are evaluated against fresh canonical state on every call: nothing is cached,
     *      stored, or reusable, so a previously valid authorisation cannot be replayed once the
     *      proposal leaves the cancelable window. Returns {CancelAuthority-NONE} for unknown
     *      proposals and for every terminal state (Defeated, Canceled, Expired, Executed).
     * @param proposalId The proposal to evaluate.
     * @param caller The address that would submit the cancellation.
     * @return The satisfied condition, or {CancelAuthority-NONE} when cancellation must fail closed.
     */
    function cancellationAuthority(uint256 proposalId, address caller) public view returns (CancelAuthority) {
        if (proposalSnapshot(proposalId) == 0) {
            return CancelAuthority.NONE;
        }
        return _cancellationAuthority(proposalId, caller, state(proposalId));
    }

    /**
     * @notice Whether `proposalId` targets at least one address no longer in the governed module registry.
     * @dev Only meaningful while the proposal is in a non-terminal cancelable state; returns false
     *      for unknown proposals and terminal states so callers fail closed rather than assume
     *      invalidation that can no longer act.
     * @param proposalId The proposal to inspect.
     * @return True when a target was deregistered after proposal creation.
     */
    function isProposalInvalidated(uint256 proposalId) public view returns (bool) {
        if (proposalSnapshot(proposalId) == 0) {
            return false;
        }
        ProposalState currentState = state(proposalId);
        if (!_isCancelableState(currentState)) {
            return false;
        }
        return _hasDeregisteredTarget(proposalId);
    }

    /// @dev Core authority rules shared by the public view and the {Governor-_validateCancel} hook.
    function _cancellationAuthority(
        uint256 proposalId,
        address caller,
        ProposalState currentState
    ) internal view returns (CancelAuthority) {
        if (!_isCancelableState(currentState)) {
            return CancelAuthority.NONE;
        }
        if (caller == guardian || caller == governanceGuardianModule) {
            return CancelAuthority.GUARDIAN;
        }

        address proposer = proposalProposer(proposalId);
        if (caller == proposer && (currentState == ProposalState.Pending || currentState == ProposalState.Active)) {
            return CancelAuthority.PROPOSER;
        }
        if (_hasDeregisteredTarget(proposalId)) {
            return CancelAuthority.INVALIDATED;
        }

        // Threshold invalidation is deliberately restricted to Pending: once voting has started the
        // proposer's power is snapshotted, and permissionless cancellation must never be usable to
        // censor a live vote (anti-censorship property).
        uint256 votesThreshold = proposalThreshold();
        if (
            currentState == ProposalState.Pending &&
            votesThreshold > 0 &&
            getVotes(proposer, clock() - 1) < votesThreshold
        ) {
            return CancelAuthority.THRESHOLD;
        }
        return CancelAuthority.NONE;
    }

    /// @dev True only for states in which OpenZeppelin's state machine still accepts a cancellation.
    function _isCancelableState(ProposalState currentState) internal pure returns (bool) {
        return
            currentState == ProposalState.Pending ||
            currentState == ProposalState.Active ||
            currentState == ProposalState.Succeeded ||
            currentState == ProposalState.Queued;
    }

    /// @dev True when any proposal target has been removed from the governed module registry.
    function _hasDeregisteredTarget(uint256 proposalId) internal view returns (bool) {
        (address[] memory targets,,,) = proposalDetails(proposalId);
        uint256 length = targets.length;
        for (uint256 i = 0; i < length; ++i) {
            if (!moduleRegistry.isGovernedModule(targets[i])) {
                return true;
            }
        }
        return false;
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
