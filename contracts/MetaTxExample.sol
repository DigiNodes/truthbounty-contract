// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/metatx/ERC2771Context.sol";

contract MetaTxExample is ERC2771Context {
    constructor(address trustedForwarder) ERC2771Context(trustedForwarder) {}

    // Override to preserve original sender identity
    function _msgSender() internal view override returns (address sender) {
        return ERC2771Context._msgSender();
    }

    function _msgData() internal view override returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    // Example function using meta-transactions
    function transfer(address to, uint256 amount) external {
        // _msgSender() resolves to the original user, not the relayer
        // Business logic here
    }
}
