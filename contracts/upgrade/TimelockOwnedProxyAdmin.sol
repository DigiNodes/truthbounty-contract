// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "./StorageCompatibilityValidator.sol";

/**
 * @title TimelockOwnedProxyAdmin
 * @notice ProxyAdmin owned by a TimelockController that enforces the protocol's upgrade delays
 * @dev This contract extends OpenZeppelin's ProxyAdmin but restricts all upgrades to go through
 *      the timelock with the required 7-day delay. It also includes additional validation checks
 *      before allowing any upgrades to prevent unsafe implementations.
 */
contract TimelockOwnedProxyAdmin is ProxyAdmin {
    // 7-day upgrade delay as required
    uint256 public constant UPGRADE_DELAY = 7 days;
    
    // Mapping to track pending upgrades
    struct PendingUpgrade {
        address proxy;
        address implementation;
        bytes data;
        uint256 executeAfter;
        bool executed;
        bool cancelled;
    }
    
    mapping(bytes32 => PendingUpgrade) public pendingUpgrades;
    TimelockController public immutable timelock;
    StorageCompatibilityValidator public storageValidator;
    
    // Track all implementations that have ever been used to prevent reuse
    mapping(address => bool) public usedImplementations;
    
    event UpgradeScheduled(
        bytes32 indexed upgradeId,
        address indexed proxy,
        address indexed newImplementation,
        uint256 executeAfter
    );
    event UpgradeCancelled(bytes32 indexed upgradeId);
    event ImplementationValidated(address indexed implementation, bytes32 versionHash);
    event InvalidImplementationRejected(address indexed implementation, string reason);
    
    error ZeroAddress();
    error OnlyTimelock();
    error UpgradeNotScheduled();
    error TimelockNotElapsed();
    error UpgradeAlreadyExecuted();
    error UpgradeAlreadyCancelled();
    error InvalidImplementation(string reason);
    error ImplementationAlreadyUsed(address implementation);
    error EOANotAllowed(address account);
    
    modifier onlyTimelockController() {
        if (msg.sender != address(timelock)) revert OnlyTimelock();
        _;
    }
    
    constructor(address _timelock, address _storageValidator) ProxyAdmin(_timelock) {
        if (_timelock == address(0)) revert ZeroAddress();
        if (_storageValidator == address(0)) revert ZeroAddress();
        
        // Check that both are contracts, not EOAs
        if (_timelock.code.length == 0) revert EOANotAllowed(_timelock);
        if (_storageValidator.code.length == 0) revert EOANotAllowed(_storageValidator);
        
        timelock = TimelockController(payable(_timelock));
        storageValidator = StorageCompatibilityValidator(_storageValidator);
    }
    
    /**
     * @dev Schedule an upgrade to be executed after the timelock period
     * Can only be called by the timelock (which means it must go through governance)
     */
    function scheduleUpgrade(
        address proxy,
        address newImplementation,
        bytes calldata data
    ) external onlyTimelockController returns (bytes32 upgradeId) {
        // Validate the new implementation before scheduling
        _validateImplementation(proxy, newImplementation);
        
        upgradeId = keccak256(abi.encodePacked(proxy, newImplementation, block.timestamp));
        uint256 executeAfter = block.timestamp + UPGRADE_DELAY;
        
        pendingUpgrades[upgradeId] = PendingUpgrade({
            proxy: proxy,
            implementation: newImplementation,
            data: data,
            executeAfter: executeAfter,
            executed: false,
            cancelled: false
        });
        
        emit UpgradeScheduled(upgradeId, proxy, newImplementation, executeAfter);
    }
    
    /**
     * @dev Execute a scheduled upgrade after the timelock has elapsed
     */
    function executeUpgrade(bytes32 upgradeId) external {
        PendingUpgrade storage pending = pendingUpgrades[upgradeId];
        if (pending.proxy == address(0)) revert UpgradeNotScheduled();
        if (pending.executed) revert UpgradeAlreadyExecuted();
        if (pending.cancelled) revert UpgradeAlreadyCancelled();
        if (block.timestamp < pending.executeAfter) revert TimelockNotElapsed();
        
        pending.executed = true;
        
        // Perform the upgrade using ProxyAdmin's upgradeAndCall
        upgradeAndCall(
            ITransparentUpgradeableProxy(pending.proxy),
            pending.implementation,
            pending.data
        );
    }
    
    /**
     * @dev Cancel a pending upgrade
     * Can only be called by the timelock
     */
    function cancelUpgrade(bytes32 upgradeId) external onlyTimelockController {
        PendingUpgrade storage pending = pendingUpgrades[upgradeId];
        if (pending.proxy == address(0)) revert UpgradeNotScheduled();
        if (pending.executed) revert UpgradeAlreadyExecuted();
        if (pending.cancelled) revert UpgradeAlreadyCancelled();
        
        pending.cancelled = true;
        emit UpgradeCancelled(upgradeId);
    }
    
    /**
     * @dev Internal validation function to prevent unsafe upgrades
     */
    function _validateImplementation(address proxy, address newImplementation) internal {
        if (newImplementation == address(0)) revert ZeroAddress();
        
        // Check that it's a contract, not an EOA
        if (newImplementation.code.length == 0) {
            emit InvalidImplementationRejected(newImplementation, "Implementation is EOA");
            revert InvalidImplementation("Implementation is EOA");
        }
        
        // Check we're not reusing an implementation that's already been used anywhere
        if (usedImplementations[newImplementation]) {
            emit InvalidImplementationRejected(newImplementation, "Implementation already used");
            revert ImplementationAlreadyUsed(newImplementation);
        }
        
        // Validate storage compatibility using the storage validator
        try storageValidator.validateUpgrade(proxy, address(0), newImplementation) {
            // Storage layout is compatible
        } catch (bytes memory reason) {
            emit InvalidImplementationRejected(newImplementation, string(reason));
            revert InvalidImplementation(string(reason));
        }
        
        // Mark implementation as used to prevent future reuse
        usedImplementations[newImplementation] = true;
        
        emit ImplementationValidated(newImplementation, keccak256(bytes("1.0.0")));
    }
    
    // Storage gap for future upgrades
    uint256[50] private __gap;
}