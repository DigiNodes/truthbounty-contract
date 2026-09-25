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

    /// @notice Administrative role allowed to configure supported assets and explicit lock mutators.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Module identifier authorized to slash locked stake.
    bytes32 public constant MODULE_SLASHING = keccak256("SLASHING");
    /// @notice Module identifier authorized to execute settlement hooks.
    bytes32 public constant MODULE_SETTLEMENT = keccak256("SETTLEMENT");
    /// @notice Module identifier authorized to manage verification stake.
    bytes32 public constant MODULE_VERIFICATION = keccak256("VERIFICATION");

    /// @notice Registry queried to resolve registry-derived module authority; registry failure denies only that authority, not authority granted through explicit `lockMutators`.
    IModuleRegistry public immutable moduleRegistry;
    /// @notice Primary ERC-20 asset used by the `IStakeCustody` verifier-stake surface.
    IERC20 public immutable stakingToken;

    /// @notice Indicates whether an asset is enabled for custody deposits and accounting.
    mapping(address => bool) public supportedAssets;
    /// @notice Explicit governance-authorized addresses allowed to mutate locks in addition to registered modules.
    mapping(address => bool) public lockMutators;

    mapping(address => uint256) private _totalCustody;
    mapping(address => uint256) private _protocolAllocation;
    mapping(address => uint256) private _assetTotalLocked;
    mapping(address => uint256) private _assetTotalClaimable;
    mapping(address => mapping(address => uint256)) private _claimable;
    mapping(bytes32 => uint256) private _locks;

    mapping(uint256 => uint256) private _claimTotalVerifierStake;
    mapping(uint256 => mapping(address => uint256)) private _accountClaimVerifierStake;

    /// @notice Records the finalized settlement outcome per (claimId, round) to enforce idempotency.
    mapping(uint256 => mapping(uint256 => IV2Types.SettlementOutcome)) private _settlementOutcome;

    /// @notice Emitted when an exact-balance asset deposit increases an account's claimable balance.
    /// @param asset ERC-20 asset address.
    /// @param account Account credited.
    /// @param amount Exact received amount in asset base units.
    event VaultDeposited(address indexed asset, address indexed account, uint256 amount);
    /// @notice Emitted when claimable funds move into a typed lock cell.
    /// @param asset ERC-20 asset address.
    /// @param account Account whose funds are locked.
    /// @param claimId Claim associated with the lock.
    /// @param round Settlement round.
    /// @param category Lock accounting category.
    /// @param amount Amount moved in asset base units.
    event VaultLocked(
        address indexed asset,
        address indexed account,
        uint256 indexed claimId,
        uint256 round,
        IV2Types.LockCategory category,
        uint256 amount
    );
    /// @notice Emitted when a typed lock returns funds to claimable custody.
    /// @param asset ERC-20 asset address.
    /// @param account Account receiving claimable credit.
    /// @param claimId Claim associated with the lock.
    /// @param round Settlement round.
    /// @param category Lock accounting category.
    /// @param amount Amount moved in asset base units.
    event VaultUnlocked(
        address indexed asset,
        address indexed account,
        uint256 indexed claimId,
        uint256 round,
        IV2Types.LockCategory category,
        uint256 amount
    );
    /// @notice Emitted when a caller withdraws its claimable balance.
    /// @param asset ERC-20 asset address.
    /// @param account Caller and recipient.
    /// @param amount Amount transferred in asset base units.
    event VaultWithdrawn(address indexed asset, address indexed account, uint256 amount);
    /// @notice Emitted when locked funds are reclassified as protocol allocation.
    /// @param asset ERC-20 asset address.
    /// @param amount Amount allocated in asset base units.
    /// @param reason Stable reason code supplied by authorized slashing logic.
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

    /// @notice Returns the immutable StakeVault V2 ABI version.
    /// @return major ABI major version.
    /// @return minor ABI minor version.
    function protocolVersion() external pure override returns (uint16 major, uint16 minor) {
        return (2, 0);
    }

    /// @notice Reports supported ERC-165 interfaces for the custody and V2 discovery surfaces.
    /// @param interfaceId Interface identifier to query.
    /// @return supported True when the interface is implemented by this vault.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl, ERC165, IERC165)
        returns (bool)
    {
        return interfaceId == type(IStakeCustody).interfaceId || interfaceId == type(IV2Module).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // IStakeCustody — verifier stake surface (primary asset, round 0)
    // -------------------------------------------------------------------------

    /// @inheritdoc IStakeCustody
    function depositStake(uint256 claimId, uint256 amount) external override nonReentrant {
        _assertSettlementNotFinalized(claimId, 0);
        address asset = address(stakingToken);
        address account = msg.sender;
        _deposit(account, asset, amount);
        _lock(asset, account, claimId, 0, IV2Types.LockCategory.VERIFIER_PRINCIPAL, amount);
        emit StakeDeposited(account, claimId, amount, uint64(block.timestamp), 1);
    }

    /// @inheritdoc IStakeCustody
    function releaseStake(uint256 claimId, address account, uint256 amount) external override nonReentrant {
        _onlyAuthorizedMutator();
        _assertSettlementNotFinalized(claimId, 0);
        address asset = address(stakingToken);
        _unlock(asset, account, claimId, 0, IV2Types.LockCategory.VERIFIER_PRINCIPAL, amount);
        emit StakeReleased(account, claimId, amount, uint64(block.timestamp), 1);
    }

    /// @inheritdoc IStakeCustody
    function slashStake(uint256 claimId, address account, uint256 amount, bytes32 reason) external override nonReentrant {
        _onlyAuthorizedMutator();
        _assertSettlementNotFinalized(claimId, 0);
        address asset = address(stakingToken);
        _slash(asset, account, claimId, 0, IV2Types.LockCategory.VERIFIER_PRINCIPAL, amount, reason);
        emit StakeSlashed(account, claimId, amount, reason, uint64(block.timestamp), 1);
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
    /// @dev Deposits verify that the vault's balance increases by exactly `amount`; supported assets must have compatible balance and transfer behavior.
    /// @param asset ERC-20 asset address.
    /// @param amount Requested amount in asset base units.
    function deposit(address asset, uint256 amount) external nonReentrant {
        _deposit(msg.sender, asset, amount);
    }

    /// @notice Locks claimable balance into a typed lock cell. Authorized modules only.
    /// @dev Authorization accepts explicit `lockMutators` or a registered supported module; registry failure reverts only registry-derived authorization checks, while explicit mutator authority remains available. An insufficient claimable balance reverts without partial accounting.
    /// @param asset ERC-20 asset address.
    /// @param account Account whose balance is locked.
    /// @param claimId Claim associated with the lock.
    /// @param round Settlement round.
    /// @param category Non-`NONE` lock category.
    /// @param amount Amount in asset base units.
    function lock(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        IV2Types.LockCategory category,
        uint256 amount
    ) external nonReentrant {
        _onlyAuthorizedMutator();
        _assertSettlementNotFinalized(claimId, round);
        _lock(asset, account, claimId, round, category, amount);
    }

    /// @notice Unlocks a typed lock cell back to claimable balance. Authorized modules only.
    /// @dev The lock is reduced by the requested amount; an insufficient lock reverts and preserves all state.
    /// @param asset ERC-20 asset address.
    /// @param account Account whose lock is released.
    /// @param claimId Claim associated with the lock.
    /// @param round Settlement round.
    /// @param category Lock category to release.
    /// @param amount Amount in asset base units.
    function unlock(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        IV2Types.LockCategory category,
        uint256 amount
    ) external nonReentrant {
        _onlyAuthorizedMutator();
        _assertSettlementNotFinalized(claimId, round);
        _unlock(asset, account, claimId, round, category, amount);
    }

    /// @notice Moves locked principal into protocol allocation. Authorized modules only.
    /// @dev Allocation is not a token transfer; custody totals remain conserved while the destination becomes protocol-owned.
    /// @param asset ERC-20 asset address.
    /// @param account Account whose lock is allocated.
    /// @param claimId Claim associated with the lock.
    /// @param round Settlement round.
    /// @param category Lock category to allocate.
    /// @param amount Amount in asset base units.
    /// @param reason Stable allocation reason code.
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
        _assertSettlementNotFinalized(claimId, round);
        _slash(asset, account, claimId, round, category, amount, reason);
    }

    // -------------------------------------------------------------------------
    // Typed settlement hooks (V2-SC-012)
    // -------------------------------------------------------------------------

    /// @inheritdoc IStakeCustody
    function settleConclusive(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        uint256 principalAmount,
        uint256 rewardAmount
    ) external override nonReentrant {
        _onlySettlementModule();
        _assertSettlementNotFinalized(claimId, round);
        _settlementOutcome[claimId][round] = IV2Types.SettlementOutcome.CONCLUDED;

        if (principalAmount > 0) {
            _unlock(asset, account, claimId, round, IV2Types.LockCategory.VERIFIER_PRINCIPAL, principalAmount);
        }
        if (rewardAmount > 0) {
            _creditReward(asset, account, rewardAmount);
        }
        emit VaultSettledConclusive(asset, account, claimId, round, principalAmount, rewardAmount, uint64(block.timestamp), 1);
    }

    /// @inheritdoc IStakeCustody
    function refundInconclusive(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        uint256 amount
    ) external override nonReentrant {
        _onlySettlementModule();
        _assertSettlementNotFinalized(claimId, round);
        _settlementOutcome[claimId][round] = IV2Types.SettlementOutcome.REFUNDED;

        _unlock(asset, account, claimId, round, IV2Types.LockCategory.VERIFIER_PRINCIPAL, amount);
        emit VaultRefundedInconclusive(asset, account, claimId, round, amount, uint64(block.timestamp), 1);
    }

    /// @inheritdoc IStakeCustody
    function carryForwardAppeal(
        address asset,
        address account,
        uint256 claimId,
        uint256 fromRound,
        uint256 toRound,
        uint256 amount
    ) external override nonReentrant {
        _onlySettlementModule();
        _assertSettlementNotFinalized(claimId, fromRound);
        _settlementOutcome[claimId][fromRound] = IV2Types.SettlementOutcome.CARRIED_FORWARD;

        _moveLock(asset, account, claimId, fromRound, toRound, amount);
        emit VaultCarriedForward(asset, account, claimId, fromRound, toRound, amount, uint64(block.timestamp), 1);
    }

    /// @inheritdoc IStakeCustody
    function rolloverRound(
        address asset,
        address account,
        uint256 claimId,
        uint256 fromRound,
        uint256 toRound,
        uint256 amount
    ) external override nonReentrant {
        _onlySettlementModule();
        _assertSettlementNotFinalized(claimId, fromRound);
        _settlementOutcome[claimId][fromRound] = IV2Types.SettlementOutcome.ROLLED_OVER;

        _moveLock(asset, account, claimId, fromRound, toRound, amount);
        emit VaultRolledOver(asset, account, claimId, fromRound, toRound, amount, uint64(block.timestamp), 1);
    }

    /// @inheritdoc IStakeCustody
    function finalUnlock(
        address asset,
        address account,
        uint256 claimId,
        uint256 round,
        uint256 amount
    ) external override nonReentrant {
        _onlySettlementModule();
        _assertSettlementNotFinalized(claimId, round);
        _settlementOutcome[claimId][round] = IV2Types.SettlementOutcome.UNLOCKED;

        _unlock(asset, account, claimId, round, IV2Types.LockCategory.VERIFIER_PRINCIPAL, amount);
        emit VaultFinalUnlocked(asset, account, claimId, round, amount, uint64(block.timestamp), 1);
    }

    /// @inheritdoc IStakeCustody
    function settlementOutcome(uint256 claimId, uint256 round) external view override returns (IV2Types.SettlementOutcome) {
        return _settlementOutcome[claimId][round];
    }

    /// @notice Pull-based withdrawal of the caller's claimable balance.
    /// @dev Only the caller's own balance can be withdrawn; a failed token transfer reverts the accounting update and reentrancy is blocked.
    /// @param asset ERC-20 asset address.
    /// @param amount Amount in asset base units.
    function withdraw(address asset, uint256 amount) external nonReentrant {
        _withdraw(msg.sender, asset, amount);
    }

    // -------------------------------------------------------------------------
    // Reconciliation views
    // -------------------------------------------------------------------------

    /// @notice Total accounted custody for an asset.
    /// @param asset ERC-20 asset address.
    /// @return custody Total token balance attributed to this vault in asset base units.
    function totalCustody(address asset) external view returns (uint256 custody) {
        return _totalCustody[asset];
    }

    /// @notice Locked principal for a specific lock cell.
    /// @param asset ERC-20 asset address.
    /// @param account Account owning the lock.
    /// @param claimId Claim associated with the lock.
    /// @param round Settlement round.
    /// @param category Lock category.
    /// @return amount Locked amount in asset base units.
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
    /// @param asset ERC-20 asset address.
    /// @param account Account to inspect.
    /// @return amount Claimable amount in asset base units.
    function claimableBalance(address asset, address account) external view returns (uint256 amount) {
        return _claimable[asset][account];
    }

    /// @notice Protocol-owned allocation held in custody (e.g. slashed stake).
    /// @param asset ERC-20 asset address.
    /// @return amount Allocated amount in asset base units.
    function protocolAllocation(address asset) external view returns (uint256 amount) {
        return _protocolAllocation[asset];
    }

    /// @notice Returns custody and total accounted obligations for reconciliation.
    /// @dev The accounting invariant is `custody >= obligations`; this view is intended for monitoring and does not repair state.
    /// @param asset ERC-20 asset address.
    /// @return custody Total accounted custody in asset base units.
    /// @return obligations Sum of protocol allocation, locked, and claimable balances.
    function reconcile(address asset) external view returns (uint256 custody, uint256 obligations) {
        return _reconcile(asset);
    }

    /// @notice Returns the canonical conservation terms including the raw on-chain balance for debugging and invariant checks.
    function conservation(address asset)
        external
        view
        returns (uint256 custody, uint256 obligations, uint256 actualBalance)
    {
        custody = _totalCustody[asset];
        obligations = _protocolAllocation[asset] + _assetTotalLocked[asset] + _assetTotalClaimable[asset];
        actualBalance = IERC20(asset).balanceOf(address(this));
    }

    // -------------------------------------------------------------------------
    // Administration
    // -------------------------------------------------------------------------

    /// @notice Enables or disables an asset for custody operations.
    /// @dev Disabling blocks new deposits through `_deposit` but leaves `lock`, `unlock`, `allocateLocked`, and `withdraw` available for existing balances; it does not confiscate existing custody.
    /// @param asset ERC-20 asset address to configure.
    /// @param enabled Whether custody operations are enabled.
    function setSupportedAsset(address asset, bool enabled) external onlyRole(ADMIN_ROLE) {
        if (asset == address(0)) revert V2Errors.ZeroAddress();
        supportedAssets[asset] = enabled;
    }

    /// @notice Grants or revokes explicit lock-mutation authority (governance override).
    /// @dev This is a governance emergency override; it does not grant token custody or settlement execution rights. The change is intentionally not emitted as a local event, so consumers must treat governance transaction traces and the public mapping as the audit record.
    /// @param module Address to authorize or remove.
    /// @param enabled Whether the address may mutate locks.
    function setLockMutator(address module, bool enabled) external onlyRole(ADMIN_ROLE) {
        if (module == address(0)) revert V2Errors.ZeroAddress();
        lockMutators[module] = enabled;
    }

    /// @notice Returns whether an address may mutate locks.
    /// @dev A true result is necessary but not sufficient for settlement hooks, which remain restricted to the registered settlement module.
    /// @param caller Address to check.
    /// @return authorized True for an explicit mutator or a registered supported module.
    function isAuthorizedMutator(address caller) public view returns (bool authorized) {
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

    /// @notice Restricts a hook to the registered SETTLEMENT module.
    /// @dev Registry lookup and address comparison are security boundaries; a registry call failure must propagate and deny the hook.
    function _onlySettlementModule() internal view {
        if (!_isRegisteredModule(msg.sender, MODULE_SETTLEMENT)) revert V2Errors.UnauthorizedModule(msg.sender);
    }

    /// @notice Reverts if a settlement outcome has already been recorded for the claim-round.
    /// @dev This is the replay-protection invariant for all settlement hooks.
    function _assertSettlementNotFinalized(uint256 claimId, uint256 round) internal view {
        if (_settlementOutcome[claimId][round] != IV2Types.SettlementOutcome.NONE) {
            revert V2Errors.SettlementAlreadyFinalized(claimId, round);
        }
    }

    /// @notice Credits a reward to an account's claimable balance, funded from protocol allocation.
    /// @dev Rewards are reclassified, not minted; insufficient protocol allocation reverts atomically.
    function _creditReward(address asset, address account, uint256 amount) internal {
        if (amount == 0) revert V2Errors.ZeroAmount();
        uint256 allocation = _protocolAllocation[asset];
        if (allocation < amount) revert V2Errors.InsufficientProtocolAllocation(amount, allocation);

        _protocolAllocation[asset] = allocation - amount;
        _claimable[asset][account] += amount;
        _assetTotalClaimable[asset] += amount;

        _assertReconciliation(asset);
    }

    /// @notice Moves a VERIFIER_PRINCIPAL lock from one round to another without changing custody totals.
    /// @dev The destination round must be later than the source and must not have a recorded settlement outcome; no rounding or external transfer occurs in this transition.
    function _moveLock(
        address asset,
        address account,
        uint256 claimId,
        uint256 fromRound,
        uint256 toRound,
        uint256 amount
    ) internal {
        if (amount == 0) revert V2Errors.ZeroAmount();
        if (toRound < fromRound) revert V2Errors.InvalidArgument("destination round must be later");
        if (toRound == fromRound) revert V2Errors.InvalidArgument("same round");
        if (_settlementOutcome[claimId][toRound] != IV2Types.SettlementOutcome.NONE) {
            revert V2Errors.SettlementAlreadyFinalized(claimId, toRound);
        }

        bytes32 fromKey = _lockKey(asset, account, claimId, fromRound, IV2Types.LockCategory.VERIFIER_PRINCIPAL);
        uint256 locked = _locks[fromKey];
        if (locked < amount) revert V2Errors.InsufficientLocked(amount, locked);

        _locks[fromKey] = locked - amount;

        bytes32 toKey = _lockKey(asset, account, claimId, toRound, IV2Types.LockCategory.VERIFIER_PRINCIPAL);
        _locks[toKey] += amount;

        _assertReconciliation(asset);
    }

    function _assertReconciliation(address asset) internal view {
        (uint256 custody, uint256 obligations) = _reconcile(asset);
        uint256 actualBalance = IERC20(asset).balanceOf(address(this));

        if (obligations > custody) revert V2Errors.ObligationsExceedCustody(asset, custody, obligations);
        if (custody != obligations || actualBalance != custody) {
            revert V2Errors.ConservationInvariantViolation(asset, custody, obligations, actualBalance);
        }
    }

    function _reconcile(address asset) internal view returns (uint256 custody, uint256 obligations) {
        custody = _totalCustody[asset];
        obligations = _protocolAllocation[asset] + _assetTotalLocked[asset] + _assetTotalClaimable[asset];
    }
}
