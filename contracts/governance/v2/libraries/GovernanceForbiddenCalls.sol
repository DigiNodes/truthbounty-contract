// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GovernanceForbiddenCalls
 * @notice Static library identifying claim-settlement and outcome-override selectors
 *         that governance proposals must never invoke.
 * @dev Governance may configure protocol parameters but must not decide individual claims.
 */
library GovernanceForbiddenCalls {
    /// @dev TruthBountyWeighted.settleClaim(uint256)
    bytes4 internal constant SETTLE_CLAIM_UINT256 = bytes4(keccak256("settleClaim(uint256)"));
    /// @dev TruthBountyClaims.settleClaim(address,uint256)
    bytes4 internal constant SETTLE_CLAIM_ADDRESS_UINT256 = bytes4(keccak256("settleClaim(address,uint256)"));
    /// @dev TruthBountyClaims.settleClaimsBatch(address[],uint256[])
    bytes4 internal constant SETTLE_CLAIMS_BATCH = bytes4(keccak256("settleClaimsBatch(address[],uint256[])"));
    /// @dev ExampleSettlement / legacy settleClaim variants with extra params
    bytes4 internal constant SETTLE_CLAIM_WITH_PROOF = bytes4(keccak256("settleClaim(uint256,bytes32)"));

    error ForbiddenGovernanceCall(bytes4 selector);

    /**
     * @dev Reverts when `calldata_` encodes a prohibited claim-outcome operation.
     * @param calldata_ Encoded call data for a single governance operation.
     */
    function enforceAllowed(bytes memory calldata_) internal pure {
        if (calldata_.length < 4) {
            return;
        }
        bytes4 selector;
        assembly {
            selector := mload(add(calldata_, 32))
        }
        if (isForbidden(selector)) {
            revert ForbiddenGovernanceCall(selector);
        }
    }

    /**
     * @dev Returns true when the four-byte selector matches a blocked claim-outcome call.
     */
    function isForbidden(bytes4 selector) internal pure returns (bool) {
        return selector == SETTLE_CLAIM_UINT256 || selector == SETTLE_CLAIM_ADDRESS_UINT256
            || selector == SETTLE_CLAIMS_BATCH || selector == SETTLE_CLAIM_WITH_PROOF;
    }
}
