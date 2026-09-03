// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IStakeCustody} from "./interfaces/IStakeCustody.sol";
import {IModuleRegistry} from "./interfaces/IModuleRegistry.sol";
import {IV2Module} from "./interfaces/IV2Module.sol";
import {IV2Types} from "./interfaces/IV2Types.sol";
import {V2Errors} from "./libraries/V2Errors.sol";

/// @title StakeVault
/// @notice Canonical V2 custody module with typed locks, exact-balance accounting, and pull-based withdrawals.
/// @dev Every token in custody belongs to a named bucket: claimable, locked (by category), or protocol allocation.
///      Only registered canonical modules may mutate locks. User withdrawals cannot affect another account or claim.
contract StakeVault is ERC165, AccessControl, ReentrancyGuard, IStakeCustody {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    bytes32 public constant MODULE_SLASHING = keccak256("SLASHING");
    bytes32 public constant MODULE_SETTLEMENT = keccak256("SETTLEMENT");
    bytes32 public constant MODULE_VERIFICATION = keccak256("VERIFICATION");

    IModuleRegistry public immutable moduleRegistry;
    IERC20 public immutable stakingToken;

    mapping(address => bool) public supportedAssets;
    mapping(address => bool) public lockMutators;

    mapping(address => uint256) private _totalCustody;
    mapping(address => uint256) private _protocolAllocation;
    mapping(address => uint256) private _assetTotalLocked;
    mapping(address => uint256) private _assetTotalClaimable;
    mapping(address => mapping(address => uint256)) private _claimable;
    mapping(bytes32 => uint256) private _locks;

    mapping(uint256 => uint256) private _claimTotalVerifierStake;
    mapping(uint256 => mapping(address => uint256)) private _accountClaimVerifierStake;

    event VaultDeposited(address indexed asset, address indexed account, uint256 amount);
    event VaultLocked(
        address indexed asset,
        address indexed account,
        uint256 indexed claimId,
        uint256 round,
        IV2Types.LockCategory category,
        uint256 amount
    );
    event VaultUnlocked(
        address indexed asset,
        address indexed account,
        uint256 indexed claimId,
        uint256 round,
        IV2Types.LockCategory category,
        uint256 amount
    );
    event VaultWithdrawn(address indexed asset, address indexed account, uint256 amount);
    event ProtocolAllocationIncreased(address indexed asset, uint256 amount, bytes32 indexed reason);

    /// @param registry Canonical module registry used to authorize lock mutations.
    /// @param token Primary staking asset for the `IStakeCustody` surface.
    /// @param admin Governance or deployment authority.
    constructor(address registry, address token, address admin) {
        if (registry == address(0) || token == address(0) || admin == address(0)) revert V2Errors.ZeroAddress();

        moduleRegistry = IModuleRegistry(registry);
        stakingToken = IERC20(token);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        supportedAssets[token] = true;
    }

    function protocolVersion() external pure override returns (uint16 major, uint16 minor) {
        return (2, 0);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IStakeCustody).interfaceId || interfaceId == type(IV2Module).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // IStakeCustody — verifier stake surface (primary asset, round 0)
    // -------------------------------------------------------------------------

    /// @inheritdoc IStakeCustody
    function depositStake(uint256 claimId, uint256 amount) external override nonReentrant {
        address asset = address(stakingToken);
        address account = msg.sender;
        _deposit(account, asset, amount);
        _lock(asset, account, claimId, 0, IV2Types.LockCategory.VERIFIER_PRINCIPAL, amount);
        emit StakeDeposited(account, claimId, amount);
    }

    /// @inheritdoc IStakeCustody
    function releaseStake(uint256 claimId, address account, uint256 amount) external override nonReentrant {
        _onlyAuthorizedMutator();
        address asset = address(stakingToken);
        _unlock(asset, account, claimId, 0, IV2Types.LockCategory.VERIFIER_PRINCIPAL, amount);
        emit StakeReleased(account, claimId, amount);
    }

    /// @inheritdoc IStakeCustody
    function slashStake(uint256 claimId, address account, uint256 amount, bytes32 reason) external override nonReentrant {
        _onlyAuthorizedMutator();
        address asset = address(stakingToken);
        _slash(asset, account, claimId, 0, IV2Types.LockCategory.VERIFIER_PRINCIPAL, amount, reason);
        emit StakeSlashed(account, claimId, amount, reason);
    }

    /// @inheritdoc IStakeCustody
    function staked(uint256 claimId, address account) external view override returns (uint256) {
        return _accountClaimVerifierStake[claimId][account];
    }

    /// @inheritdoc IStakeCustody
    function totalStaked(uint256 claimId) external view override returns (uint256) {
        return _claimTotalVerifierStake[claimId];
    }

    // -------------------------------------------------------------------------
    // Extended multi-asset custody API
    // -------------------------------------------------------------------------

    /// @notice Deposits a supported asset into the caller's claimable balance.
    function deposit(address asset, uint256 amount) external nonReentrant {
        _deposit(msg.sender, asset, amount);
    }

    /// @notice Locks claimable balance into a typed lock cell. Authorized modules only.
    function lock(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        IV2Types.LockCategory category,
        uint256 amount
    ) external nonReentrant {
        _onlyAuthorizedMutator();
        _lock(asset, account, claimId, round, category, amount);
    }

    /// @notice Unlocks a typed lock cell back to claimable balance. Authorized modules only.
    function unlock(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        IV2Types.LockCategory category,
        uint256 amount
    ) external nonReentrant {
        _onlyAuthorizedMutator();
        _unlock(asset, account, claimId, round, category, amount);
    }

    /// @notice Moves locked principal into protocol allocation. Authorized modules only.
    function allocateLocked(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        IV2Types.LockCategory category,
        uint256 amount,
        bytes32 reason
    ) external nonReentrant {
        _onlyAuthorizedMutator();
        _slash(asset, account, claimId, round, category, amount, reason);
    }

    /// @notice Pull-based withdrawal of the caller's claimable balance.
    function withdraw(address asset, uint256 amount) external nonReentrant {
        _withdraw(msg.sender, asset, amount);
    }

    // -------------------------------------------------------------------------
    // Reconciliation views
    // -------------------------------------------------------------------------

    /// @notice Total accounted custody for an asset.
    function totalCustody(address asset) external view returns (uint256) {
        return _totalCustody[asset];
    }

    /// @notice Locked principal for a specific lock cell.
    function lockedPrincipal(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        IV2Types.LockCategory category
    ) external view returns (uint256) {
        return _locks[_lockKey(asset, account, claimId, round, category)];
    }

    /// @notice Claimable (unlocked) balance for an account and asset.
    function claimableBalance(address asset, address account) external view returns (uint256) {
        return _claimable[asset][account];
    }

    /// @notice Protocol-owned allocation held in custody (e.g. slashed stake).
    function protocolAllocation(address asset) external view returns (uint256) {
        return _protocolAllocation[asset];
    }

    /// @notice Returns custody and total accounted obligations for reconciliation.
    function reconcile(address asset) external view returns (uint256 custody, uint256 obligations) {
        return _reconcile(asset);
    }

    // -------------------------------------------------------------------------
    // Administration
    // -------------------------------------------------------------------------

    /// @notice Enables or disables an asset for custody operations.
    function setSupportedAsset(address asset, bool enabled) external onlyRole(ADMIN_ROLE) {
        if (asset == address(0)) revert V2Errors.ZeroAddress();
        supportedAssets[asset] = enabled;
    }

    /// @notice Grants or revokes explicit lock-mutation authority (governance override).
    function setLockMutator(address module, bool enabled) external onlyRole(ADMIN_ROLE) {
        if (module == address(0)) revert V2Errors.ZeroAddress();
        lockMutators[module] = enabled;
    }

    /// @notice Returns whether an address may mutate locks.
    function isAuthorizedMutator(address caller) public view returns (bool) {
        if (lockMutators[caller]) return true;
        return _isRegisteredModule(caller, MODULE_SLASHING) || _isRegisteredModule(caller, MODULE_SETTLEMENT)
            || _isRegisteredModule(caller, MODULE_VERIFICATION);
    }

    // -------------------------------------------------------------------------
    // Internal accounting
    // -------------------------------------------------------------------------

    function _deposit(address account, address asset, uint256 amount) internal {
        if (amount == 0) revert V2Errors.ZeroAmount();
        if (!supportedAssets[asset]) revert V2Errors.UnsupportedAsset(asset);

        uint256 received = _transferIn(asset, account, amount);
        _claimable[asset][account] += received;
        _assetTotalClaimable[asset] += received;
        _totalCustody[asset] += received;

        _assertReconciliation(asset);
        emit VaultDeposited(asset, account, received);
    }

    function _lock(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        IV2Types.LockCategory category,
        uint256 amount
    ) internal {
        if (amount == 0) revert V2Errors.ZeroAmount();
        if (category == IV2Types.LockCategory.NONE) revert V2Errors.ZeroAmount();

        uint256 available = _claimable[asset][account];
        if (available < amount) revert V2Errors.InsufficientClaimable(account, amount, available);

        _claimable[asset][account] = available - amount;
        _assetTotalClaimable[asset] -= amount;

        bytes32 key = _lockKey(asset, account, claimId, round, category);
        _locks[key] += amount;
        _assetTotalLocked[asset] += amount;

        if (category == IV2Types.LockCategory.VERIFIER_PRINCIPAL && asset == address(stakingToken)) {
            _accountClaimVerifierStake[claimId][account] += amount;
            _claimTotalVerifierStake[claimId] += amount;
        }

        _assertReconciliation(asset);
        emit VaultLocked(asset, account, claimId, round, category, amount);
    }

    function _unlock(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        IV2Types.LockCategory category,
        uint256 amount
    ) internal {
        if (amount == 0) revert V2Errors.ZeroAmount();

        bytes32 key = _lockKey(asset, account, claimId, round, category);
        uint256 locked = _locks[key];
        if (locked < amount) revert V2Errors.InsufficientLocked(amount, locked);

        _locks[key] = locked - amount;
        _assetTotalLocked[asset] -= amount;
        _claimable[asset][account] += amount;
        _assetTotalClaimable[asset] += amount;

        if (category == IV2Types.LockCategory.VERIFIER_PRINCIPAL && asset == address(stakingToken)) {
            _accountClaimVerifierStake[claimId][account] -= amount;
            _claimTotalVerifierStake[claimId] -= amount;
        }

        _assertReconciliation(asset);
        emit VaultUnlocked(asset, account, claimId, round, category, amount);
    }

    function _slash(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        IV2Types.LockCategory category,
        uint256 amount,
        bytes32 reason
    ) internal {
        if (amount == 0) revert V2Errors.ZeroAmount();

        bytes32 key = _lockKey(asset, account, claimId, round, category);
        uint256 locked = _locks[key];
        if (locked < amount) revert V2Errors.InsufficientLocked(amount, locked);

        _locks[key] = locked - amount;
        _assetTotalLocked[asset] -= amount;
        _protocolAllocation[asset] += amount;

        if (category == IV2Types.LockCategory.VERIFIER_PRINCIPAL && asset == address(stakingToken)) {
            _accountClaimVerifierStake[claimId][account] -= amount;
            _claimTotalVerifierStake[claimId] -= amount;
        }

        _assertReconciliation(asset);
        emit ProtocolAllocationIncreased(asset, amount, reason);
    }

    function _withdraw(address account, address asset, uint256 amount) internal {
        if (amount == 0) revert V2Errors.ZeroAmount();

        uint256 available = _claimable[asset][account];
        if (available < amount) revert V2Errors.InsufficientClaimable(account, amount, available);

        _claimable[asset][account] = available - amount;
        _assetTotalClaimable[asset] -= amount;
        _totalCustody[asset] -= amount;

        IERC20(asset).safeTransfer(account, amount);

        _assertReconciliation(asset);
        emit VaultWithdrawn(asset, account, amount);
    }

    function _transferIn(address asset, address from, uint256 amount) internal returns (uint256 received) {
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransferFrom(from, address(this), amount);
        received = IERC20(asset).balanceOf(address(this)) - balanceBefore;
        if (received != amount) revert V2Errors.TransferAmountMismatch(amount, received);
    }

    function _lockKey(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        IV2Types.LockCategory category
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(asset, account, claimId, round, category));
    }

    function _onlyAuthorizedMutator() internal view {
        if (!isAuthorizedMutator(msg.sender)) revert V2Errors.UnauthorizedModule(msg.sender);
    }

    function _isRegisteredModule(address caller, bytes32 moduleId) internal view returns (bool) {
        if (!moduleRegistry.isRegistered(moduleId)) return false;
        (address implementation,,) = moduleRegistry.module(moduleId);
        return implementation == caller;
    }

    function _assertReconciliation(address asset) internal view {
        (uint256 custody, uint256 obligations) = _reconcile(asset);
        if (obligations > custody) revert V2Errors.ObligationsExceedCustody(asset, custody, obligations);
    }

    function _reconcile(address asset) internal view returns (uint256 custody, uint256 obligations) {
        custody = _totalCustody[asset];
        obligations = _protocolAllocation[asset] + _assetTotalLocked[asset] + _assetTotalClaimable[asset];
    }
}
