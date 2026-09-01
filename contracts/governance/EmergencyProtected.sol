// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
        (bool success, bytes memory data) = emergencyController.staticcall(
            abi.encodeWithSignature("isOperationAllowed(bytes32)", operationType)
        );
        if (success && data.length >= 32) {
            bool allowed = abi.decode(data, (bool));
            if (!allowed) revert OperationPaused(operationType, 0);
        }
        // If the call fails, assume paused (fail-safe)
        else {
            revert OperationPaused(operationType, 0);
        }
        _;
    }
}
