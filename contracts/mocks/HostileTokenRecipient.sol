// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title HostileTokenRecipient
 * @notice ERC20 recipient that can reject transfers for denial-of-service regression tests.
 */
interface IHostileTokenRecipient {
    function onTransferReceived() external;
}

contract HostileTokenRecipient is IHostileTokenRecipient {
    bool public rejectTransfers = true;

    function setRejectTransfers(bool reject) external {
        rejectTransfers = reject;
    }

    function onTransferReceived() external view override {
        if (rejectTransfers) revert("HostileRecipient: reject");
    }
}

/**
 * @title HostileERC20
 * @notice Minimal ERC20 test token that invokes a recipient hook.
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
            IHostileTokenRecipient(to).onTransferReceived();
        }
        balanceOf[to] += amount;
        return true;
    }
}
