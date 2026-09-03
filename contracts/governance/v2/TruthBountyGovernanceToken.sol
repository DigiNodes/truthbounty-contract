// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title TruthBountyGovernanceToken
 * @notice ERC20Votes token used for TruthBounty V2 on-chain governance.
 * @dev Delegation is required before voting power is active. Holders delegate to themselves
 *      or another address via {delegate}. Token transfers move voting units 1:1 with balances.
 */
contract TruthBountyGovernanceToken is ERC20, ERC20Permit, ERC20Votes {
    error ZeroRecipient();

    constructor(address initialHolder, uint256 initialSupply)
        ERC20("TruthBounty Governance", "TB-GOV")
        ERC20Permit("TruthBounty Governance")
    {
        if (initialHolder == address(0)) revert ZeroRecipient();
        _mint(initialHolder, initialSupply);
    }

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }
}
