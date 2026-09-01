// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../utils/LifecycleFixture.t.sol";

contract LifecycleFixtureTest is LifecycleFixture {
    
    function setUp() public override {
        super.setUp();
    }

    function testUndisputedClaimLifecycle() public {
        uint256 initialBal1 = bountyToken.balanceOf(verifier1);
        uint256 initialBal2 = bountyToken.balanceOf(verifier2);
        
        uint256 claimId = driveUndisputedClaim(true);
        
        // Assert state matches expected
        // Claim struct has 11 fields. 6th is `settled`
        (, , , , , bool settled, , , , , ) = truthBounty.claims(claimId);
        assertTrue(settled, "Claim should be settled");
        
        // Verify balances (verifiers won the undisputed claim and should receive rewards)
        assertTrue(bountyToken.balanceOf(verifier1) > initialBal1, "Verifier 1 should have received rewards");
        assertTrue(bountyToken.balanceOf(verifier2) > initialBal2, "Verifier 2 should have received rewards");
    }

    function testChallengedClaimLifecycle_ChallengerWins() public {
        uint256 claimId = driveChallengedClaim(true);
        
        (, , , , , bool settled, , , , , ) = truthBounty.claims(claimId);
        assertTrue(settled, "Claim should be settled");
        
        // Vote struct has 11 fields. 6th is `rewardClaimed`, 7th is `stakeReturned`
        (, , , , , bool v1RewardClaimed, bool v1StakeReturned, , , , ) = truthBounty.votes(claimId, verifier1);
        assertFalse(v1RewardClaimed, "V1 should not claim rewards");
        assertTrue(v1StakeReturned, "V1 stake should be returned (minus slash)");
        
        (, , , , , bool v3RewardClaimed, bool v3StakeReturned, , , , ) = truthBounty.votes(claimId, verifier3);
        assertTrue(v3RewardClaimed, "V3 should have claimed rewards");
        assertTrue(v3StakeReturned, "V3 stake should be fully returned");
    }

    function testChallengedClaimLifecycle_SubmitterWins() public {
        uint256 claimId = driveChallengedClaim(false);
        
        (, , , , , bool settled, , , , , ) = truthBounty.claims(claimId);
        assertTrue(settled, "Claim should be settled");
        
        (, , , , , bool v1RewardClaimed, bool v1StakeReturned, , , , ) = truthBounty.votes(claimId, verifier1);
        assertTrue(v1RewardClaimed, "V1 should have claimed rewards");
        assertTrue(v1StakeReturned, "V1 stake should be fully returned");
        
        (, , , , , bool v3RewardClaimed, bool v3StakeReturned, , , , ) = truthBounty.votes(claimId, verifier3);
        assertFalse(v3RewardClaimed, "V3 should not claim rewards");
        assertTrue(v3StakeReturned, "V3 stake should be returned (minus slash)");
    }
}
