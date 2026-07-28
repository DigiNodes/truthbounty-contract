// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGrantAllocation {
    enum GrantStatus { PROPOSED, APPROVED, ALLOCATED, IN_PROGRESS, COMPLETED, CANCELLED }

    struct Milestone {
        string description;
        uint256 percentage;
        bool completed;
        uint256 completedAt;
    }

    struct Grant {
        bytes32 id;
        bytes32 budgetId;
        address recipient;
        uint256 totalAmount;
        uint256 amountPaid;
        uint256 milestoneCount;
        uint256 milestonesCompleted;
        GrantStatus status;
        uint256 proposedAt;
        uint256 approvedAt;
        uint256 completedAt;
        string description;
        bytes32 governanceProposalRef;
    }

    event GrantProposed(bytes32 indexed grantId, address indexed recipient, uint256 amount, bytes32 indexed budgetId);
    event GrantApproved(bytes32 indexed grantId, address indexed recipient, uint256 amount);
    event GrantAllocated(bytes32 indexed grantId, bytes32 indexed budgetId, uint256 amount);
    event MilestoneCompleted(bytes32 indexed grantId, uint256 milestoneIndex, uint256 percentage);
    event GrantPayment(bytes32 indexed grantId, address indexed recipient, uint256 amount);
    event GrantCompleted(bytes32 indexed grantId, address indexed recipient, uint256 totalPaid);
    event GrantCancelled(bytes32 indexed grantId, string reason);

    error GrantNotFound(bytes32 grantId);
    error GrantNotInState(bytes32 grantId, GrantStatus expected);
    error InvalidRecipient();
    error InvalidMilestoneConfig();
    error MilestonePercentageOverflow();
    error MilestoneAlreadyCompleted(uint256 index);
    error GrantAmountExceedsBudget(bytes32 grantId, bytes32 budgetId, uint256 grantAmount, uint256 budgetRemaining);
    error GrantAlreadyCompleted(bytes32 grantId);
    error GrantAlreadyCancelled(bytes32 grantId);
    error ZeroAmount();
    error ZeroAddress();

    function proposeGrant(address recipient, uint256 amount, bytes32 budgetId, string calldata description, uint256[] calldata milestonePercentages) external returns (bytes32 grantId);
    function approveGrant(bytes32 grantId) external;
    function completeMilestone(bytes32 grantId, uint256 milestoneIndex) external;
    function releasePayment(bytes32 grantId) external returns (uint256);
    function completeGrant(bytes32 grantId) external;
    function cancelGrant(bytes32 grantId, string calldata reason) external;
    function getGrant(bytes32 grantId) external view returns (Grant memory);
    function getGrantMilestones(bytes32 grantId) external view returns (Milestone[] memory);
    function getGrantsForBudget(bytes32 budgetId) external view returns (bytes32[] memory);
    function getGrantsForRecipient(address recipient) external view returns (bytes32[] memory);
    function getGrantCount() external view returns (uint256);
}
