# Treasury Budgeting & Grant Allocation Framework

## Overview

The Governance Treasury Budgeting & Grant Allocation Framework enables structured financial management for the TruthBounty DAO. It consists of two core contracts:

- **BudgetRegistry** — Manages treasury budgets with categories, spending limits, and governance controls
- **GrantAllocation** — Handles the full grant lifecycle from proposal to milestone-based payment

## Architecture

```
Governance
    |
    v
BudgetRegistry  <-->  GrantAllocation
    |                      |
    v                      v
Treasury Engine       Grant Recipients
```

Budget management is separated from Treasury Accounting. The Treasury executes approved allocations only after BudgetRegistry validation.

## Budget Registry

### Budget Structure

Each budget contains:
- Unique budget ID (bytes32)
- Category (enum: PROTOCOL_DEVELOPMENT, SECURITY, COMMUNITY, ECOSYSTEM, OPERATIONS, RESEARCH)
- Name (string)
- Approved amount
- Spent amount
- Created at timestamp
- Expiration date
- Governance proposal reference
- Status (ACTIVE, CLOSED, EXPIRED)

### Categories

Six predefined budget categories:

| Category | Description |
|---|---|
| PROTOCOL_DEVELOPMENT | Smart contracts, backend, frontend, infrastructure |
| SECURITY | Audits, bug bounty, emergency response |
| COMMUNITY | Ambassadors, education, events, documentation |
| ECOSYSTEM | Grants, hackathons, integrations, partnerships |
| OPERATIONS | Infrastructure, hosting, legal, compliance |
| RESEARCH | Protocol research, simulations, tokenomics, governance |

Categories are governance-configurable (annual limits, quarterly limits, enabled/disabled).

### Spending Constraints

- Budgets cannot exceed their approved amount
- Category annual limits prevent overspending per year
- Category quarterly limits prevent overspending per quarter
- Budgets expire after their configured duration
- Categories can be disabled by governance

## Grant Allocation

### Grant Lifecycle

```
Proposed -> Approved -> In Progress -> Allocated -> Completed
                                \              v
                                 +-> Cancelled
```

1. **Proposal** — Grant manager proposes a grant with milestone percentages (must sum to 100%)
2. **Approval** — Grant approver approves the proposal
3. **Milestones** — Milestone verifier marks milestones as completed
4. **Payment** — Grant manager releases proportional payment based on completed milestones
5. **Completion** — Grant auto-completes when full amount is paid

### Grant Structure

Each grant contains:
- Unique grant ID (bytes32)
- Budget ID reference
- Recipient address
- Total amount
- Amount paid
- Milestone tracking
- Status (PROPOSED, APPROVED, ALLOCATED, IN_PROGRESS, COMPLETED, CANCELLED)
- Governance proposal reference

## Treasury Integration

When `releasePayment` is called on GrantAllocation, it:
1. Validates the budget is active via BudgetRegistry
2. Ensures sufficient remaining budget
3. Calls `spendFromBudget` on the registry to record the expenditure
4. Returns the payment amount

This ensures all grant payments are validated against approved budgets before execution.

## Governance Controls

Both contracts use AccessControl roles:

### BudgetRegistry Roles
- `DEFAULT_ADMIN_ROLE` — Full administrative access
- `BUDGET_MANAGER_ROLE` — Create and close budgets, configure categories
- `BUDGET_ALLOCATOR_ROLE` — Allocate and spend from budgets
- `EMERGENCY_RESERVE_ROLE` — Manage emergency reserves
- `PAUSER_ROLE` — Emergency pause/unpause

### GrantAllocation Roles
- `DEFAULT_ADMIN_ROLE` — Full administrative access
- `GRANT_MANAGER_ROLE` — Propose grants, release payments, cancel grants
- `GRANT_APPROVER_ROLE` — Approve grant proposals
- `MILESTONE_VERIFIER_ROLE` — Verify and complete milestones
- `PAUSER_ROLE` — Emergency pause/unpause

## Events

### Budget Registry
- `BudgetCreated(bytes32 budgetId, BudgetCategory category, uint256 amount, string name)`
- `BudgetAllocated(bytes32 budgetId, uint256 amount, address allocator)`
- `BudgetSpent(bytes32 budgetId, uint256 amount, address recipient, bytes32 ref)`
- `BudgetClosed(bytes32 budgetId)`
- `BudgetExpired(bytes32 budgetId)`
- `CategoryLimitUpdated(BudgetCategory category, uint256 newAnnualLimit, uint256 newQuarterlyLimit)`
- `CategoryEnabled(BudgetCategory category, bool enabled)`
- `EmergencyReserveUpdated(uint256 oldReserve, uint256 newReserve)`

### Grant Allocation
- `GrantProposed(bytes32 grantId, address recipient, uint256 amount, bytes32 budgetId)`
- `GrantApproved(bytes32 grantId, address recipient, uint256 amount)`
- `GrantAllocated(bytes32 grantId, bytes32 budgetId, uint256 amount)`
- `MilestoneCompleted(bytes32 grantId, uint256 milestoneIndex, uint256 percentage)`
- `GrantPayment(bytes32 grantId, address recipient, uint256 amount)`
- `GrantCompleted(bytes32 grantId, address recipient, uint256 totalPaid)`
- `GrantCancelled(bytes32 grantId, string reason)`

## Financial Reporting

Read interfaces exposed:

### Budget Registry
- `getBudget(bytes32 budgetId)` — Full budget details
- `getActiveBudgets()` — List active budget IDs
- `getCategoryBudgets(BudgetCategory)` — Budgets in a category
- `getTotalAllocated()` — Sum of all approved amounts
- `getTotalSpent()` — Sum of all spent amounts
- `getCategoryUtilisation(BudgetCategory)` — Allocated, spent, remaining per category
- `getCategoryAnnualSpent(BudgetCategory)` — Year-to-date spending
- `getCategoryQuarterlySpent(BudgetCategory)` — Quarter-to-date spending
- `getGovernanceExpenditure()` — Total allocated and spent

### Grant Allocation
- `getGrant(bytes32 grantId)` — Full grant details
- `getGrantMilestones(bytes32 grantId)` — Milestone statuses
- `getGrantsForBudget(bytes32 budgetId)` — Grants under a budget
- `getGrantsForRecipient(address)` — Grants for an address
- `getGrantCount()` — Total grant count

## Security Considerations

- Unauthorised spending prevented by role-based access control
- Duplicate grant payments prevented by milestone completion tracking
- Budget overruns prevented by `InsufficientBudget` checks
- Treasury reconciliation ensured by `spendFromBudget` validation
- Governance abuse mitigated by multi-role separation
- Emergency pause stops all budget and grant activity

## Testing

Tests are located in `test/treasury/`:
- `BudgetRegistry.t.sol` — Unit tests for budget creation, allocation, spending, category limits, events
- `GrantAllocation.t.sol` — Unit tests for grant lifecycle, milestones, payments, events
- `test/fuzz/BudgetRegistry.fuzz.t.sol` — Fuzz tests with randomised inputs
- `test/invariant/BudgetRegistryInvariant.t.sol` — Invariant tests for accounting consistency

Run tests:
```bash
forge test --match-contract BudgetRegistryTest -vvv
forge test --match-contract GrantAllocationTest -vvv
forge test --match-contract BudgetRegistryFuzzTest -vvv
forge test --match-contract BudgetRegistryInvariant -vvv
```

## Deployment

Deploy BudgetRegistry first, then GrantAllocation:
```solidity
BudgetRegistry registry = new BudgetRegistry(admin);
GrantAllocation grants = new GrantAllocation(address(registry), admin);
```

Configure roles and grant the GrantAllocation contract BUDGET_ALLOCATOR_ROLE:

```solidity
registry.grantRole(registry.BUDGET_ALLOCATOR_ROLE(), address(grants));
```
