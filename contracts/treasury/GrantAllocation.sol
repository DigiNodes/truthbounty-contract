// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IGrantAllocation.sol";
import "./IBudgetRegistry.sol";

contract GrantAllocation is IGrantAllocation, AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant GRANT_MANAGER_ROLE = keccak256("GRANT_MANAGER_ROLE");
    bytes32 public constant GRANT_APPROVER_ROLE = keccak256("GRANT_APPROVER_ROLE");
    bytes32 public constant MILESTONE_VERIFIER_ROLE = keccak256("MILESTONE_VERIFIER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IBudgetRegistry public budgetRegistry;

    uint256 private _grantCount;

    mapping(bytes32 => Grant) private _grants;
    mapping(bytes32 => bool) private _grantExists;
    mapping(bytes32 => Milestone[]) private _milestones;
    mapping(bytes32 => bytes32[]) private _budgetGrants;
    mapping(bytes32 => uint256) private _budgetGrantCount;
    mapping(address => bytes32[]) private _recipientGrants;
    mapping(address => uint256) private _recipientGrantCount;

    bytes32[] private _allGrantIds;

    constructor(address _budgetRegistry, address admin) {
        require(_budgetRegistry != address(0), ZeroAddress());
        require(admin != address(0), ZeroAddress());

        budgetRegistry = IBudgetRegistry(_budgetRegistry);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GRANT_MANAGER_ROLE, admin);
        _grantRole(GRANT_APPROVER_ROLE, admin);
        _grantRole(MILESTONE_VERIFIER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        _setRoleAdmin(GRANT_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(GRANT_APPROVER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(MILESTONE_VERIFIER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    function proposeGrant(
        address recipient,
        uint256 amount,
        bytes32 budgetId,
        string calldata description,
        uint256[] calldata milestonePercentages
    ) external nonReentrant whenNotPaused onlyRole(GRANT_MANAGER_ROLE) returns (bytes32 grantId) {
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount == 0) revert ZeroAmount();

        IBudgetRegistry.Budget memory budget = budgetRegistry.getBudget(budgetId);
        if (budget.status != IBudgetRegistry.BudgetStatus.ACTIVE) revert("Budget not active");

        uint256 budgetRemaining = budget.approvedAmount - budget.spentAmount;
        if (amount > budgetRemaining) revert GrantAmountExceedsBudget(grantId, budgetId, amount, budgetRemaining);

        _validateMilestones(milestonePercentages);

        grantId = keccak256(abi.encode(recipient, amount, budgetId, block.timestamp, _grantCount));

        _grants[grantId] = Grant({
            id: grantId,
            budgetId: budgetId,
            recipient: recipient,
            totalAmount: amount,
            amountPaid: 0,
            milestoneCount: milestonePercentages.length,
            milestonesCompleted: 0,
            status: GrantStatus.PROPOSED,
            proposedAt: block.timestamp,
            approvedAt: 0,
            completedAt: 0,
            description: description,
            governanceProposalRef: bytes32(0)
        });

        _grantExists[grantId] = true;
        _allGrantIds.push(grantId);

        for (uint256 i = 0; i < milestonePercentages.length; i++) {
            _milestones[grantId].push(Milestone({
                description: "",
                percentage: milestonePercentages[i],
                completed: false,
                completedAt: 0
            }));
        }

        _budgetGrants[budgetId].push(grantId);
        _budgetGrantCount[budgetId]++;
        _recipientGrants[recipient].push(grantId);
        _recipientGrantCount[recipient]++;
        _grantCount++;

        emit GrantProposed(grantId, recipient, amount, budgetId);
    }

    function approveGrant(bytes32 grantId) external nonReentrant whenNotPaused onlyRole(GRANT_APPROVER_ROLE) {
        if (!_grantExists[grantId]) revert GrantNotFound(grantId);

        Grant storage grant = _grants[grantId];
        if (grant.status != GrantStatus.PROPOSED) revert GrantNotInState(grantId, GrantStatus.PROPOSED);

        grant.status = GrantStatus.APPROVED;
        grant.approvedAt = block.timestamp;

        emit GrantApproved(grantId, grant.recipient, grant.totalAmount);
    }

    function completeMilestone(bytes32 grantId, uint256 milestoneIndex) external nonReentrant whenNotPaused onlyRole(MILESTONE_VERIFIER_ROLE) {
        if (!_grantExists[grantId]) revert GrantNotFound(grantId);

        Grant storage grant = _grants[grantId];
        if (grant.status != GrantStatus.APPROVED && grant.status != GrantStatus.IN_PROGRESS && grant.status != GrantStatus.ALLOCATED) {
            revert GrantNotInState(grantId, GrantStatus.IN_PROGRESS);
        }

        if (milestoneIndex >= grant.milestoneCount) revert InvalidMilestoneConfig();

        Milestone storage milestone = _milestones[grantId][milestoneIndex];
        if (milestone.completed) revert MilestoneAlreadyCompleted(milestoneIndex);

        milestone.completed = true;
        milestone.completedAt = block.timestamp;
        grant.milestonesCompleted++;

        if (grant.status == GrantStatus.APPROVED) {
            grant.status = GrantStatus.IN_PROGRESS;
        }

        emit MilestoneCompleted(grantId, milestoneIndex, milestone.percentage);
    }

    function releasePayment(bytes32 grantId) external nonReentrant whenNotPaused onlyRole(GRANT_MANAGER_ROLE) returns (uint256) {
        if (!_grantExists[grantId]) revert GrantNotFound(grantId);

        Grant storage grant = _grants[grantId];
        if (grant.status == GrantStatus.PROPOSED) revert GrantNotInState(grantId, GrantStatus.APPROVED);
        if (grant.status == GrantStatus.CANCELLED) revert GrantAlreadyCancelled(grantId);

        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < grant.milestoneCount; i++) {
            if (_milestones[grantId][i].completed) {
                totalPercentage += _milestones[grantId][i].percentage;
            }
        }

        uint256 earnedAmount = (grant.totalAmount * totalPercentage) / 100;
        uint256 availablePayment = earnedAmount - grant.amountPaid;

        if (availablePayment == 0) revert("No payment available");

        if (grant.amountPaid == 0 && grant.status == GrantStatus.APPROVED) {
            grant.status = GrantStatus.ALLOCATED;
        }

        grant.amountPaid += availablePayment;

        budgetRegistry.spendFromBudget(grant.budgetId, availablePayment, grant.recipient, grantId);

        emit GrantPayment(grantId, grant.recipient, availablePayment);

        if (grant.amountPaid >= grant.totalAmount) {
            grant.status = GrantStatus.COMPLETED;
            grant.completedAt = block.timestamp;
            emit GrantCompleted(grantId, grant.recipient, grant.amountPaid);
        }

        return availablePayment;
    }

    function completeGrant(bytes32 grantId) external nonReentrant onlyRole(GRANT_MANAGER_ROLE) {
        if (!_grantExists[grantId]) revert GrantNotFound(grantId);

        Grant storage grant = _grants[grantId];
        if (grant.status == GrantStatus.COMPLETED) revert GrantAlreadyCompleted(grantId);
        if (grant.status == GrantStatus.CANCELLED) revert GrantAlreadyCancelled(grantId);

        grant.status = GrantStatus.COMPLETED;
        grant.completedAt = block.timestamp;

        emit GrantCompleted(grantId, grant.recipient, grant.amountPaid);
    }

    function cancelGrant(bytes32 grantId, string calldata reason) external nonReentrant onlyRole(GRANT_MANAGER_ROLE) {
        if (!_grantExists[grantId]) revert GrantNotFound(grantId);

        Grant storage grant = _grants[grantId];
        if (grant.status == GrantStatus.COMPLETED) revert GrantAlreadyCompleted(grantId);
        if (grant.status == GrantStatus.CANCELLED) revert GrantAlreadyCancelled(grantId);

        grant.status = GrantStatus.CANCELLED;

        emit GrantCancelled(grantId, reason);
    }

    function getGrant(bytes32 grantId) external view returns (Grant memory) {
        if (!_grantExists[grantId]) revert GrantNotFound(grantId);
        return _grants[grantId];
    }

    function getGrantMilestones(bytes32 grantId) external view returns (Milestone[] memory) {
        if (!_grantExists[grantId]) revert GrantNotFound(grantId);
        return _milestones[grantId];
    }

    function getGrantsForBudget(bytes32 budgetId) external view returns (bytes32[] memory) {
        return _budgetGrants[budgetId];
    }

    function getGrantsForRecipient(address recipient) external view returns (bytes32[] memory) {
        return _recipientGrants[recipient];
    }

    function getGrantCount() external view returns (uint256) {
        return _grantCount;
    }

    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    function _validateMilestones(uint256[] calldata milestonePercentages) internal pure {
        if (milestonePercentages.length == 0) revert InvalidMilestoneConfig();

        uint256 total = 0;
        for (uint256 i = 0; i < milestonePercentages.length; i++) {
            if (milestonePercentages[i] == 0) revert InvalidMilestoneConfig();
            total += milestonePercentages[i];
        }
        if (total != 100) revert InvalidMilestoneConfig();
    }
}
