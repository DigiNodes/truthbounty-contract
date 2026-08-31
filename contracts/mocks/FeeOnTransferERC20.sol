// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev ERC20 that deducts a fee on transfer to test exact-balance rejection.
contract FeeOnTransferERC20 is ERC20 {
    uint256 public feeBps;

    constructor(string memory name, string memory symbol, uint256 _feeBps) ERC20(name, symbol) {
        feeBps = _feeBps;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && to != address(0) && feeBps > 0) {
            uint256 fee = (amount * feeBps) / 10_000;
            super._update(from, address(this), fee);
            amount -= fee;
        }
        super._update(from, to, amount);
    }
}
