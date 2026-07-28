// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RewardToken
 * @notice ERC20 token with role-based minting and burning for protocol rewards
 * @dev Uses AccessControl with MINTER_ROLE and BURNER_ROLE.
 *      DEFAULT_ADMIN_ROLE can grant/revoke minter/burner roles.
 */
contract RewardToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /**
     * @param initialAdmin Address that receives DEFAULT_ADMIN_ROLE and initial supply
     * @param initialSupply Initial token supply minted to initialAdmin
     */
    constructor(address initialAdmin, uint256 initialSupply) ERC20("RewardToken", "RWD") {
        require(initialAdmin != address(0), "Invalid admin address");

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);

        if (initialSupply > 0) {
            _mint(initialAdmin, initialSupply);
        }
    }

    /**
     * @notice Mint new tokens
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from an address
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }
}