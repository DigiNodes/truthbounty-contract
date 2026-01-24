# Description

Closes #7

## Changes proposed

### What were you told to do?

I was tasked with working on **Multi-Claim Batching for Gas Efficiency** with the following requirements:

- Batch verification settlements to process multiple claims in a single transaction.
- Reduce per-claim gas costs compared to single calls.
- Implement loop safety checks to avoid out-of-gas errors.
- Ensure the solution is gas-aware and handles edge cases safely.

### What did I do?

**Implemented Batch Settlement Logic:**

- Created `contracts/TruthBountyClaims.sol` which handles both single and batched claim settlements.
- Implemented `settleClaimsBatch` function that accepts arrays of beneficiaries and amounts.
- set a `MAX_BATCH_SIZE` constant (200) to prevent block gas limit issues.

**Optimized Gas Usage:**

- Used `unchecked` arithmetic for loop increments to save gas.
- Cached array lengths in memory to avoid repeated storage/calldata reads.
- Verified gas savings: ~68k gas for a single claim vs ~49.5k per claim in a batch (approx 27% reduction).

**Ensured Security and Safety:**

- Added `ReentrancyGuard` to prevent reentrancy attacks.
- Inherited `Ownable` to restrict settlement access to the contract owner.
- Added checks for array length mismaatches and zero-address beneficiaries.

**Added Comprehensive Testing:**

- Created `test/TruthBountyClaims.test.ts` using Hardhat.
- Validated single and batch settlement success events.
- Tested failure scenarios (array mismatch, unauthorized access).
- Included a gas reporting test case to log comparison metrics.

## Check List (Check all the applicable boxes)

🚨Please review the contribution guideline for this repository.

- [x] My code follows the code style of this project.
- [x] This PR does not contain plagiarized content.
- [x] The title and description of the PR is clear and explains the approach.
- [x] I am making a pull request against the dev branch (left side).
- [x] My commit messages styles matches our requested structure.
- [x] My code additions will fail neither code linting checks nor unit test.
- [x] I am only making changes to files I was requested to.

## Screenshots/Videos

N/A (Smart Contract Implementation)
