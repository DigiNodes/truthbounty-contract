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
 *      This is the legacy, level-based adapter. Canonical V2 modules use the
 *      operation-scoped control plane instead: inherit `EmergencyGuarded` and gate on a
 *      `V2Scopes` constant. See `docs/v2/emergency-controls.md`.
 *
 *      The modifier fails closed. A missing controller, an unreachable controller, a
 *      malformed response, and an unclassified operation identifier all block the call.
 *      When the controller reverts with its own diagnostic, that revert is bubbled up so
 *      `EmergencyController.UnknownOperation` reaches the caller unchanged.
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
     * @notice Reverts if the given operation type is unavailable.
     * @dev Fail closed: every failure mode blocks the guarded call.
     * @param operationType The operation to check (e.g. keccak256("claim_creation"))
     */
    modifier whenNotPaused(bytes32 operationType) {
        address controller = emergencyController;
        if (controller == address(0)) revert EmergencyControllerNotSet();

        (bool success, bytes memory data) = controller.staticcall(
            abi.encodeWithSignature("isOperationAllowed(bytes32)", operationType)
        );

        if (!success) {
            // Bubble the controller's own diagnostic — an unclassified operation reverts with
            // `UnknownOperation` rather than being treated as allowed.
            if (data.length != 0) {
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
            revert OperationPaused(operationType, _currentPauseLevel(controller));
        }

        if (data.length < 32 || !abi.decode(data, (bool))) {
            revert OperationPaused(operationType, _currentPauseLevel(controller));
        }

        _;
    }

    /// @dev Best-effort pause level for diagnostics; a failure reports level 0 rather than
    ///      weakening the block, which is already decided.
    function _currentPauseLevel(address controller) private view returns (uint8) {
        (bool ok, bytes memory data) = controller.staticcall(abi.encodeWithSignature("getPauseLevel()"));
        if (ok && data.length >= 32) {
            return abi.decode(data, (uint8));
        }
        return 0;
    }
}
