// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../treasury/ITreasuryAccounting.sol";

/**
 * @title MockTreasuryAccounting
 * @dev Lightweight test double for ITreasuryAccounting that records calls
 *      without enforcing token-flow invariants. Used by unit-test fixtures
 *      that deploy Staking but do not need real treasury accounting.
 */
contract MockTreasuryAccounting is ITreasuryAccounting {
    uint256 public stakingReserve;
    uint256 public slashedTreasury;
    uint256 public totalStakeRecorded;
    uint256 public totalUnstakeRecorded;
    uint256 public totalSlashRecorded;

    function recordStake(address user, uint256 amount) external {
        stakingReserve += amount;
        totalStakeRecorded += amount;
    }

    function recordUnstake(address user, uint256 amount) external {
        stakingReserve -= amount;
        totalUnstakeRecorded += amount;
    }

    function recordSlash(address verifier, uint256 amount) external {
        stakingReserve -= amount;
        slashedTreasury += amount;
        totalSlashRecorded += amount;
    }

    function depositToAccount(TreasuryAccount targetAccount, uint256 amount) external {}

    function recordRewardDistribution(address recipient, uint256 amount) external {}

    function transferBetweenAccounts(
        TreasuryAccount fromAccount,
        TreasuryAccount toAccount,
        uint256 amount,
        string calldata movementType
    ) external {}

    function getAccountBalance(TreasuryAccount account) external view returns (uint256) {
        if (account == TreasuryAccount.STAKING_RESERVE) return stakingReserve;
        if (account == TreasuryAccount.SLASHED_TREASURY) return slashedTreasury;
        return 0;
    }

    function getAccountBalances() external view returns (uint256[6] memory balances) {
        balances[uint256(TreasuryAccount.STAKING_RESERVE)] = stakingReserve;
        balances[uint256(TreasuryAccount.SLASHED_TREASURY)] = slashedTreasury;
    }

    function calculateTotalAssets() external view returns (uint256) {
        return stakingReserve + slashedTreasury;
    }
}
