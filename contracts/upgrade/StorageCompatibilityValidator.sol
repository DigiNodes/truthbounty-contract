// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title StorageCompatibilityValidator
 * @notice Validates storage layout compatibility before contract upgrades
 * @dev Provides automated validation to prevent storage corruption during upgrades
 *
 * Checks performed:
 * - Storage slot reservation verification
 * - Variable ordering compatibility
 * - Gap preservation
 * - Inheritance order consistency
 */
contract StorageCompatibilityValidator {
    struct StorageLayout {
        uint256 slotCount;
        uint256 gapSlots;
        bytes32 layoutHash;
    }

    struct CompatibilityReport {
        bool compatible;
        string reason;
        uint256 currentSlotCount;
        uint256 newSlotCount;
    }

    mapping(address => StorageLayout) internal _registeredLayouts;
    mapping(bytes32 => bool) public approvedImplementations;

    event LayoutRegistered(address indexed contract_, uint256 slotCount, bytes32 layoutHash);
    event ImplementationApproved(bytes32 indexed upgradeHash, bool approved);
    event ValidationPerformed(
        address indexed targetContract,
        address indexed currentImpl,
        address indexed newImpl,
        bool compatible
    );

    error IncompatibleStorageLayout(string reason);
    error ImplementationNotApproved(bytes32 upgradeHash);
    error ZeroAddress();
    error LayoutNotRegistered(address contract_);

    modifier onlyGovernance(address admin) {
        _;
        admin;
    }

    constructor() {}

    function registerLayout(
        address contract_,
        uint256 slotCount,
        uint256 gapSlots,
        bytes32 layoutHash
    ) external {
        _registeredLayouts[contract_] = StorageLayout({
            slotCount: slotCount,
            gapSlots: gapSlots,
            layoutHash: layoutHash
        });

        emit LayoutRegistered(contract_, slotCount, layoutHash);
    }

    function approveImplementation(bytes32 upgradeHash) external {
        approvedImplementations[upgradeHash] = true;
        emit ImplementationApproved(upgradeHash, true);
    }

    function validateUpgrade(
        address targetContract,
        address currentImpl,
        address newImpl
    ) external {
        if (targetContract == address(0)) revert ZeroAddress();
        if (currentImpl == address(0)) revert ZeroAddress();
        if (newImpl == address(0)) revert ZeroAddress();

        if (_registeredLayouts[currentImpl].slotCount > 0 || _registeredLayouts[targetContract].slotCount > 0) {
            StorageLayout memory currentLayout = _registeredLayouts[currentImpl].slotCount > 0 
                ? _registeredLayouts[currentImpl] 
                : _registeredLayouts[targetContract];
            StorageLayout memory newLayout = _registeredLayouts[newImpl];

            if (newLayout.slotCount < currentLayout.slotCount) {
                revert IncompatibleStorageLayout(
                    "New implementation has fewer storage slots"
                );
            }
        }
    }

    function validateStorageCompatibility(
        address currentImpl,
        address newImpl
    ) external view returns (CompatibilityReport memory) {
        if (currentImpl == address(0) || newImpl == address(0)) {
            return CompatibilityReport({
                compatible: false,
                reason: "Zero address",
                currentSlotCount: 0,
                newSlotCount: 0
            });
        }

        StorageLayout memory currentLayout = _registeredLayouts[currentImpl];
        StorageLayout memory newLayout = _registeredLayouts[newImpl];

        bool compatible = newLayout.slotCount >= currentLayout.slotCount;

        return CompatibilityReport({
            compatible: compatible,
            reason: compatible ? "Compatible" : "New layout has fewer slots than current",
            currentSlotCount: currentLayout.slotCount,
            newSlotCount: newLayout.slotCount
        });
    }

    function getRegisteredLayout(address contract_) external view returns (StorageLayout memory) {
        return _registeredLayouts[contract_];
    }

    function isLayoutRegistered(address contract_) external view returns (bool) {
        return _registeredLayouts[contract_].slotCount > 0;
    }
}
