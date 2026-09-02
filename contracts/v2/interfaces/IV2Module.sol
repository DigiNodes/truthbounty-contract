// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Common discovery surface for every TruthBounty V2 module.
/// @dev Implementations MUST return true for type(IV2Module).interfaceId and their module interface ID.
interface IV2Module is IERC165 {
    /// @notice Returns the immutable protocol version implemented by this module.
    function protocolVersion() external pure returns (uint16 major, uint16 minor);
}
