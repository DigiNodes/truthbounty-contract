// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ISupplyChainAttestations } from "../interfaces/ISupplyChainAttestations.sol";

/// @title V2SubmoduleProvenance
/// @notice Pure stateless helpers to verify the pinned submodule dependency graph.
library V2SubmoduleProvenance {
    function verifyDependencyGraph(
        ISupplyChainAttestations.DependencyEntry[] memory dependencies,
        uint256 minPinnedSubmodules
    ) internal pure returns (bool) {
        if (dependencies.length < minPinnedSubmodules) {
            return false;
        }
        for (uint256 i = 0; i < dependencies.length; i++) {
            if (bytes(dependencies[i].name).length == 0) return false;
            if (bytes(dependencies[i].version).length == 0) return false;
            if (bytes(dependencies[i].kind).length == 0) return false;
            if (bytes(dependencies[i].rev).length != 40) return false;
            if (bytes(dependencies[i].integrity).length != 40) return false;
        }
        return true;
    }
}
