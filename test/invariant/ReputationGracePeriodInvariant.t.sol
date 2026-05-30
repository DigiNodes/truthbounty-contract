// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/TruthBountyWeighted.sol";
import "../contracts/TruthBountyToken.sol";
import "../contracts/MockReputationOracle.sol";

/**
 * @title ReputationGracePeriodInvariant
 * @notice Invariant tests for reputation grace period mechanism
 * @dev Verifies that grace period prevents last-minute reputation boosts
 */
contract ReputationGracePeriodInvariant is Test {
    TruthBountyWeighted public truthBounty;
    TruthBountyToken public bountyToken;
    MockReputationOracle public reputationOracle;

    address public owner = address(0x1);
    address public submitter = address(0x2);
    address public verifier1 = address(0x3);
    address public verifier2 = address(0x4);

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;
    uint256 constant MIN_STAKE = 100 * 10 ** 18;

    function setUp() public {
        // Deploy token
        vm.startPrank(owner);
        bountyToken = new TruthBountyToken(owner);

        // Deploy oracle
        reputationOracle = new MockReputationOracle();

        // Deploy TruthBounty
        truthBounty = new TruthBountyWeighted(
            address(bountyToken),
            address(reputationOracle),
            owner,
            owner
        );

        // Fund contract
        bountyToken.transfer(address(truthBounty), 100_000 * 10 ** 18);
        vm.stopPrank();

        // Fund verifiers
        vm.prank(owner);
        bountyToken.transfer(verifier1, 10_000 * 10 ** 18);
        vm.prank(owner);
        bountyToken.transfer(verifier2, 10_000 * 10 ** 18);

        // Setup verifiers
        vm.startPrank(verifier1);
        bountyToken.approve(address(truthBounty), 10_000 * 10 ** 18);
        truthBounty.deposit(1_000 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(verifier2);
        bountyToken.approve(address(truthBounty), 10_000 * 10 ** 18);
        truthBounty.deposit(1_000 * 10 ** 18);
        vm.stopPrank();

        // Set initial reputation
        vm.startPrank(owner);
        reputationOracle.setReputationScore(verifier1, 1 * 10 ** 18);
        reputationOracle.setReputationScore(verifier2, 1 * 10 ** 18);
        vm.stopPrank();
    }

    /**
     * @notice Invariant: Votes with updated reputation within grace period should use default score
     * @dev If reputation is updated within grace period, the vote's reputation score must be default
     */
    function invariant_GracePeriodEnforced() public {
        // Create claim
        uint256 claimId = _createClaim();

        // Get claim creation time
        TruthBountyWeighted.Claim memory claim = truthBounty.getClaim(claimId);
        uint256 claimCreatedAt = claim.createdAt;
        uint256 gracePeriod = truthBounty.reputationUpdateGracePeriod();

        // Boost reputation shortly after claim creation
        vm.prank(owner);
        reputationOracle.setReputationScore(verifier1, 10 * 10 ** 18);

        // Verify update timestamp is within grace period
        uint256 lastUpdate = reputationOracle.getLastReputationUpdate(verifier1);
        uint256 timeDiff = lastUpdate > claimCreatedAt
            ? lastUpdate - claimCreatedAt
            : claimCreatedAt - lastUpdate;

        // If within grace period, voting should use default reputation
        if (timeDiff <= gracePeriod) {
            vm.prank(verifier1);
            truthBounty.vote(claimId, true, MIN_STAKE);

            TruthBountyWeighted.Vote memory vote = truthBounty.getVote(claimId, verifier1);
            assertEq(vote.reputationScore, truthBounty.defaultReputationScore(),
                "Vote must use default reputation within grace period");
        }
    }

    /**
     * @notice Invariant: Votes outside grace period should use actual reputation
     * @dev If reputation is updated outside grace period, the vote should use the actual score
     */
    function invariant_OutsideGracePeriodUsesActualReputation() public {
        // Set old reputation
        vm.prank(owner);
        reputationOracle.setReputationScore(verifier1, 2 * 10 ** 18);

        // Move time forward beyond grace period
        uint256 gracePeriod = truthBounty.reputationUpdateGracePeriod();
        skip(gracePeriod + 1);

        // Create claim
        uint256 claimId = _createClaim();

        // Vote should use the old (now outside grace period) reputation
        vm.prank(verifier1);
        truthBounty.vote(claimId, true, MIN_STAKE);

        TruthBountyWeighted.Vote memory vote = truthBounty.getVote(claimId, verifier1);
        assertEq(vote.reputationScore, 2 * 10 ** 18,
            "Vote should use actual reputation outside grace period");
    }

    /**
     * @notice Invariant: Grace period window is symmetric around claim creation
     * @dev Updates before and after claim creation within grace period should be restricted
     */
    function invariant_GracePeriodSymmetry() public {
        uint256 gracePeriod = truthBounty.reputationUpdateGracePeriod();

        // Scenario 1: Update before claim, within grace period
        vm.prank(owner);
        reputationOracle.setReputationScore(verifier1, 5 * 10 ** 18);

        // Move forward but less than grace period
        skip(gracePeriod / 2);

        uint256 claimId1 = _createClaim();
        vm.prank(verifier1);
        truthBounty.vote(claimId1, true, MIN_STAKE);

        TruthBountyWeighted.Vote memory vote1 = truthBounty.getVote(claimId1, verifier1);
        assertEq(vote1.reputationScore, truthBounty.defaultReputationScore(),
            "Grace period should apply to updates before claim");

        // Scenario 2: Update after claim, within grace period
        uint256 claimId2 = _createClaim();
        
        // Update reputation right after claim (within grace period)
        vm.prank(owner);
        reputationOracle.setReputationScore(verifier2, 8 * 10 ** 18);

        vm.prank(verifier2);
        truthBounty.vote(claimId2, false, MIN_STAKE);

        TruthBountyWeighted.Vote memory vote2 = truthBounty.getVote(claimId2, verifier2);
        assertEq(vote2.reputationScore, truthBounty.defaultReputationScore(),
            "Grace period should apply to updates after claim");
    }

    /**
     * @notice Invariant: Grace period prevents weighted stake manipulation
     * @dev Effective stake should not be artificially boosted by last-minute reputation updates
     */
    function invariant_EffectiveStakeNotManipulated() public {
        // Create baseline claim with verifier1 at default reputation
        uint256 claimId1 = _createClaim();
        vm.prank(verifier1);
        truthBounty.vote(claimId1, true, MIN_STAKE);

        TruthBountyWeighted.Vote memory baselineVote = truthBounty.getVote(claimId1, verifier1);
        uint256 baselineEffectiveStake = baselineVote.effectiveStake;

        // Try to boost and vote again
        vm.prank(owner);
        reputationOracle.setReputationScore(verifier1, 100 * 10 ** 18);

        uint256 claimId2 = _createClaim();
        vm.prank(verifier1);
        truthBounty.vote(claimId2, true, MIN_STAKE);

        TruthBountyWeighted.Vote memory boostedVote = truthBounty.getVote(claimId2, verifier1);

        // Effective stake should be the same (both using default reputation)
        assertEq(boostedVote.effectiveStake, baselineEffectiveStake,
            "Effective stake should not change due to grace period protection");
    }

    /**
     * @notice Invariant: Grace period window bounds are respected
     * @dev Grace period parameter must stay within min/max bounds
     */
    function invariant_GracePeriodBoundsEnforced() public view {
        uint256 gracePeriod = truthBounty.reputationUpdateGracePeriod();

        // Check minimum bound
        assertGe(gracePeriod, 1 hours,
            "Grace period must be at least 1 hour");

        // Check maximum bound
        assertLe(gracePeriod, 30 days,
            "Grace period must be at most 30 days");
    }

    /**
     * @notice Invariant: Multiple voters voting on same claim should have independent grace period calculations
     * @dev Each voter's reputation update timing should be evaluated independently
     */
    function invariant_IndependentVoterGracePeriods() public {
        uint256 gracePeriod = truthBounty.reputationUpdateGracePeriod();

        // Verifier1: Update old reputation
        vm.prank(owner);
        reputationOracle.setReputationScore(verifier1, 5 * 10 ** 18);

        // Wait beyond grace period
        skip(gracePeriod + 1);

        // Create claim
        uint256 claimId = _createClaim();

        // Verifier2: Update reputation right now (within grace period of claim)
        vm.prank(owner);
        reputationOracle.setReputationScore(verifier2, 5 * 10 ** 18);

        // Both vote
        vm.prank(verifier1);
        truthBounty.vote(claimId, true, MIN_STAKE);

        vm.prank(verifier2);
        truthBounty.vote(claimId, false, MIN_STAKE);

        // Verifier1 should use actual (5x) reputation
        TruthBountyWeighted.Vote memory vote1 = truthBounty.getVote(claimId, verifier1);
        assertEq(vote1.reputationScore, 5 * 10 ** 18,
            "Verifier1 outside grace period should use actual reputation");

        // Verifier2 should use default (1x) reputation
        TruthBountyWeighted.Vote memory vote2 = truthBounty.getVote(claimId, verifier2);
        assertEq(vote2.reputationScore, truthBounty.defaultReputationScore(),
            "Verifier2 within grace period should use default reputation");

        // Effective stakes should reflect the difference
        assertGt(vote1.effectiveStake, vote2.effectiveStake,
            "Verifier1 should have higher effective stake");
    }

    // ============ Helper Functions ============

    function _createClaim() internal returns (uint256) {
        vm.startPrank(submitter);
        bountyToken.approve(address(truthBounty), MIN_STAKE);
        uint256 claimId = truthBounty.createClaim("Test claim content");
        vm.stopPrank();
        return claimId;
    }
}
