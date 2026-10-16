// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Mock ERC20 token that always returns false on transfer to simulate non-reverting failures.
 */
contract MockFailingERC20 is ERC20 {
    constructor() ERC20("Mock Failing ERC20", "MFE") {
        _mint(msg.sender, 1000000 * 10**decimals());
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        // Always return false to simulate failure without reverting
        return false;
    }

    /**
     * @dev Simulates a false-returning transferFrom for allowance-race and
     * transfer-mismatch tests. Returns false without reverting.
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        return false;
    }
}