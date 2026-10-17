// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockGovernanceController
 * @notice Mock governance controller for testing purposes
 */
contract MockGovernanceController {
    address public admin;

    constructor(address _admin) {
        admin = _admin;
    }

    function setAdmin(address _admin) external {
        admin = _admin;
    }
}
