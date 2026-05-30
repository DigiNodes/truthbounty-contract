// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../contracts/TruthBountyWeighted.sol";
import "../fuzz/RoundingErrorPrevention.fuzz.sol"; // For Mocks

contract RewardRoundingHandler is Test {
    TruthBountyWeighted public truthBounty;
    MockBountyToken public token;
    MockOracle public oracle;

    address[] public verifiers;
    uint256[] public claimIds;

    constructor() {
        token = new MockBountyToken();
        oracle = new MockOracle();
        
        truthBounty = new TruthBountyWeighted(address(token), address(oracle), msg.sender, msg.sender);
        
        vm.startPrank(msg.sender);
        truthBounty.setVerificationWindowDuration(1 days);
        truthBounty.setConfirmationDelay(1 hours);
        vm.stopPrank();

        for (uint256 i = 0; i < 5; i++) {
            address verifier = address(uint160(0x1000 + i));
            verifiers.push(verifier);
            token.mint(verifier, 100000 * 10**18);

            vm.prank(verifier);
            token.approve(address(truthBounty), type(uint256).max);

            vm.prank(verifier);
            truthBounty.stake(50000 * 10**18);
        }
    }

    function createClaim(uint256 seed) public {
        vm.prank(address(this));
        uint256 claimId = truthBounty.createClaim(string(abi.encode("claim_", seed)));
        claimIds.push(claimId);
    }

    function castVotes(uint256 claimIdx, uint256 seed) public {
        if (claimIds.length == 0) return;
        uint256 claimId = claimIds[claimIdx % claimIds.length];

        for (uint256 i = 0; i < 5; i++) {
            if (block.timestamp >= 1 days) return;
            bool support = ((seed % 2) + i) % 2 == 0;
            uint256 stakeAmount = 100 * 10**18 * (1 + (seed % 10));

            vm.prank(verifiers[i]);
            try truthBounty.vote(claimId, support, stakeAmount) {} catch {}
        }
    }

    function settleClaim(uint256 claimIdx) public {
        if (claimIds.length == 0) return;
        uint256 claimId = claimIds[claimIdx % claimIds.length];

        (, , , , , bool settled, , , ) = truthBounty.claims(claimId);
        if (settled) return;

        if (block.timestamp < 1 days) {
            skip(1 days + 1 hours + 1);
        }

        vm.prank(address(this));
        try truthBounty.settleClaim(claimId) {} catch {}
    }

    function claimRewards(uint256 claimIdx, uint256 verifierIdx) public {
        if (claimIds.length == 0 || verifierIdx >= 5) return;
        uint256 claimId = claimIds[claimIdx % claimIds.length];
        address verifier = verifiers[verifierIdx];

        vm.prank(verifier);
        try truthBounty.claimSettlementRewards(claimId) {} catch {}
    }
}

// This invariant function ensures no settlement enters an invalid reward state 
// regarding the distribution of tokens and remainders.
contract RewardRoundingInvariantTest is StdInvariant, Test {
    RewardRoundingHandler public handler;
    TruthBountyWeighted public truthBounty;
    
    function setUp() public {
        handler = new RewardRoundingHandler();
        truthBounty = handler.truthBounty();

        // Target the handler instead of the truth bounty contract directly
        // to avoid unhandled reverts causing test failures when fail_on_revert = true
        targetContract(address(handler));
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