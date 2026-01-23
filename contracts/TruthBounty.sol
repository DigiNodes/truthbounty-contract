// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract TruthBountyToken is ERC20, Pausable, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    event EmergencyShutdown(address indexed by, uint timestamp);
    event ContractResumed(address indexed by, uint timestamp);
    event TokensMinted(address indexed to, uint256 amount, address indexed by);

    constructor() ERC20("TruthBounty", "BOUNTY") {
        // Grant roles to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

        // Mint initial supply
        _mint(msg.sender, 10_000_000 * 10 ** decimals());
    }

    /**
     * @notice Mint new tokens
     * @dev Only MINTER_ROLE can mint, blocked when paused
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        _mint(to, amount);
        emit TokensMinted(to, amount, msg.sender);
    }

    /**
     * @notice Emergency pause - stops all token operations
     * @dev Only PAUSER_ROLE can pause
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
        emit EmergencyShutdown(msg.sender, block.timestamp);
    }

    /**
     * @notice Resume normal operations
     * @dev Only PAUSER_ROLE can unpause
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
        emit ContractResumed(msg.sender, block.timestamp);
    }

    /**
     * @notice Override transfer to respect pause state
     */
    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        super._update(from, to, value);
    }

    /**
     * @notice Check if contract is currently paused
     */
    function isPaused() external view returns (bool) {
        return paused();
    }

    /**
     * @notice Grant PAUSER_ROLE to an address
     * @dev Only ADMIN_ROLE can grant pauser role
     */
    function grantPauserRole(address account) external onlyRole(ADMIN_ROLE) {
        grantRole(PAUSER_ROLE, account);
    }

    /**
     * @notice Revoke PAUSER_ROLE from an address
     * @dev Only ADMIN_ROLE can revoke pauser role
     */
    function revokePauserRole(address account) external onlyRole(ADMIN_ROLE) {
        revokeRole(PAUSER_ROLE, account);
    }
}