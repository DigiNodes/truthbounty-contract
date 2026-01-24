// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Lock is Ownable, Pausable {
    uint public unlockTime;
    address payable public lockOwner;

    event Withdrawal(uint amount, uint when);
    event EmergencyShutdown(address indexed by, uint timestamp);
    event ContractResumed(address indexed by, uint timestamp);

    constructor(uint _unlockTime) payable Ownable(msg.sender) {
        require(
            block.timestamp < _unlockTime,
            "Unlock time should be in the future"
        );

        unlockTime = _unlockTime;
    }

    function withdraw() public onlyOwner {
        // Uncomment this line, and the import of "hardhat/console.sol", to print a log in your terminal
        // console.log("Unlock time is %o and block timestamp is %o", unlockTime, block.timestamp);

        require(block.timestamp >= unlockTime, "You can't withdraw yet");

        emit Withdrawal(address(this).balance, block.timestamp);

        payable(owner()).transfer(address(this).balance);
    }

     /**
     * @notice Emergency pause - stops all withdrawals
     * @dev Only callable by contract owner
     */
    function pause() external onlyOwner {
        _pause();
        emit EmergencyShutdown(msg.sender, block.timestamp);
    }

    /**
     * @notice Resume normal operations
     * @dev Only callable by contract owner
     */
    function unpause() external onlyOwner {
        _unpause();
        emit ContractResumed(msg.sender, block.timestamp);
    }

    /**
     * @notice Emergency withdrawal for owner (only when paused)
     * @dev Allows recovery of funds during emergency
     */
    function emergencyWithdraw() external onlyOwner whenPaused {
        uint balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        
        emit Withdrawal(balance, block.timestamp);
        payable(owner()).transfer(balance);
    }

    /**
     * @notice Check if contract is currently paused
     */
    function isPaused() external view returns (bool) {
        return paused();
    }
}
