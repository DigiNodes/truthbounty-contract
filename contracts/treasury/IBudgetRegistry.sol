// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBudgetRegistry {
    enum BudgetCategory {
        PROTOCOL_DEVELOPMENT,
        SECURITY,
        COMMUNITY,
        ECOSYSTEM,
        OPERATIONS,
        RESEARCH
    }

    enum BudgetStatus { ACTIVE, CLOSED, EXPIRED }

    struct Budget {
        bytes32 id;
        BudgetCategory category;
        string name;
        uint256 approvedAmount;
        uint256 spentAmount;
        uint256 createdAt;
        uint256 expiresAt;
        bytes32 governanceProposalRef;
        BudgetStatus status;
    }

    struct CategoryConfig {
        uint256 annualLimit;
        uint256 quarterlyLimit;
        bool enabled;
    }

    event BudgetCreated(bytes32 indexed budgetId, BudgetCategory indexed category, uint256 amount, string name);
    event BudgetAllocated(bytes32 indexed budgetId, uint256 amount, address indexed allocator);
    event BudgetSpent(bytes32 indexed budgetId, uint256 amount, address indexed recipient, bytes32 ref);
    event BudgetClosed(bytes32 indexed budgetId);
    event BudgetExpired(bytes32 indexed budgetId);
    event CategoryLimitUpdated(BudgetCategory indexed category, uint256 newAnnualLimit, uint256 newQuarterlyLimit);
    event CategoryEnabled(BudgetCategory indexed category, bool enabled);
    event EmergencyReserveUpdated(uint256 oldReserve, uint256 newReserve);
    event GovernanceProposalRefUpdated(bytes32 indexed budgetId, bytes32 newRef);

    error BudgetNotFound(bytes32 budgetId);
    error BudgetAlreadyClosed(bytes32 budgetId);
    error BudgetExpiredError(bytes32 budgetId);
    error InsufficientBudget(bytes32 budgetId, uint256 requested, uint256 available);
    error CategoryNotEnabled(BudgetCategory category);
    error CategoryLimitExceeded(BudgetCategory category, uint256 amount);
    error AnnualLimitExceeded(BudgetCategory category, uint256 annualSpent, uint256 limit);
    error QuarterlyLimitExceeded(BudgetCategory category, uint256 quarterlySpent, uint256 limit);
    error EmergencyReserveTooLow(uint256 requested, uint256 reserve);
    error ZeroAmount();
    error ZeroAddress();
    error UnauthorizedCaller(address caller);
    error InvalidExpiration();
    error BudgetNameEmpty();

    function createBudget(BudgetCategory category, uint256 amount, uint256 duration, string calldata name, bytes32 governanceProposalRef) external returns (bytes32 budgetId);
    function allocateBudget(bytes32 budgetId, uint256 amount) external;
    function spendFromBudget(bytes32 budgetId, uint256 amount, address recipient, bytes32 ref) external returns (bool);
    function closeBudget(bytes32 budgetId) external;
    function setCategoryConfig(BudgetCategory category, uint256 annualLimit, uint256 quarterlyLimit, bool enabled) external;
    function setEmergencyReserve(uint256 newReserve) external;
    function getBudget(bytes32 budgetId) external view returns (Budget memory);
    function getActiveBudgets() external view returns (bytes32[] memory);
    function getCategoryBudgets(BudgetCategory category) external view returns (bytes32[] memory);
    function getBudgetCount() external view returns (uint256);
    function getCategoryConfig(BudgetCategory category) external view returns (CategoryConfig memory);
    function getTotalAllocated() external view returns (uint256);
    function getTotalSpent() external view returns (uint256);
    function getCategoryUtilisation(BudgetCategory category) external view returns (uint256 allocated, uint256 spent, uint256 remaining);
    function getCategoryAnnualSpent(BudgetCategory category) external view returns (uint256);
    function getCategoryQuarterlySpent(BudgetCategory category) external view returns (uint256);
    function getEmergencyReserve() external view returns (uint256);
    function getGovernanceExpenditure() external view returns (uint256 totalAllocated, uint256 totalSpent);
}
