// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ITreasuryAccounting
 * @dev Interface for the TreasuryAccounting contract that defines all external functions
 *      used by other protocol contracts (staking, rewards, slashing)
 */
interface ITreasuryAccounting {
    // ============ ENUMS ============
    
    enum TreasuryAccount {
        STAKING_RESERVE,      // Tokens actively staked by users
        REWARDS_POOL,         // Reserved for reward distribution
        PROTOCOL_FEES,        // Accumulated protocol fees
        GOVERNANCE_RESERVES,  // Governance-controlled reserve fund
        ECOSYSTEM_FUND,       // Future ecosystem development fund
        SLASHED_TREASURY      // Tokens slashed from verifiers
    }

    // ============ STRUCTS ============

    struct TokenMovement {
        uint256 timestamp;
        address from;
        address to;
        uint256 amount;
        TreasuryAccount fromAccount;
        TreasuryAccount toAccount;
        string movementType;
        bytes32 transactionId;
    }

    struct AccountSnapshot {
        uint256 timestamp;
        uint256 blockNumber;
        uint256[6] balances;
        uint256 totalAssets;
        address snapshotSender;
    }

    // ============ EXTERNAL FUNCTIONS USED BY PROTOCOL CONTRACTS ============

    /**
     * @dev Deposit tokens from external sources into a specific treasury account
     * @param targetAccount The treasury account to credit
     * @param amount Amount of tokens to deposit
     */
    function depositToAccount(TreasuryAccount targetAccount, uint256 amount) external;

    /**
     * @dev Record a user staking tokens into the staking reserve
     * @param user The user address that staked
     * @param amount The amount staked
     */
    function recordStake(address user, uint256 amount) external;

    /**
     * @dev Record a user unstaking tokens from the staking reserve
     * @param user The user address that unstaked
     * @param amount The amount unstaked
     */
    function recordUnstake(address user, uint256 amount) external;

    /**
     * @dev Record a slashing event moving funds from staking to slashed treasury
     * @param verifier The verifier address that was slashed
     * @param amount The amount slashed
     */
    function recordSlash(address verifier, uint256 amount) external;

    /**
     * @dev Record reward distribution from the rewards pool
     * @param recipient The address receiving the reward
     * @param amount The reward amount
     */
    function recordRewardDistribution(address recipient, uint256 amount) external;

    /**
     * @dev Transfer funds between internal treasury accounts
     * @param fromAccount Source account
     * @param toAccount Target account
     * @param amount Amount to transfer
     * @param movementType Description of the movement
     */
    function transferBetweenAccounts(
        TreasuryAccount fromAccount,
        TreasuryAccount toAccount,
        uint256 amount,
        string calldata movementType
    ) external;

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Get the balance of a specific treasury account
     */
    function getAccountBalance(TreasuryAccount account) external view returns (uint256);

    /**
     * @dev Get all account balances
     */
    function getAccountBalances() external view returns (uint256[6] memory);

    /**
     * @dev Calculate total assets across all accounts
     */
    function calculateTotalAssets() external view returns (uint256);

    // ============ EVENTS ============

    event FundsTransferred(
        bytes32 indexed transactionId,
        TreasuryAccount fromAccount,
        TreasuryAccount toAccount,
        uint256 amount,
        address indexed operator,
        string movementType
    );

    event ExternalDeposit(
        bytes32 indexed transactionId,
        TreasuryAccount targetAccount,
        uint256 amount,
        address indexed depositor
    );

    event ExternalWithdrawal(
        bytes32 indexed transactionId,
        TreasuryAccount sourceAccount,
        uint256 amount,
        address indexed recipient,
        address indexed operator
    );

    event AccountSnapshotCreated(
        uint256 indexed snapshotIndex,
        uint256 timestamp,
        uint256 totalAssets,
        address indexed snapshotter
    );
}