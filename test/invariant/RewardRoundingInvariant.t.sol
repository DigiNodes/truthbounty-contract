// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/TruthBountyWeighted.sol";
import "../fuzz/RoundingErrorPrevention.fuzz.sol"; // For Mocks

// This invariant function ensures no settlement enters an invalid reward state 
// regarding the distribution of tokens and remainders.
contract RewardRoundingInvariantTest is Test {
    TruthBountyWeighted public truthBounty;
    MockBountyToken public token;
    MockOracle public oracle;

    address public admin = address(0x1);
    
    function setUp() public {
        token = new MockBountyToken();
        oracle = new MockOracle();
        
        vm.startPrank(admin);
        truthBounty = new TruthBountyWeighted(address(token), address(oracle), admin, admin);
        truthBounty.setVerificationWindowDuration(1 days);
        truthBounty.setConfirmationDelay(1 hours);
        vm.stopPrank();

        // Target the truth bounty contract for invariant testing
        targetContract(address(truthBounty));
    }

    /// @dev Invariant: The distributed rewards for any settled claim must never exceed its totalRewards.
    ///                 If all winners have claimed, distributedRewards must exactly equal totalRewards.
    function invariant_DistributedRewardsConsistency() public view {
        uint256 claimIdCounter = truthBounty.claimCounter();
        
        for (uint256 i = 0; i < claimIdCounter; i++) {
            (
                , // passed
                uint256 totalRewards,
                , // totalSlashed
                uint256 winnerWeightedStake,
                , // loserWeightedStake
                uint256 claimedWinnerWeightedStake,
                uint256 distributedRewards
            ) = truthBounty.settlementResults(i);
            
            // 1. We should never distribute more than we have
            assertLe(distributedRewards, totalRewards, "Protocol invariant violated: Distributed rewards exceeded total rewards");
            
            // 2. Exact match at the end
            if (claimedWinnerWeightedStake == winnerWeightedStake && winnerWeightedStake > 0) {
                assertEq(distributedRewards, totalRewards, "Protocol invariant violated: All rewards not exactly distributed after full claim");
            }
        }
    }
}