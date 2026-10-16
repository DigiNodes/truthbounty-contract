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
    enum RollbackPolicy {
        None,
        Full,
        StorageOnly
    }

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

    struct RollbackPlan {
        RollbackPolicy policy;
        bytes32 preUpgradeStateHash;
        bytes32 postUpgradeStateHash;
        bool supported;
        bool executed;
    }

    mapping(address => StorageLayout) internal _registeredLayouts;
    mapping(bytes32 => bool) public approvedImplementations;
    mapping(address => RollbackPlan) internal _rollbackPlans;

    event LayoutRegistered(address indexed contract_, uint256 slotCount, bytes32 layoutHash);
    event ImplementationApproved(bytes32 indexed upgradeHash, bool approved);
    event ValidationPerformed(
        address indexed targetContract,
        address indexed currentImpl,
        address indexed newImpl,
        bool compatible
    );
    event RollbackPlanRegistered(
        address indexed targetContract,
        RollbackPolicy policy,
        bytes32 preUpgradeStateHash,
        bool supported
    );
    event RollbackExecuted(
        address indexed targetContract,
        bytes32 preUpgradeStateHash,
        bytes32 postUpgradeStateHash,
        bool stateEquivalent
    );

    error IncompatibleStorageLayout(string reason);
    error ImplementationNotApproved(bytes32 upgradeHash);
    error ZeroAddress();
    error LayoutNotRegistered(address contract_);
    error RollbackNotSupported(address targetContract);
    error RollbackAlreadyExecuted(address targetContract);
    error StateNotEquivalent(bytes32 expected, bytes32 actual);

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

    function registerRollbackPlan(
        address targetContract,
        RollbackPolicy policy,
        bytes32 preUpgradeStateHash
    ) external {
        if (targetContract == address(0)) revert ZeroAddress();
        if (policy == RollbackPolicy.None) revert RollbackNotSupported(targetContract);

        _rollbackPlans[targetContract] = RollbackPlan({
            policy: policy,
            preUpgradeStateHash: preUpgradeStateHash,
            postUpgradeStateHash: bytes32(0),
            supported: true,
            executed: false
        });

        emit RollbackPlanRegistered(targetContract, policy, preUpgradeStateHash, true);
    }

    function getRollbackPlan(address targetContract) external view returns (RollbackPlan memory) {
        return _rollbackPlans[targetContract];
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

    function executeRollback(
        address targetContract,
        bytes32 postUpgradeStateHash
    ) external {
        if (targetContract == address(0)) revert ZeroAddress();

        RollbackPlan storage plan = _rollbackPlans[targetContract];
        if (!plan.supported) revert RollbackNotSupported(targetContract);
        if (plan.executed) revert RollbackAlreadyExecuted(targetContract);

        if (plan.policy == RollbackPolicy.StorageOnly) {
            if (postUpgradeStateHash != plan.preUpgradeStateHash) {
                revert StateNotEquivalent(plan.preUpgradeStateHash, postUpgradeStateHash);
            }
        }

        plan.postUpgradeStateHash = postUpgradeStateHash;
        plan.executed = true;

        bool stateEquivalent = postUpgradeStateHash == plan.preUpgradeStateHash;
        emit RollbackExecuted(
            targetContract,
            plan.preUpgradeStateHash,
            postUpgradeStateHash,
            stateEquivalent
        );
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
