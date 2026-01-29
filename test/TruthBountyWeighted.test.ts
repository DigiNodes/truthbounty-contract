import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("TruthBountyWeighted", function () {
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

  beforeEach(async function () {
    [owner, submitter, verifier1, verifier2, verifier3] = await ethers.getSigners();

    // Deploy Token
    const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
    bountyToken = await TruthBountyToken.deploy();
    await bountyToken.waitForDeployment();

    // Deploy Mock Oracle
    const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
    mockOracle = await MockReputationOracle.deploy();
    await mockOracle.waitForDeployment();

    // Deploy TruthBountyWeighted
    const TruthBountyWeighted = await ethers.getContractFactory("TruthBountyWeighted");
    truthBounty = await TruthBountyWeighted.deploy(
      await bountyToken.getAddress(),
      await mockOracle.getAddress()
    );
    await truthBounty.waitForDeployment();

    // Fund contract with tokens for rewards
    await bountyToken.transfer(await truthBounty.getAddress(), ethers.parseEther("100000"));

    // Distribute tokens to verifiers
    await bountyToken.transfer(await verifier1.getAddress(), ethers.parseEther("10000"));
    await bountyToken.transfer(await verifier2.getAddress(), ethers.parseEther("10000"));
    await bountyToken.transfer(await verifier3.getAddress(), ethers.parseEther("10000"));

    // Approve spending
    await bountyToken.connect(verifier1).approve(await truthBounty.getAddress(), ethers.MaxUint256);
    await bountyToken.connect(verifier2).approve(await truthBounty.getAddress(), ethers.MaxUint256);
    await bountyToken.connect(verifier3).approve(await truthBounty.getAddress(), ethers.MaxUint256);
  });

  describe("Deployment", function () {
    it("Should set correct token and oracle addresses", async function () {
      expect(await truthBounty.bountyToken()).to.equal(await bountyToken.getAddress());
      expect(await truthBounty.reputationOracle()).to.equal(await mockOracle.getAddress());
    });

    it("Should have weighted staking enabled by default", async function () {
      expect(await truthBounty.weightedStakingEnabled()).to.equal(true);
    });
  });

  describe("Weighted Voting", function () {
    let claimId: bigint;

    beforeEach(async function () {
      // Create claim
      const tx = await truthBounty.connect(submitter).createClaim("QmTestHash");
      const receipt = await tx.wait();
      claimId = 0n; // First claim

      // Stake for all verifiers
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("1000"));
      await truthBounty.connect(verifier3).stake(ethers.parseEther("1000"));
    });

    it("Should calculate effective stake based on reputation when voting", async function () {
      // Set different reputations
      await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("2")); // 2x
      await mockOracle.setReputationScore(await verifier2.getAddress(), ethers.parseEther("1")); // 1x
      await mockOracle.setReputationScore(await verifier3.getAddress(), ethers.parseEther("0.5")); // 0.5x

      const stakeAmount = ethers.parseEther("100");

      // Verifier1 votes (2x weight)
      await expect(
        truthBounty.connect(verifier1).vote(claimId, true, stakeAmount)
      )
        .to.emit(truthBounty, "VoteCast")
        .withArgs(
          claimId,
          await verifier1.getAddress(),
          true,
          stakeAmount,
          ethers.parseEther("200"), // 100 * 2.0
          ethers.parseEther("2")
        );

      // Verifier2 votes (1x weight)
      await expect(
        truthBounty.connect(verifier2).vote(claimId, true, stakeAmount)
      )
        .to.emit(truthBounty, "VoteCast")
        .withArgs(
          claimId,
          await verifier2.getAddress(),
          true,
          stakeAmount,
          ethers.parseEther("100"), // 100 * 1.0
          ethers.parseEther("1")
        );

      // Verifier3 votes (0.5x weight)
      await expect(
        truthBounty.connect(verifier3).vote(claimId, false, stakeAmount)
      )
        .to.emit(truthBounty, "VoteCast")
        .withArgs(
          claimId,
          await verifier3.getAddress(),
          false,
          stakeAmount,
          ethers.parseEther("50"), // 100 * 0.5
          ethers.parseEther("0.5")
        );

      // Check claim totals (should be weighted)
      const claim = await truthBounty.getClaim(claimId);
      expect(claim.totalWeightedFor).to.equal(ethers.parseEther("300")); // 200 + 100
      expect(claim.totalWeightedAgainst).to.equal(ethers.parseEther("50")); // 50
      expect(claim.totalStakeAmount).to.equal(ethers.parseEther("300")); // Raw: 100 + 100 + 100
    });

    it("Should use default reputation for users without score", async function () {
      const stakeAmount = ethers.parseEther("100");

      await truthBounty.connect(verifier1).vote(claimId, true, stakeAmount);

      const vote = await truthBounty.getVote(claimId, await verifier1.getAddress());

      // Should use default (1.0)
      expect(vote.reputationScore).to.equal(ethers.parseEther("1"));
      expect(vote.effectiveStake).to.equal(stakeAmount);
    });

    it("Should apply minimum reputation bound", async function () {
      // Set very low reputation (below minimum)
      await mockOracle.setReputationScore(
        await verifier1.getAddress(),
        ethers.parseEther("0.01") // 1%
      );

      const stakeAmount = ethers.parseEther("100");
      await truthBounty.connect(verifier1).vote(claimId, true, stakeAmount);

      const vote = await truthBounty.getVote(claimId, await verifier1.getAddress());

      // Should be clamped to minimum (0.1)
      expect(vote.reputationScore).to.equal(ethers.parseEther("0.1"));
      expect(vote.effectiveStake).to.equal(ethers.parseEther("10")); // 100 * 0.1
    });

    it("Should apply maximum reputation bound", async function () {
      // Set very high reputation (above maximum)
      await mockOracle.setReputationScore(
        await verifier1.getAddress(),
        ethers.parseEther("50") // 5000%
      );

      const stakeAmount = ethers.parseEther("100");
      await truthBounty.connect(verifier1).vote(claimId, true, stakeAmount);

      const vote = await truthBounty.getVote(claimId, await verifier1.getAddress());

      // Should be clamped to maximum (10)
      expect(vote.reputationScore).to.equal(ethers.parseEther("10"));
      expect(vote.effectiveStake).to.equal(ethers.parseEther("1000")); // 100 * 10
    });
  });

  describe("Weighted Settlement", function () {
    let claimId: bigint;

    beforeEach(async function () {
      const tx = await truthBounty.connect(submitter).createClaim("QmTestHash");
      claimId = 0n;

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("1000"));
      await truthBounty.connect(verifier3).stake(ethers.parseEther("1000"));
    });

    it("Should determine outcome based on weighted votes", async function () {
      // Setup: High reputation votes FOR, low reputation votes AGAINST
      await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("3")); // 3x
      await mockOracle.setReputationScore(await verifier2.getAddress(), ethers.parseEther("0.5")); // 0.5x
      await mockOracle.setReputationScore(await verifier3.getAddress(), ethers.parseEther("0.5")); // 0.5x

      const stakeAmount = ethers.parseEther("100");

      // Verifier1 (3x) votes FOR: effective = 300
      await truthBounty.connect(verifier1).vote(claimId, true, stakeAmount);

      // Verifier2 (0.5x) votes AGAINST: effective = 50
      await truthBounty.connect(verifier2).vote(claimId, false, stakeAmount);

      // Verifier3 (0.5x) votes AGAINST: effective = 50
      await truthBounty.connect(verifier3).vote(claimId, false, stakeAmount);

      // Total weighted FOR: 300
      // Total weighted AGAINST: 100
      // Percentage FOR: 300 / 400 = 75% > 60% threshold
      // Should PASS

      await time.increase(VERIFICATION_WINDOW + 1);

      await expect(truthBounty.settleClaim(claimId))
        .to.emit(truthBounty, "ClaimSettled")
        .withArgs(
          claimId,
          true, // passed
          ethers.parseEther("300"), // weighted for
          ethers.parseEther("100"), // weighted against
          expect.anything(),
          expect.anything()
        );

      const settlement = await truthBounty.settlementResults(claimId);
      expect(settlement.passed).to.equal(true);
    });

    it("Should fail claim when weighted votes are insufficient", async function () {
      // Setup: Low reputation votes FOR, high reputation votes AGAINST
      await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("0.5")); // 0.5x
      await mockOracle.setReputationScore(await verifier2.getAddress(), ethers.parseEther("3")); // 3x
      await mockOracle.setReputationScore(await verifier3.getAddress(), ethers.parseEther("3")); // 3x

      const stakeAmount = ethers.parseEther("100");

      // Verifier1 (0.5x) votes FOR: effective = 50
      await truthBounty.connect(verifier1).vote(claimId, true, stakeAmount);

      // Verifier2 (3x) votes AGAINST: effective = 300
      await truthBounty.connect(verifier2).vote(claimId, false, stakeAmount);

      // Verifier3 (3x) votes AGAINST: effective = 300
      await truthBounty.connect(verifier3).vote(claimId, false, stakeAmount);

      // Total weighted FOR: 50
      // Total weighted AGAINST: 600
      // Percentage FOR: 50 / 650 ≈ 7.7% < 60% threshold
      // Should FAIL

      await time.increase(VERIFICATION_WINDOW + 1);

      await truthBounty.settleClaim(claimId);

      const settlement = await truthBounty.settlementResults(claimId);
      expect(settlement.passed).to.equal(false);
    });

    it("Should distribute rewards proportional to effective stake", async function () {
      // Setup equal raw stakes but different reputations
      await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("2")); // 2x
      await mockOracle.setReputationScore(await verifier2.getAddress(), ethers.parseEther("1")); // 1x

      const stakeAmount = ethers.parseEther("100");

      // Both vote FOR
      await truthBounty.connect(verifier1).vote(claimId, true, stakeAmount);
      await truthBounty.connect(verifier2).vote(claimId, true, stakeAmount);

      // Settle
      await time.increase(VERIFICATION_WINDOW + 1);
      await truthBounty.settleClaim(claimId);

      const settlement = await truthBounty.settlementResults(claimId);

      // Verifier1 has 200 effective stake, Verifier2 has 100 effective stake
      // Total winner weighted stake: 300
      // Verifier1 should get 200/300 = 66.67% of rewards
      // Verifier2 should get 100/300 = 33.33% of rewards

      const totalRewards = settlement.totalRewards;

      const verifier1RewardShare = (totalRewards * 200n) / 300n;
      const verifier2RewardShare = (totalRewards * 100n) / 300n;

      // Claim rewards
      const balanceBefore1 = await bountyToken.balanceOf(await verifier1.getAddress());
      await truthBounty.connect(verifier1).claimSettlementRewards(claimId);
      const balanceAfter1 = await bountyToken.balanceOf(await verifier1.getAddress());

      const balanceBefore2 = await bountyToken.balanceOf(await verifier2.getAddress());
      await truthBounty.connect(verifier2).claimSettlementRewards(claimId);
      const balanceAfter2 = await bountyToken.balanceOf(await verifier2.getAddress());

      // Check proportional distribution (allowing for rounding)
      const reward1 = balanceAfter1 - balanceBefore1 - stakeAmount; // Subtract returned stake
      const reward2 = balanceAfter2 - balanceBefore2 - stakeAmount;

      expect(reward1).to.be.closeTo(verifier1RewardShare, ethers.parseEther("0.01"));
      expect(reward2).to.be.closeTo(verifier2RewardShare, ethers.parseEther("0.01"));
    });
  });

  describe("Equal Weight Fallback", function () {
    let claimId: bigint;

    beforeEach(async function () {
      const tx = await truthBounty.connect(submitter).createClaim("QmTestHash");
      claimId = 0n;

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("1000"));

      // Disable weighted staking
      await truthBounty.setWeightedStakingEnabled(false);
    });

    it("Should use equal weights when weighted staking is disabled", async function () {
      // Set different reputations (should be ignored)
      await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("10"));
      await mockOracle.setReputationScore(await verifier2.getAddress(), ethers.parseEther("0.1"));

      const stakeAmount = ethers.parseEther("100");

      // Both votes should have equal weight
      await truthBounty.connect(verifier1).vote(claimId, true, stakeAmount);
      await truthBounty.connect(verifier2).vote(claimId, false, stakeAmount);

      const claim = await truthBounty.getClaim(claimId);

      // Should be equal (1:1 ratio)
      expect(claim.totalWeightedFor).to.equal(stakeAmount);
      expect(claim.totalWeightedAgainst).to.equal(stakeAmount);
    });
  });

  describe("Preview Effective Stake", function () {
    it("Should preview effective stake correctly", async function () {
      await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("2.5"));

      const [effectiveStake, reputationScore] = await truthBounty.previewEffectiveStake(
        await verifier1.getAddress(),
        ethers.parseEther("1000")
      );

      expect(effectiveStake).to.equal(ethers.parseEther("2500")); // 1000 * 2.5
      expect(reputationScore).to.equal(ethers.parseEther("2.5"));
    });
  });

  describe("Admin Functions", function () {
    it("Should allow owner to update reputation oracle", async function () {
      const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
      const newOracle = await MockReputationOracle.deploy();
      await newOracle.waitForDeployment();

      await expect(truthBounty.setReputationOracle(await newOracle.getAddress()))
        .to.emit(truthBounty, "ReputationOracleUpdated");

      expect(await truthBounty.reputationOracle()).to.equal(await newOracle.getAddress());
    });

    it("Should allow owner to update reputation bounds", async function () {
      await expect(
        truthBounty.setReputationBounds(ethers.parseEther("0.2"), ethers.parseEther("5"))
      )
        .to.emit(truthBounty, "ReputationBoundsUpdated");

      expect(await truthBounty.minReputationScore()).to.equal(ethers.parseEther("0.2"));
      expect(await truthBounty.maxReputationScore()).to.equal(ethers.parseEther("5"));
    });

    it("Should allow owner to toggle weighted staking", async function () {
      await expect(truthBounty.setWeightedStakingEnabled(false))
        .to.emit(truthBounty, "WeightedStakingToggled")
        .withArgs(false);

      expect(await truthBounty.weightedStakingEnabled()).to.equal(false);
    });
  });

  describe("Edge Cases", function () {
    it("Should handle oracle failure gracefully", async function () {
      // Deploy a broken oracle (will be inactive)
      const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
      const brokenOracle = await MockReputationOracle.deploy();
      await brokenOracle.waitForDeployment();
      await brokenOracle.setActive(false);

      await truthBounty.setReputationOracle(await brokenOracle.getAddress());

      // Create claim and stake
      const tx = await truthBounty.connect(submitter).createClaim("QmTestHash");
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));

      // Should use default reputation
      await truthBounty.connect(verifier1).vote(0, true, ethers.parseEther("100"));

      const vote = await truthBounty.getVote(0, await verifier1.getAddress());
      expect(vote.reputationScore).to.equal(ethers.parseEther("1")); // Default
    });
  });
});
