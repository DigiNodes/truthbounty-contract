// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ProtocolExecutionBounds} from "./ProtocolExecutionBounds.sol";

/**
 * @title PullSettlementLedger
 * @notice Pull-based settlement credits — recipient behavior cannot block other users (V2-SC-038).
 * @dev Treasury credits balances; each recipient withdraws independently. A hostile or reverting
 *      recipient only griefs their own withdrawal attempt, not global finalization.
 */
contract PullSettlementLedger is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant CREDITOR_ROLE = keccak256("CREDITOR_ROLE");

    IERC20 public immutable token;

    mapping(address => uint256) public credited;
    mapping(address => uint256) public withdrawn;

    event SettlementCredited(address indexed beneficiary, uint256 amount, bytes32 indexed settlementRef);
    event SettlementWithdrawn(address indexed beneficiary, uint256 amount);

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientCredit(uint256 available, uint256 requested);
    error BatchTooLarge(uint256 length, uint256 max);
    error LengthMismatch(uint256 a, uint256 b);

    constructor(address admin, IERC20 token_) {
        if (address(token_) == address(0)) revert ZeroAddress();
        token = token_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CREDITOR_ROLE, admin);
    }

    function credit(address beneficiary, uint256 amount, bytes32 settlementRef)
        external
        onlyRole(CREDITOR_ROLE)
    {
        if (beneficiary == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        credited[beneficiary] += amount;
        emit SettlementCredited(beneficiary, amount, settlementRef);
    }

    function creditBatch(
        address[] calldata beneficiaries,
        uint256[] calldata amounts,
        bytes32 settlementRef
    ) external onlyRole(CREDITOR_ROLE) {
        uint256 length = beneficiaries.length;
        if (length != amounts.length) revert LengthMismatch(length, amounts.length);
        if (length > ProtocolExecutionBounds.MAX_SETTLEMENT_BATCH_SIZE) {
            revert BatchTooLarge(length, ProtocolExecutionBounds.MAX_SETTLEMENT_BATCH_SIZE);
        }

        for (uint256 i = 0; i < length; ++i) {
            address beneficiary = beneficiaries[i];
            uint256 amount = amounts[i];
            if (beneficiary == address(0)) revert ZeroAddress();
            if (amount == 0) revert ZeroAmount();
            credited[beneficiary] += amount;
            emit SettlementCredited(beneficiary, amount, settlementRef);
        }
    }

    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 available = credited[msg.sender] - withdrawn[msg.sender];
        if (amount > available) revert InsufficientCredit(available, amount);

        withdrawn[msg.sender] += amount;
        token.safeTransfer(msg.sender, amount);
        emit SettlementWithdrawn(msg.sender, amount);
    }

    function availableBalance(address account) external view returns (uint256) {
        return credited[account] - withdrawn[account];
    }
}
