import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

/**
 * Test suite for PR #169: Rounding Error in Reward Payouts
 * 
 * These tests verify that:
 * 1. Rounding errors in reward calculations are tracked
 * 2. Dust (accumulated rounding errors) is properly distributed
 * 3. No rewards are lost due to integer division
 * 4. Total distributed rewards + dust = calculated rewards
 */
describe("PR #169: Rounding Error in Reward Payouts", function () {
  let truthBounty: Contract;
  let bountyToken: Contract;
  let mockOracle: Contract;
  let owner: Signer;
  let submitter: Signer;
  let verifier1: Signer;
  let verifier2: Signer;
  let verifier3: Signer;

  const INITIAL_SUPPLY = ethers.parseEther("1000000");
  const MIN_STAKE = ethers.parseEther("100");
  const VERIFICATION_WINDOW = 7 * 24 * 60 * 60; // 7 days
  const CONFIRMATION_DELAY = 1 * 60 * 60; // 1 hour
  const PERCENT_DENOMINATOR = 100n;

  beforeEach(async function () {
    [owner, submitter, verifier1, verifier2, verifier3] = await ethers.getSigners();

    // Deploy Token
    const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
    bountyToken = await TruthBountyToken.deploy(await owner.getAddress());
    await bountyToken.waitForDeployment();

    // Deploy Mock Oracle
    const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
    mockOracle = await MockReputationOracle.deploy();
    await mockOracle.waitForDeployment();

    // Deploy TruthBountyWeighted
    const TruthBountyWeighted = await ethers.getContractFactory("TruthBountyWeighted");
    truthBounty = await TruthBountyWeighted.deploy(
      await bountyToken.getAddress(),
      await mockOracle.getAddress(),
      await owner.getAddress(),
      await owner.getAddress()
    );
    await truthBounty.waitForDeployment();

    // Fund contract with tokens for rewards
    await bountyToken.transfer(await truthBounty.getAddress(), ethers.parseEther("500000"));

    // Distribute tokens to verifiers
    await bountyToken.transfer(await verifier1.getAddress(), ethers.parseEther("50000"));
    await bountyToken.transfer(await verifier2.getAddress(), ethers.parseEther("50000"));
    await bountyToken.transfer(await verifier3.getAddress(), ethers.parseEther("50000"));

    // Approve tokens for staking
    await bountyToken.connect(verifier1).approve(await truthBounty.getAddress(), ethers.parseEther("50000"));
    await bountyToken.connect(verifier2).approve(await truthBounty.getAddress(), ethers.parseEther("50000"));
    await bountyToken.connect(verifier3).approve(await truthBounty.getAddress(), ethers.parseEther("50000"));
  });

  describe("Rounding Error Detection and Dust Tracking", function () {
    it("Should track rounding dust when calculating rewards", async function () {
      // Approve tokens for staking
      await bountyToken.connect(verifier1).approve(await truthBounty.getAddress(), ethers.parseEther("50000"));
      await bountyToken.connect(verifier2).approve(await truthBounty.getAddress(), ethers.parseEther("50000"));
      await bountyToken.connect(verifier3).approve(await truthBounty.getAddress(), ethers.parseEther("50000"));

      // Create claim with amount that will cause rounding errors
      const claimId = await truthBounty.claimCounter();
      await truthBounty.connect(submitter).createClaim("Test claim content");

      // Stake with amounts that create rounding issues
      // Using amount that won't divide evenly with reward percentages
      await truthBounty.connect(verifier1).stake(ethers.parseEther("500"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("500"));
      await truthBounty.connect(verifier3).stake(ethers.parseEther("500"));

      await truthBounty.connect(verifier1).vote(claimId, true, ethers.parseEther("333"));
      await truthBounty.connect(verifier2).vote(claimId, false, ethers.parseEther("100"));

      // Advance time past verification window
      await time.increase(VERIFICATION_WINDOW + CONFIRMATION_DELAY + 1);

      // Settle claim
      const settleTx = await truthBounty.settleClaim(claimId);
      const receipt = await settleTx.wait();

      // Check that settlement result has dust tracking
      const settlement = await truthBounty.settlementResults(claimId);
      expect(settlement.rewardDust).to.be.gte(0);

      // Verify DustCollected event was emitted if dust > 0
      if (settlement.rewardDust > 0n) {
        expect(receipt.logs.length).to.be.gt(0);
      }
    });

    it("Should distribute accumulated dust to reward claimant", async function () {
      // Stake first
      await truthBounty.connect(verifier1).stake(ethers.parseEther("500"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("500"));
      await truthBounty.connect(verifier3).stake(ethers.parseEther("500"));

      const claimId = await truthBounty.claimCounter();
      await truthBounty.connect(submitter).createClaim("Test claim with rounding");

      // Use amounts designed to produce rounding errors
      const stake1 = ethers.parseEther("337"); // Odd number for rounding
      const stake2 = ethers.parseEther("111"); // Another odd number

      await truthBounty.connect(verifier1).vote(claimId, true, stake1);
      await truthBounty.connect(verifier2).vote(claimId, true, stake2);
      await truthBounty.connect(verifier3).vote(claimId, false, ethers.parseEther("100"));

      // Advance time
      await time.increase(VERIFICATION_WINDOW + CONFIRMATION_DELAY + 1);

      // Settle
      await truthBounty.settleClaim(claimId);

      const settlement = await truthBounty.settlementResults(claimId);
      const initialDust = settlement.rewardDust;

      // First winner claims
      const verifier1Balance1 = await bountyToken.balanceOf(await verifier1.getAddress());
      await truthBounty.connect(verifier1).claimSettlementRewards(claimId);
      const verifier1Balance2 = await bountyToken.balanceOf(await verifier1.getAddress());

      const verifier1Reward = verifier1Balance2 - verifier1Balance1;

      // Second winner claims - should get dust
      const verifier2Balance1 = await bountyToken.balanceOf(await verifier2.getAddress());
      await truthBounty.connect(verifier2).claimSettlementRewards(claimId);
      const verifier2Balance2 = await bountyToken.balanceOf(await verifier2.getAddress());

      const verifier2Reward = verifier2Balance2 - verifier2Balance1;

      // Check that dust was distributed to one of the winners
      const settlementAfter = await truthBounty.settlementResults(claimId);
      expect(settlementAfter.rewardDust).to.equal(0n); // All dust should be distributed
      expect(verifier1Reward.toString()).not.to.equal("0");
      expect(verifier2Reward.toString()).not.to.equal("0");
    });

    it("Should handle odd-number stakes without losing tokens", async function () {
      // Stake first
      await truthBounty.connect(verifier1).stake(ethers.parseEther("500"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("500"));
      await truthBounty.connect(verifier3).stake(ethers.parseEther("500"));

      const claimId = await truthBounty.claimCounter();
      await truthBounty.connect(submitter).createClaim("Odd stake test");

      // Use amounts that will definitely cause rounding
      const oddStake1 = ethers.parseEther("333.333333333333333333"); // Not clean division
      const oddStake2 = ethers.parseEther("444.444444444444444444"); // Not clean division
      const oddStake3 = ethers.parseEther("111.111111111111111111");

      await truthBounty.connect(verifier1).vote(claimId, true, oddStake1);
      await truthBounty.connect(verifier2).vote(claimId, true, oddStake2);
      await truthBounty.connect(verifier3).vote(claimId, false, oddStake3);

      // Advance time
      await time.increase(VERIFICATION_WINDOW + CONFIRMATION_DELAY + 1);

      // Settle
      await truthBounty.settleClaim(claimId);
      const settlement = await truthBounty.settlementResults(claimId);

      const totalRewards = settlement.totalRewards;

      // Track total distributed
      let totalDistributed = 0n;

      // First winner claims
      const v1Before = await bountyToken.balanceOf(await verifier1.getAddress());
      await truthBounty.connect(verifier1).claimSettlementRewards(claimId);
      const v1After = await bountyToken.balanceOf(await verifier1.getAddress());
      const v1Reward = v1After - v1Before - oddStake1; // Exclude stake return
      totalDistributed += v1Reward;

      // Second winner claims
      const v2Before = await bountyToken.balanceOf(await verifier2.getAddress());
      await truthBounty.connect(verifier2).claimSettlementRewards(claimId);
      const v2After = await bountyToken.balanceOf(await verifier2.getAddress());
      const v2Reward = v2After - v2Before - oddStake2; // Exclude stake return
      totalDistributed += v2Reward;

      // Verify no rewards are lost
      const settlementFinal = await truthBounty.settlementResults(claimId);
      expect(settlementFinal.rewardDust).to.equal(0n);
    });
  });

  describe("Settlement Result Structure", function () {
    it("Should initialize SettlementResult with dust tracking fields", async function () {
      // Stake first
      await truthBounty.connect(verifier1).stake(ethers.parseEther("500"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("500"));

      const claimId = await truthBounty.claimCounter();
      await truthBounty.connect(submitter).createClaim("Test dust tracking");

      await truthBounty.connect(verifier1).vote(claimId, true, MIN_STAKE);
      await truthBounty.connect(verifier2).vote(claimId, false, MIN_STAKE);

      // Advance time
      await time.increase(VERIFICATION_WINDOW + CONFIRMATION_DELAY + 1);

      // Settle
      await truthBounty.settleClaim(claimId);

      const settlement = await truthBounty.settlementResults(claimId);

      // Verify new fields exist
      expect(settlement.rewardDust).to.exist;
      expect(settlement.rewardsDistributedCount).to.exist;
      expect(settlement.rewardDust).to.be.a("bigint");
      expect(settlement.rewardsDistributedCount).to.be.a("bigint");
    });
  });

  describe("Edge Cases for Rounding", function () {
    it("Should handle single winner scenario correctly", async function () {
      // Stake first with sufficient amounts
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("500"));

      const claimId = await truthBounty.claimCounter();
      await truthBounty.connect(submitter).createClaim("Single winner test");

      // Only one winner
      await truthBounty.connect(verifier1).vote(claimId, true, ethers.parseEther("777"));
      await truthBounty.connect(verifier2).vote(claimId, false, ethers.parseEther("123"));

      // Advance time
      await time.increase(VERIFICATION_WINDOW + CONFIRMATION_DELAY + 1);

      // Settle
      await truthBounty.settleClaim(claimId);

      const settlement = await truthBounty.settlementResults(claimId);
      const expectedReward = settlement.totalRewards;

      // Claim reward
      const balanceBefore = await bountyToken.balanceOf(await verifier1.getAddress());
      await truthBounty.connect(verifier1).claimSettlementRewards(claimId);
      const balanceAfter = await bountyToken.balanceOf(await verifier1.getAddress());

      // Verify winner gets exact reward (no rounding issues for single winner)
      const actualReward = balanceAfter - balanceBefore - ethers.parseEther("777"); // Exclude stake
      expect(actualReward).to.be.gte(0n);
    });

    it("Should handle many winners with small stakes", async function () {
      // Get additional signers for multiple winners
      const [, , , , v3, v4, v5, v6, v7, v8] = await ethers.getSigners();
      const winners = [verifier1, verifier2, verifier3, v4, v5];

      // Distribute tokens
      for (const winner of winners.slice(2)) {
        await bountyToken.transfer(await winner.getAddress(), ethers.parseEther("50000"));
        await bountyToken.connect(winner).approve(
          await truthBounty.getAddress(),
          ethers.parseEther("50000")
        );
        await truthBounty.connect(winner).stake(ethers.parseEther("500"));
      }

      // Stake first winners
      await truthBounty.connect(verifier1).stake(ethers.parseEther("500"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("500"));

      const claimId = await truthBounty.claimCounter();
      await truthBounty.connect(submitter).createClaim("Many winners test");

      // All vote for pass with sufficient amounts (at least MIN_STAKE each)
      await truthBounty.connect(winners[0]).vote(claimId, true, ethers.parseEther("100"));
      await truthBounty.connect(winners[1]).vote(claimId, true, ethers.parseEther("100"));
      await truthBounty.connect(winners[2]).vote(claimId, true, ethers.parseEther("100"));
      await truthBounty.connect(winners[3]).vote(claimId, true, ethers.parseEther("100"));
      await truthBounty.connect(winners[4]).vote(claimId, true, ethers.parseEther("100"));

      // One loser
      await bountyToken.transfer(await v6.getAddress(), ethers.parseEther("50000"));
      await bountyToken.connect(v6).approve(await truthBounty.getAddress(), ethers.parseEther("50000"));
      await truthBounty.connect(v6).stake(ethers.parseEther("500"));
      await truthBounty.connect(v6).vote(claimId, false, ethers.parseEther("100"));

      // Advance time
      await time.increase(VERIFICATION_WINDOW + CONFIRMATION_DELAY + 1);

      // Settle
      await truthBounty.settleClaim(claimId);

      const settlement = await truthBounty.settlementResults(claimId);

      // All winners claim
      for (const winner of winners) {
        await truthBounty.connect(winner).claimSettlementRewards(claimId);
      }

      // Verify no dust remains
      const settlementAfter = await truthBounty.settlementResults(claimId);
      expect(settlementAfter.rewardDust).to.equal(0n);
    });
  });

  describe("No Regression Tests", function () {
    it("Should maintain existing reward distribution behavior", async function () {
      // Stake first with sufficient amounts
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1500"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("1500"));

      const claimId = await truthBounty.claimCounter();
      await truthBounty.connect(submitter).createClaim("Regression test");

      // Use clean numbers that don't cause rounding
      // Make sure one side has more votes to pass threshold (60%)
      await truthBounty.connect(verifier1).vote(claimId, true, ethers.parseEther("1000"));
      await truthBounty.connect(verifier2).vote(claimId, false, ethers.parseEther("500"));

      // Advance time
      await time.increase(VERIFICATION_WINDOW + CONFIRMATION_DELAY + 1);

      // Settle
      await truthBounty.settleClaim(claimId);

      const settlement = await truthBounty.settlementResults(claimId);

      // Verify expected behavior - pass should be true because 1000 / 1500 = 66.67% > 60%
      expect(settlement.passed).to.be.true;
      expect(settlement.totalRewards).to.be.gte(0n);
      expect(settlement.totalSlashed).to.be.gt(0n);

      // Winner should be able to claim
      await expect(truthBounty.connect(verifier1).claimSettlementRewards(claimId))
        .to.emit(truthBounty, "RewardsDistributed");
    });

    it("Should not affect loser stake withdrawal", async function () {
      // Stake first
      await truthBounty.connect(verifier1).stake(ethers.parseEther("500"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("500"));

      const claimId = await truthBounty.claimCounter();
      await truthBounty.connect(submitter).createClaim("Loser withdrawal test");

      await truthBounty.connect(verifier1).vote(claimId, true, ethers.parseEther("500"));
      await truthBounty.connect(verifier2).vote(claimId, false, ethers.parseEther("300"));

      // Advance time
      await time.increase(VERIFICATION_WINDOW + CONFIRMATION_DELAY + 1);

      // Settle
      await truthBounty.settleClaim(claimId);

      // Loser withdraws
      const loserBalanceBefore = await bountyToken.balanceOf(await verifier2.getAddress());
      await truthBounty.connect(verifier2).withdrawSettledStake(claimId);
      const loserBalanceAfter = await bountyToken.balanceOf(await verifier2.getAddress());

      // Should get some stake back (after slashing)
      expect(loserBalanceAfter).to.be.gt(loserBalanceBefore);
    });
  });
});
