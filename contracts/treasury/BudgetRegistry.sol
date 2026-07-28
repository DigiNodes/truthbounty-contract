// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IBudgetRegistry.sol";
import "../governance/GovernanceHooks.sol";

contract BudgetRegistry is IBudgetRegistry, AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant BUDGET_MANAGER_ROLE = keccak256("BUDGET_MANAGER_ROLE");
    bytes32 public constant BUDGET_ALLOCATOR_ROLE = keccak256("BUDGET_ALLOCATOR_ROLE");
    bytes32 public constant EMERGENCY_RESERVE_ROLE = keccak256("EMERGENCY_RESERVE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant MIN_BUDGET_DURATION = 1 days;
    uint256 public constant MAX_BUDGET_DURATION = 365 days;
    uint256 public constant ONE_YEAR = 365 days;
    uint256 public constant QUARTER = 91 days;

    uint256 private _emergencyReserve;
    uint256 private _budgetCount;

    mapping(bytes32 => Budget) private _budgets;
    mapping(bytes32 => bool) private _budgetExists;
    bytes32[] private _activeBudgetIds;
    mapping(bytes32 => bool) private _isActiveBudget;

    mapping(BudgetCategory => CategoryConfig) private _categoryConfigs;
    mapping(BudgetCategory => bytes32[]) private _categoryBudgetIds;

    mapping(BudgetCategory => uint256) private _categoryAnnualSpentCache;
    mapping(BudgetCategory => uint256) private _categoryAnnualSpentYear;
    mapping(BudgetCategory => uint256) private _categoryQuarterlySpentCache;
    mapping(BudgetCategory => uint256) private _categoryQuarterlySpentQuarter;

    uint256 private _totalAllocated;
    uint256 private _totalSpent;

    constructor(address admin) {
        require(admin != address(0), ZeroAddress());

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(BUDGET_MANAGER_ROLE, admin);
        _grantRole(BUDGET_ALLOCATOR_ROLE, admin);
        _grantRole(EMERGENCY_RESERVE_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        _setRoleAdmin(BUDGET_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(BUDGET_ALLOCATOR_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(EMERGENCY_RESERVE_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, DEFAULT_ADMIN_ROLE);

        _categoryConfigs[BudgetCategory.PROTOCOL_DEVELOPMENT] = CategoryConfig({ annualLimit: type(uint256).max, quarterlyLimit: type(uint256).max, enabled: true });
        _categoryConfigs[BudgetCategory.SECURITY] = CategoryConfig({ annualLimit: type(uint256).max, quarterlyLimit: type(uint256).max, enabled: true });
        _categoryConfigs[BudgetCategory.COMMUNITY] = CategoryConfig({ annualLimit: type(uint256).max, quarterlyLimit: type(uint256).max, enabled: true });
        _categoryConfigs[BudgetCategory.ECOSYSTEM] = CategoryConfig({ annualLimit: type(uint256).max, quarterlyLimit: type(uint256).max, enabled: true });
        _categoryConfigs[BudgetCategory.OPERATIONS] = CategoryConfig({ annualLimit: type(uint256).max, quarterlyLimit: type(uint256).max, enabled: true });
        _categoryConfigs[BudgetCategory.RESEARCH] = CategoryConfig({ annualLimit: type(uint256).max, quarterlyLimit: type(uint256).max, enabled: true });
    }

    function createBudget(
        BudgetCategory category,
        uint256 amount,
        uint256 duration,
        string calldata name,
        bytes32 governanceProposalRef
    ) external nonReentrant whenNotPaused onlyRole(BUDGET_MANAGER_ROLE) returns (bytes32 budgetId) {
        if (amount == 0) revert ZeroAmount();
        if (duration < MIN_BUDGET_DURATION || duration > MAX_BUDGET_DURATION) revert InvalidExpiration();
        if (bytes(name).length == 0) revert BudgetNameEmpty();
        if (!_categoryConfigs[category].enabled) revert CategoryNotEnabled(category);

        budgetId = keccak256(abi.encode(category, name, amount, block.timestamp, _budgetCount));

        _budgets[budgetId] = Budget({
            id: budgetId,
            category: category,
            name: name,
            approvedAmount: amount,
            spentAmount: 0,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            governanceProposalRef: governanceProposalRef,
            status: BudgetStatus.ACTIVE
        });

        _budgetExists[budgetId] = true;
        _activeBudgetIds.push(budgetId);
        _isActiveBudget[budgetId] = true;
        _categoryBudgetIds[category].push(budgetId);
        _budgetCount++;

        _totalAllocated += amount;

        emit BudgetCreated(budgetId, category, amount, name);
    }

    function allocateBudget(bytes32 budgetId, uint256 amount) external nonReentrant whenNotPaused onlyRole(BUDGET_ALLOCATOR_ROLE) {
        if (amount == 0) revert ZeroAmount();
        if (!_budgetExists[budgetId]) revert BudgetNotFound(budgetId);

        Budget storage budget = _budgets[budgetId];
        if (budget.status != BudgetStatus.ACTIVE) revert BudgetAlreadyClosed(budgetId);
        if (block.timestamp >= budget.expiresAt) {
            _expireBudget(budgetId);
            revert BudgetExpiredError(budgetId);
        }

        uint256 available = budget.approvedAmount - budget.spentAmount;
        if (amount > available) revert InsufficientBudget(budgetId, amount, available);

        CategoryConfig memory config = _categoryConfigs[budget.category];
        if (!config.enabled) revert CategoryNotEnabled(budget.category);

        _checkCategoryLimits(budget.category, amount);

        budget.spentAmount += amount;

        _totalSpent += amount;

        emit BudgetAllocated(budgetId, amount, msg.sender);
    }

    function spendFromBudget(
        bytes32 budgetId,
        uint256 amount,
        address recipient,
        bytes32 ref
    ) external nonReentrant whenNotPaused onlyRole(BUDGET_ALLOCATOR_ROLE) returns (bool) {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (!_budgetExists[budgetId]) revert BudgetNotFound(budgetId);

        Budget storage budget = _budgets[budgetId];
        if (budget.status != BudgetStatus.ACTIVE) revert BudgetAlreadyClosed(budgetId);
        if (block.timestamp >= budget.expiresAt) {
            _expireBudget(budgetId);
            revert BudgetExpiredError(budgetId);
        }

        uint256 available = budget.approvedAmount - budget.spentAmount;
        if (amount > available) revert InsufficientBudget(budgetId, amount, available);

        CategoryConfig memory config = _categoryConfigs[budget.category];
        if (!config.enabled) revert CategoryNotEnabled(budget.category);

        _checkCategoryLimits(budget.category, amount);

        budget.spentAmount += amount;

        _totalSpent += amount;

        emit BudgetSpent(budgetId, amount, recipient, ref);
        return true;
    }

    function closeBudget(bytes32 budgetId) external nonReentrant onlyRole(BUDGET_MANAGER_ROLE) {
        if (!_budgetExists[budgetId]) revert BudgetNotFound(budgetId);

        Budget storage budget = _budgets[budgetId];
        if (budget.status != BudgetStatus.ACTIVE) revert BudgetAlreadyClosed(budgetId);

        budget.status = BudgetStatus.CLOSED;

        if (_isActiveBudget[budgetId]) {
            _isActiveBudget[budgetId] = false;
        }

        emit BudgetClosed(budgetId);
    }

    function setCategoryConfig(
        BudgetCategory category,
        uint256 annualLimit,
        uint256 quarterlyLimit,
        bool enabled
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _categoryConfigs[category] = CategoryConfig({
            annualLimit: annualLimit,
            quarterlyLimit: quarterlyLimit,
            enabled: enabled
        });
        emit CategoryLimitUpdated(category, annualLimit, quarterlyLimit);
        emit CategoryEnabled(category, enabled);
    }

    function setEmergencyReserve(uint256 newReserve) external onlyRole(EMERGENCY_RESERVE_ROLE) {
        uint256 oldReserve = _emergencyReserve;
        _emergencyReserve = newReserve;
        emit EmergencyReserveUpdated(oldReserve, newReserve);
    }

    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    function getBudget(bytes32 budgetId) external view returns (Budget memory) {
        if (!_budgetExists[budgetId]) revert BudgetNotFound(budgetId);
        return _budgets[budgetId];
    }

    function getActiveBudgets() external view returns (bytes32[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < _activeBudgetIds.length; i++) {
            if (_isActiveBudget[_activeBudgetIds[i]]) {
                count++;
            }
        }

        bytes32[] memory result = new bytes32[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < _activeBudgetIds.length; i++) {
            if (_isActiveBudget[_activeBudgetIds[i]]) {
                result[idx] = _activeBudgetIds[i];
                idx++;
            }
        }
        return result;
    }

    function getCategoryBudgets(BudgetCategory category) external view returns (bytes32[] memory) {
        return _categoryBudgetIds[category];
    }

    function getBudgetCount() external view returns (uint256) {
        return _budgetCount;
    }

    function getCategoryConfig(BudgetCategory category) external view returns (CategoryConfig memory) {
        return _categoryConfigs[category];
    }

    function getTotalAllocated() external view returns (uint256) {
        return _totalAllocated;
    }

    function getTotalSpent() external view returns (uint256) {
        return _totalSpent;
    }

    function getCategoryUtilisation(BudgetCategory category) external view returns (uint256 allocated, uint256 spent, uint256 remaining) {
        bytes32[] storage budgetIds = _categoryBudgetIds[category];
        for (uint256 i = 0; i < budgetIds.length; i++) {
            Budget storage b = _budgets[budgetIds[i]];
            allocated += b.approvedAmount;
            spent += b.spentAmount;
        }
        remaining = allocated - spent;
    }

    function getCategoryAnnualSpent(BudgetCategory category) external view returns (uint256) {
        uint256 currentYear = block.timestamp / ONE_YEAR;
        if (_categoryAnnualSpentYear[category] == currentYear) {
            return _categoryAnnualSpentCache[category];
        }
        return _computeCategoryAnnualSpent(category);
    }

    function getCategoryQuarterlySpent(BudgetCategory category) external view returns (uint256) {
        uint256 currentQuarter = block.timestamp / QUARTER;
        if (_categoryQuarterlySpentQuarter[category] == currentQuarter) {
            return _categoryQuarterlySpentCache[category];
        }
        return _computeCategoryQuarterlySpent(category);
    }

    function getEmergencyReserve() external view returns (uint256) {
        return _emergencyReserve;
    }

    function getGovernanceExpenditure() external view returns (uint256 totalAllocated, uint256 totalSpent) {
        return (_totalAllocated, _totalSpent);
    }

    function _checkCategoryLimits(BudgetCategory category, uint256 amount) internal {
        uint256 currentYear = block.timestamp / ONE_YEAR;
        uint256 currentQuarter = block.timestamp / QUARTER;

        if (_categoryAnnualSpentYear[category] != currentYear) {
            _categoryAnnualSpentYear[category] = currentYear;
            _categoryAnnualSpentCache[category] = 0;
        }

        if (_categoryQuarterlySpentQuarter[category] != currentQuarter) {
            _categoryQuarterlySpentQuarter[category] = currentQuarter;
            _categoryQuarterlySpentCache[category] = 0;
        }

        CategoryConfig memory config = _categoryConfigs[category];

        uint256 newAnnual = _categoryAnnualSpentCache[category] + amount;
        if (newAnnual > config.annualLimit) revert AnnualLimitExceeded(category, newAnnual, config.annualLimit);

        uint256 newQuarterly = _categoryQuarterlySpentCache[category] + amount;
        if (newQuarterly > config.quarterlyLimit) revert QuarterlyLimitExceeded(category, newQuarterly, config.quarterlyLimit);

        _categoryAnnualSpentCache[category] = newAnnual;
        _categoryQuarterlySpentCache[category] = newQuarterly;
    }

    function _computeCategoryAnnualSpent(BudgetCategory category) internal view returns (uint256) {
        uint256 yearStart = (block.timestamp / ONE_YEAR) * ONE_YEAR;
        uint256 total = 0;
        bytes32[] storage budgetIds = _categoryBudgetIds[category];
        for (uint256 i = 0; i < budgetIds.length; i++) {
            Budget storage b = _budgets[budgetIds[i]];
            if (b.createdAt >= yearStart) {
                total += b.spentAmount;
            }
        }
        return total;
    }

    function _computeCategoryQuarterlySpent(BudgetCategory category) internal view returns (uint256) {
        uint256 quarterStart = (block.timestamp / QUARTER) * QUARTER;
        uint256 total = 0;
        bytes32[] storage budgetIds = _categoryBudgetIds[category];
        for (uint256 i = 0; i < budgetIds.length; i++) {
            Budget storage b = _budgets[budgetIds[i]];
            if (b.createdAt >= quarterStart) {
                total += b.spentAmount;
            }
        }
        return total;
    }

    function _expireBudget(bytes32 budgetId) internal {
        Budget storage budget = _budgets[budgetId];
        if (budget.status == BudgetStatus.ACTIVE) {
            budget.status = BudgetStatus.EXPIRED;
            if (_isActiveBudget[budgetId]) {
                _isActiveBudget[budgetId] = false;
            }
            emit BudgetExpired(budgetId);
        }
    }
}
