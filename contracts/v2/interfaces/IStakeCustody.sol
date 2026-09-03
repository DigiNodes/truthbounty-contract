// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IV2Module} from "./IV2Module.sol";
import {IV2Types} from "./IV2Types.sol";
interface IStakeCustody is IV2Module {
    event StakeDeposited(address indexed account, uint256 indexed claimId, uint256 amount);
    event StakeReleased(address indexed account, uint256 indexed claimId, uint256 amount);
    event StakeSlashed(address indexed account, uint256 indexed claimId, uint256 amount, bytes32 indexed reason);

    /// @notice Emitted when a conclusive settlement converts frozen principal into claimable principal and reward.
    event VaultSettledConclusive(
        address indexed asset,
        address indexed account,
        uint256 indexed claimId,
        uint256 round,
        uint256 principalAmount,
        uint256 rewardAmount
    );
    /// @notice Emitted when an inconclusive round refunds frozen principal back to the account.
    event VaultRefundedInconclusive(
        address indexed asset,
        address indexed account,
        uint256 indexed claimId,
        uint256 round,
        uint256 amount
    );
    /// @notice Emitted when an appeal carries a lock forward to the next round.
    event VaultCarriedForward(
        address indexed asset,
        address indexed account,
        uint256 indexed claimId,
        uint256 fromRound,
        uint256 toRound,
        uint256 amount
    );
    /// @notice Emitted when a round rolls a lock forward without settlement.
    event VaultRolledOver(
        address indexed asset,
        address indexed account,
        uint256 indexed claimId,
        uint256 fromRound,
        uint256 toRound,
        uint256 amount
    );
    /// @notice Emitted when a lock is finally unlocked to claimable balance.
    event VaultFinalUnlocked(
        address indexed asset,
        address indexed account,
        uint256 indexed claimId,
        uint256 round,
        uint256 amount
    );

    function depositStake(uint256 claimId, uint256 amount) external;
    function releaseStake(uint256 claimId, address account, uint256 amount) external;
    function slashStake(uint256 claimId, address account, uint256 amount, bytes32 reason) external;
    function staked(uint256 claimId, address account) external view returns (uint256);
    function totalStaked(uint256 claimId) external view returns (uint256);

    /// @notice Conclusive settlement: converts frozen verifier principal into claimable principal and reward.
    /// @dev Authorized to the SETTLEMENT module only. Idempotent per (claimId, round).
    function settleConclusive(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        uint256 principalAmount,
        uint256 rewardAmount
    ) external;

    /// @notice Inconclusive refund: converts frozen verifier principal back to claimable principal.
    /// @dev Authorized to the SETTLEMENT module only. Idempotent per (claimId, round).
    function refundInconclusive(address asset, address account, uint256 claimId, uint256 round, uint256 amount) external;

    /// @notice Appeal carry-forward: moves a lock from one round to the next for continued dispute.
    /// @dev Authorized to the SETTLEMENT module only. Idempotent per (claimId, fromRound).
    function carryForwardAppeal(
        address asset,
        address account,
        uint256 claimId,
        uint256 fromRound,
        uint256 toRound,
        uint256 amount
    ) external;

    /// @notice Round rollover: moves a lock to the next round without settlement.
    /// @dev Authorized to the SETTLEMENT module only. Idempotent per (claimId, fromRound).
    function rolloverRound(
        address asset,
        address account,
        uint256 claimId,
        uint256 fromRound,
        uint256 toRound,
        uint256 amount
    ) external;

    /// @notice Final unlock: releases remaining frozen lock to claimable balance.
    /// @dev Authorized to the SETTLEMENT module only. Idempotent per (claimId, round).
    function finalUnlock(address asset, address account, uint256 claimId, uint256 round, uint256 amount) external;

    /// @notice Returns the recorded settlement outcome for a claim-round, or NONE if not yet settled.
    function settlementOutcome(uint256 claimId, uint256 round) external view returns (IV2Types.SettlementOutcome);
}
