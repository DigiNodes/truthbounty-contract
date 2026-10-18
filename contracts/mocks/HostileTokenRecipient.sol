// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title HostileTokenRecipient
 * @notice ERC20 recipient that reverts on transfer for DoS regression tests.
 */
contract HostileTokenRecipient {
    bool public rejectTransfers = true;

    function setRejectTransfers(bool reject) external {
        rejectTransfers = reject;
    }

    function onTransferReceived() external view {
        if (rejectTransfers) revert("HostileRecipient: reject");
    }
}

/**
 * @title HostileERC20
 * @notice Minimal ERC20 that invokes recipient hook and can revert on hostile addresses.
 */
contract HostileERC20 {
    string public name = "Hostile";
    string public symbol = "HOST";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        if (to.code.length > 0) {
            HostileTokenRecipient(to).onTransferReceived();
        }
        balanceOf[to] += amount;
        return true;
    }
}
