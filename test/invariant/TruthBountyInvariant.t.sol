// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../contracts/TruthBounty.sol";

contract TruthBountyInvariant is StdInvariant, Test {
    TruthBounty public truthBounty;
    TruthBountyToken public token;

    function setUp() public {
        token = new TruthBountyToken(address(this));
        truthBounty = new TruthBounty(address(token), address(this), address(this));

        targetContract(address(truthBounty));
    }

    function invariant_TotalRewardedNeverExceedsTotalSlashed() public view {
        assertLe(truthBounty.totalRewarded(), truthBounty.totalSlashed());
    }

    function invariant_ContractEthBalanceIsNonNegative() public view {
        assertGe(address(truthBounty).balance, 0);
    }
}
