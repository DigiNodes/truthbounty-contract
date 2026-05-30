// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/TruthBountyWeighted.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockBountyToken is ERC20 {
    constructor() ERC20("Mock Bounty", "MBK") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockOracle {
    function isActive() external pure returns (bool) { return true; }
    function getReputationScore(address) external pure returns (uint256) { return 1e18; }
}

contract RoundingErrorPreventionFuzzTest is Test {
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
    }

    function testFuzz_NoDustLeftAfterRewardsClaimed(
        uint256[5] memory stakes,
        uint256 loserStake
    ) public {
        // Bound stakes to realistic minimum and maximum amounts
        uint256 sumStakes = 0;
        for (uint i = 0; i < stakes.length; i++) {
            stakes[i] = bound(stakes[i], truthBounty.minStakeAmount(), 1_000_000 * 1e18);
            sumStakes += stakes[i];
        }
        
        // Bound loser stake so the "For" votes always maintain >60% majority to guarantee a pass
        loserStake = bound(loserStake, truthBounty.minStakeAmount(), (sumStakes * 40) / 100);

        uint256 claimId = truthBounty.createClaim("Fuzz Claim");

        // Loser stakes and votes against
        address loser = address(0x10);
        token.mint(loser, loserStake);
        
        vm.startPrank(loser);
        token.approve(address(truthBounty), loserStake);
        truthBounty.stake(loserStake);
        truthBounty.vote(claimId, false, loserStake);
        vm.stopPrank();

        // Winners stake and vote for
        address[5] memory winners = [address(0x21), address(0x22), address(0x23), address(0x24), address(0x25)];
        uint256 expectedTotalWinnerStake = 0;
        
        for (uint i = 0; i < winners.length; i++) {
            token.mint(winners[i], stakes[i]);
            vm.startPrank(winners[i]);
            token.approve(address(truthBounty), stakes[i]);
            truthBounty.stake(stakes[i]);
            truthBounty.vote(claimId, true, stakes[i]);
            vm.stopPrank();
            
            expectedTotalWinnerStake += stakes[i];
        }

        // Advance time to settle the claim
        vm.warp(block.timestamp + 2 days);
        truthBounty.settleClaim(claimId);

        // Each winner claims their reward
        for (uint i = 0; i < winners.length; i++) {
            vm.prank(winners[i]);
            truthBounty.claimSettlementRewards(claimId);
        }

        // Check if all rewards were cleanly distributed
        ( , uint256 totalRewards, , , , uint256 claimedWinnerWeightedStake, uint256 distributedRewards) = truthBounty.settlementResults(claimId);
        
        assertEq(claimedWinnerWeightedStake, expectedTotalWinnerStake, "Not all winner stakes were accounted for");
        assertEq(distributedRewards, totalRewards, "Distributed rewards must exactly equal total rewards, leaving 0 dust");
    }
}