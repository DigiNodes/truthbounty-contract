// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Common discovery surface for every TruthBounty V2 module.
/// @dev Implementations MUST return true for `type(IV2Module).interfaceId` and their concrete module interface ID. The version identifies the module ABI, not an on-chain governance parameter set.
interface IV2Module is IERC165 {
    /// @notice Returns the immutable protocol version implemented by this module.
    /// @dev Declared `view` (not `pure`) so implementations can read version-bearing immutables;
    ///      the function selector and IV2Module interface ID are unaffected by mutability.
    function protocolVersion() external view returns (uint16 major, uint16 minor);
}
