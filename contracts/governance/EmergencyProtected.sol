// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BoundedStaticCall} from "../libraries/BoundedStaticCall.sol";

/**
 * @title EmergencyProtected
 * @notice Abstract contract providing a `whenNotPaused` modifier that queries
 *         the EmergencyController for the current pause level.
 * @dev Protocol modules should inherit this contract and apply the modifier
 *      to restricted functions. The EmergencyController address is set once
 *      during initialisation.
 *
 * Usage:
 *   contract ClaimRegistry is EmergencyProtected {
 *       function createClaim(...) external whenNotPaused(keccak256("claim_creation")) {
 *           // ...
 *       }
 *   }
 */
abstract contract EmergencyProtected {
    /// @notice The EmergencyController that owns the pause state
    address public emergencyController;

    error EmergencyControllerNotSet();
    error OperationPaused(bytes32 operationType, uint8 pauseLevel);

    /**
     * @notice Initialise the emergency controller reference.
     * @param _controller Address of the deployed EmergencyController
     */
    function _setEmergencyController(address _controller) internal {
        emergencyController = _controller;
    }

    /**
     * @notice Reverts if the given operation type is paused.
     * @param operationType The operation to check (e.g. keccak256("claim_creation"))
     */
    modifier whenNotPaused(bytes32 operationType) {
        if (emergencyController == address(0)) revert EmergencyControllerNotSet();
        (bool success, uint256 value, uint256 returnSize) = BoundedStaticCall.staticcallWord(
            emergencyController,
            abi.encodeWithSignature("isOperationAllowed(bytes32)", operationType)
        );
        if (success && returnSize >= 32 && value <= 1) {
            if (value == 0) revert OperationPaused(operationType, 0);
        }
        // If the call fails, assume paused (fail-safe)
        else {
            revert OperationPaused(operationType, 0);
        }
        _;
    }
}
