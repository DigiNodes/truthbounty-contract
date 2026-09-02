// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Mock ERC20 whose `transferFrom` always returns false (simulating a
 *      non-reverting token that refuses to move funds out). This is used to
 *      exercise the challenge-bond custody failure path: {SafeERC20} turns the
 *      `false` return into {SafeERC20.SafeERC20FailedOperation}, so the vault's
 *      lock is undone and the whole dispute-open transaction reverts atomically.
 */
contract MockFailingBondERC20 is ERC20 {
    constructor() ERC20("Mock Failing Bond", "MFB") {
        _mint(msg.sender, 1_000_000 * (10 ** decimals()));
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        return false;
    }
}
