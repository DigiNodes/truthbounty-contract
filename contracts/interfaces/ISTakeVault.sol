// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISTakeVault
 * @notice Minimal bond-custody interface for challenge bond locking (V2-SC-016
 *         dependency stand-in for V2-SC-009 Stake Vault Custody and Lock Ledger).
 *
 * @dev The full V2-SC-009 StakeVault is not yet implemented in this repository.
 *      This interface is the smallest surface the DisputeResolution engine needs
 *      in order to satisfy the SC-016 custody guarantees:
 *
 *        - bonds are locked in *vaulted* custody (the StakeVault holds the ERC20),
 *        - every lock is recorded on a persistent lock ledger so that on-chain
 *          bond and dispute records reconcile 1:1,
 *        - a lock can only be released by an authenticated operator in the vault
 *          domain (refund or slash), never by the depositor directly.
 *
 *      When the production V2-SC-009 StakeVault lands, `DisputeResolution` must
 *      be pointed at a contract implementing this interface (see `setVault`).
 *
 * Trust assumptions:
 * - The vault holds the configured bond ERC20 token. Only `lockBond` pulls
 *   depositor funds (via `safeTransferFrom`).
 * - `lockId` is authoritatively chosen by the calling module (the dispute id in
 *   the DisputeResolution domain) and must be unique across the vault.
 * - Bond custody is independent of governance and treasury: neither a governance
 *   role nor the treasury can unlock an active bond. Only the authorised
 *   operator (the DisputeResolution module) can release a lock.
 */
interface ISTakeVault {
    // =========================================================================
    // Structs
    // =========================================================================

    /**
     * @notice Canonical on-chain representation of a single bond lock.
     * @param lockId      Unique lock identifier (borrowed from the caller's dispute id).
     * @param token       ERC20 token bound to this lock.
     * @param depositor   Address that supplied the bond funds.
     * @param amount      Locked token amount.
     * @param lockedAt    Unix timestamp when the lock was created.
     * @param released    Whether the lock has been released (refunded or slashed).
     * @param releasedTo  Recipient of the funds once released (recorded at release time).
     */
    struct BondLock {
        uint256 lockId;
        address token;
        address depositor;
        uint256 amount;
        uint64 lockedAt;
        bool released;
        address releasedTo;
    }

    // =========================================================================
    // Events
    // =========================================================================

    /**
     * @notice Emitted when a bond is locked into vaulted custody.
     * @param lockId    Unique lock identifier.
     * @param token     ERC20 token locked.
     * @param depositor Address that supplied the funds.
     * @param amount    Amount locked.
     * @param operator  The module that created the lock (msg.sender).
     */
    event BondLocked(
        uint256 indexed lockId,
        address indexed token,
        address indexed depositor,
        uint256 amount,
        address operator
    );

    /**
     * @notice Emitted when a locked bond is released to a recipient.
     * @param lockId    Unique lock identifier.
     * @param recipient Recipient of the released funds.
     * @param amount    Amount released.
     * @param operator  The module that released the lock (msg.sender).
     */
    event BondReleased(
        uint256 indexed lockId,
        address indexed recipient,
        uint256 amount,
        address operator
    );

    // =========================================================================
    // Custom Errors
    // =========================================================================

    /// @notice Thrown when `lockId` is already locked (lock ledgers are append-only per id).
    error LockAlreadyExists(uint256 lockId);

    /// @notice Thrown when `lockId` does not exist or the depositor is zero.
    error LockNotFound(uint256 lockId);

    /// @notice Thrown when trying to release an already-released lock.
    error LockAlreadyReleased(uint256 lockId);

    /// @notice Thrown when a token transfer or the ERC20 transfer-back fails.
    error BondTransferFailed();

    /// @notice Thrown on zero-address constructor/initialization inputs.
    error ZeroAddress();

    /// @notice Thrown when the caller is not an authorised vault operator.
    error NotAuthorizedOperator();

    // =========================================================================
    // Write Functions
    // =========================================================================

    /**
     * @notice Pulls `amount` of `token` from `depositor` into vaulted custody and
     *         records it under `lockId`.
     * @param lockId    Unique, caller-chosen lock identifier (must be unused).
     * @param token     ERC20 bond token.
     * @param depositor Address providing the funds (must have approved the vault).
     * @param amount    Amount to lock.
     * @dev Reverts (atomically) if the lock already exists or the transfer fails,
     *      so no dispute can reference a bond lock that does not exist.
     * @custom:emits BondLocked
     */
    function lockBond(uint256 lockId, address token, address depositor, uint256 amount) external;

    /**
     * @notice Releases a locked bond to `recipient`.
     * @param lockId    Lock to release.
     * @param recipient Recipient of the funds.
     * @dev Only the authorised operator may release. Idempotency is enforced: a
     *      released lock cannot be released twice.
     * @custom:emits BondReleased
     */
    function releaseBond(uint256 lockId, address recipient) external;

    // =========================================================================
    // View Functions
    // =========================================================================

    /**
     * @notice Returns the bond token this vault has been configured to custody.
     * @return token The configured bond ERC20 (address(0) if unset).
     */
    function bondToken() external view returns (address token);

    /**
     * @notice Returns a single bond lock record.
     * @param lockId Lock identifier to query.
     * @return lock The BondLock struct.
     * @dev Reverts with {LockNotFound} if the lock does not exist.
     */
    function getLock(uint256 lockId) external view returns (BondLock memory lock);

    /**
     * @notice Returns the aggregate amount of bond tokens currently locked and
     *         not yet released.
     * @return total Total tokens held in vaulted custody.
     * @dev Supplies the on-chain reconciliation invariant:
     *      `totalLocked == sum(released == false ? amount : 0)`.
     */
    function totalLocked() external view returns (uint256 total);
}
