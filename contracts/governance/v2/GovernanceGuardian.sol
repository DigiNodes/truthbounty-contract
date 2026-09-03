// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ITruthBountyGovernor} from "./ITruthBountyGovernor.sol";

/**
 * @title GovernanceGuardian
 * @notice Separate emergency guardian with veto/cancel powers but no execution authority.
 * @dev Guardian may cancel active or queued proposals and pause registered modules.
 *      Guardian cannot execute proposals, bypass timelock delays, or settle claims.
 */
contract GovernanceGuardian is AccessControl, Pausable {
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    ITruthBountyGovernor public immutable governor;

    event ProposalVetoed(uint256 indexed proposalId, address indexed guardian);
    event GuardianModulePauseRequested(address indexed module, address indexed guardian);

    error ZeroGovernorAddress();
    error NotGuardian(address caller);

    constructor(address admin, address guardian, ITruthBountyGovernor governor_) {
        if (address(governor_) == address(0)) revert ZeroGovernorAddress();
        governor = governor_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, guardian);
    }

    /**
     * @notice Cancel a governance proposal. Delegates to the governor cancel path.
     * @dev Guardian cancellation is authorized inside {TruthBountyGovernor._validateCancel}.
     */
    function vetoProposal(uint256 proposalId) external onlyRole(GUARDIAN_ROLE) {
        governor.cancel(proposalId);
        emit ProposalVetoed(proposalId, msg.sender);
    }

    /**
     * @notice Signal an emergency pause request for a module. Does not execute module calls.
     */
    function requestModulePause(address module) external onlyRole(GUARDIAN_ROLE) {
        emit GuardianModulePauseRequested(module, msg.sender);
    }

    /**
     * @notice Guardian-controlled circuit breaker for guardian contract itself.
     */
    function guardianPause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    function guardianUnpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
