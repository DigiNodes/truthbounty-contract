// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MockGovernedModule
 * @dev Minimal governed module used in governor lifecycle tests.
 */
contract MockGovernedModule {
    uint256 public value;

    event ValueUpdated(uint256 newValue);

    function setValue(uint256 newValue) external {
        value = newValue;
        emit ValueUpdated(newValue);
    }

    function settleClaim(uint256 claimId) external {
        value = claimId;
    }
}
