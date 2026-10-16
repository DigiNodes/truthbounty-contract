// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IGovernanceAuthorityBoundaries} from "./IGovernanceAuthorityBoundaries.sol";
import {GovernanceAuthorityMatrix} from "./libraries/GovernanceAuthorityMatrix.sol";

/**
 * @title GovernanceAuthorityBoundaries
 * @notice On-chain publication and enforcement of the canonical V2 authority boundaries.
 * @dev The capability matrix is immutable (see {GovernanceAuthorityMatrix}); this contract records
 *      which account is accountable for each authority role. A role can be bound once at a time and
 *      an account can hold at most one role, so overlapping authority cannot be configured. The
 *      bootstrap admin must hand AUTHORITY_ADMIN_ROLE to the timelock after deployment so that
 *      authority configuration is governed and timelocked.
 */
contract GovernanceAuthorityBoundaries is IGovernanceAuthorityBoundaries, AccessControl {
    bytes32 public constant AUTHORITY_ADMIN_ROLE = keccak(256("AUTHORITY_ADMIN_ROLE"));

    /// @dev Must match {GovernanceAuthorityMatrix.ROLE_COUNT}; asserted by the boundary test suite.
    uint256 internal constant ROLE_COUNT = 7;
    /// @dev Must match {GovernanceAuthorityMatrix.CAPABILITY_COUNT}; asserted by the boundary test suite.
    uint256 internal constant CAPABILITY_COUNT = 11;

    address[ROLE_COUNT] private _authorityAccount;
    bool[ROLE_COUNT] private _authorityBound;
    mapping(address => uint256) private _roleIndexPlusOne;

    /// @dev Enumeration of bound authority accounts, kept in sync with the bound state.
    address[] private _boundAccounts;
    mapping(address => uint256) private _boundAccountIndexPlusOne;

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAuthorityAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(AUTHORITY_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IGovernanceAuthorityBoundaries
    function bindAuthority(AuthorityRole role, address account) external onlyRole(AUTHORITY_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAuthorityAddress();

        uint256 index = uint256(role);
        if (_authorityBound[index]) revert AuthorityAlreadyBound(role, _authorityAccount[index]);

        uint256 existing = _roleIndexPlusOne[account];
        if (existing != 0) {
            revert OverlappingAuthority(account, AuthorityRole(existing - 1), role);
        }

        _authorityBound[index] = true;
        _authorityAccount[index] = account;
        _roleIndexPlusOne[account] = index + 1;

        _boundAccountIndexPlusOne[account] = _boundAccounts.length + 1;
        _boundAccounts.push(account);

        emit AuthorityBoundaryDeclared(role, account);
    }

    /// @inheritdoc IGovernanceAuthorityBoundaries
    function revokeAuthority(AuthorityRole role) external onlyRole(AUTHORITY_ADMIN_ROLE) {
        uint256 index = uint256(role);
        if (!_authorityBound[index]) revert AuthorityNotBound(role);

        address account = _authorityAccount[index];
        _authorityBound[index] = false;
        _authorityAccount[index] = address(0);
        delete _roleIndexPlusOne[account];

        _removeBoundAccount(account);

        emit AuthorityBoundaryRevoked(role, account);
    }

    /// @inheritdoc IGovernanceAuthorityBoundaries
    function authorityOf(AuthorityRole role) external view returns (address) {
        return _authorityAccount[uint256(role)];
    }

    /// @inheritdoc IGovernanceAuthorityBoundaries
    function isAuthorityBound(AuthorityRole role) external view returns (bool) {
        return _authorityBound[uint256(role)];
    }

    /// @inheritdoc IGovernanceAuthorityBoundaries
    function boundRoleOf(address account) external view returns (AuthorityRole role, bool bound) {
        uint256 stored = _roleIndexPlusOne[account];
        if (stored == 0) {
            return (AuthorityRole.GOVERNOR, false);
        }
        return (AuthorityRole(stored - 1), true);
    }

    /// @notice Number of accounts currently bound to an authority role.
    function boundAccountCount() external view returns (uint256) {
        return _boundAccounts.length;
    }

    /// @notice Bound authority account at an enumeration index.
    function boundAccountAt(uint256 index) external view returns (address) {
        return _boundAccounts[index];
    }

    /// @notice Whether an account is currently bound to an authority role.
    function isBoundAccount(address account) external view returns (bool) {
        return _roleIndexPlusOne[account] != 0;
    }

    /// @notice Paginated enumeration of bound authority accounts.
    function boundAccountsPage(uint256 offset, uint256 limit) external view returns (address[] memory page, uint256 nextOffset) {
        uint256 total = _boundAccounts.length;
        if (offset >= total || limit == 0) {
            return (new address[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) end = total;

        page = new address[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            page[i - offset] = _boundAccounts[i];
        }
        nextOffset = end;
    }

    /// @notice Enumerate every role that is currently bound.
    function boundRoles() external view returns (AuthorityRole[] memory roles, address[] memory accounts) {
        uint256 count;
        for (uint256 i = 0; i < ROLE_COUNT; ++i) {
            if (_authorityBound[i]) {
                ++count;
            }
        }

        roles = new AuthorityRole[](count);
        accounts = new address[](count);
        uint256 j;
        for (uint256 i = 0; i < ROLE_COUNT; ++i) {
            if (_authorityBound[i]) {
                roles[j] = AuthorityRole(i);
                accounts[j] = _authorityAccount[i];
                ++j;
            }
        }
    }

    /// @inheritdoc IGovernanceAuthorityBoundaries
    function isCapabilityAllowed(AuthorityRole role, Capability capability) external pure returns (bool) {
        return GovernanceAuthorityMatrix.isAllowed(role, capability);
    }

    /// @inheritdoc IGovernanceAuthorityBoundaries
    function isCapabilityExclusive(Capability capability) external pure returns (bool) {
        return GovernanceAuthorityMatrix.isExclusive(capability);
    }

    /// @inheritdoc IGovernanceAuthorityBoundaries
    function soleRoleForCapability(Capability capability) external pure returns (AuthorityRole) {
        return GovernanceAuthorityMatrix.soleRoleFor(capability);
    }

    /// @inheritdoc IGovernanceAuthorityBoundaries
    function rolesForCapability(Capability capability) external pure returns (AuthorityRole[] memory) {
        return GovernanceAuthorityMatrix.rolesFor(capability);
    }

    /// @inheritdoc IGovernanceAuthorityBoundaries
    function capabilitiesOf(AuthorityRole role) external pure returns (Capability[] memory) {
        return GovernanceAuthorityMatrix.capabilitiesFor(role);
    }

    /// @inheritdoc IGovernanceAuthorityBoundaries
    function isAuthorizedFor(address account, Capability capability) external view returns (bool) {
        uint256 stored = _roleIndexPlusOne[account];
        if (stored == 0) {
            return false;
        }
        return GovernanceAuthorityMatrix.isAllowed(AuthorityRole(stored - 1), capability);
    }

    /// @inheritdoc IGovernanceAuthorityBoundaries
    function requireCapability(AuthorityRole role, Capability capability) external pure {
        GovernanceAuthorityMatrix.enforce(role, capability);
    }

    /// @inheritdoc IGovernanceAuthorityBoundaries
    function publishAuthorityMatrix() external {
        emit GovernanceAuthorityMatrixPublished(msg.sender, ROLE_COUNT, CAPABILITY_COUNT);
    }

    /// @dev Swap-and-pop removal of a bound account from the enumeration set.
    function _removeBoundAccount(address account) private {
        uint256 stored = _boundAccountIndexPlusOne[account];
        if (stored == 0) return;

        uint256 index = stored - 1;
        uint256 lastIndex = _boundAccounts.length - 1;

        if (index != lastIndex) {
            address lastAccount = _boundAccounts[lastIndex];
            _boundAccounts[index] = lastAccount;
            _boundAccountIndexPlusOne[lastAccount] = index + 1;
        }

        _boundAccounts.pop();
        delete _boundAccountIndexPlusOne[account];
    }
}
