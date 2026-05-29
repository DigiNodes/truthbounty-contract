import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

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

    it("Should expose named constants for weighted staking defaults", async function () {
      expect(await truthBounty.TOKEN_DECIMALS_MULTIPLIER()).to.equal(ethers.parseEther("1"));
      expect(await truthBounty.BASE_MULTIPLIER()).to.equal(
        await truthBounty.TOKEN_DECIMALS_MULTIPLIER()
      );
      expect(await truthBounty.PERCENT_DENOMINATOR()).to.equal(PERCENT_DENOMINATOR);
      expect(await truthBounty.DEFAULT_VERIFICATION_WINDOW_DURATION()).to.equal(
        BigInt(VERIFICATION_WINDOW)
      );
      expect(await truthBounty.MIN_VERIFICATION_WINDOW_DURATION()).to.equal(BigInt(24 * 60 * 60));
      expect(await truthBounty.MAX_VERIFICATION_WINDOW_DURATION()).to.equal(
        BigInt(30 * 24 * 60 * 60)
      );
      expect(await truthBounty.DEFAULT_MIN_STAKE_AMOUNT()).to.equal(MIN_STAKE);
      expect(await truthBounty.DEFAULT_SETTLEMENT_THRESHOLD_PERCENT()).to.equal(60n);
      expect(await truthBounty.DEFAULT_REWARD_PERCENT()).to.equal(80n);
      expect(await truthBounty.DEFAULT_SLASH_PERCENT()).to.equal(20n);
      expect(await truthBounty.MIN_REPUTATION_SCORE()).to.equal(ethers.parseEther("0.1"));
      expect(await truthBounty.MAX_REPUTATION_SCORE()).to.equal(ethers.parseEther("10"));
      expect(await truthBounty.DEFAULT_REPUTATION_SCORE()).to.equal(ethers.parseEther("1"));
    });

    it("Should initialize configurable parameters from named defaults", async function () {
      expect(await truthBounty.verificationWindowDuration()).to.equal(
        await truthBounty.DEFAULT_VERIFICATION_WINDOW_DURATION()
      );
      expect(await truthBounty.minStakeAmount()).to.equal(
        await truthBounty.DEFAULT_MIN_STAKE_AMOUNT()
      );
      expect(await truthBounty.settlementThresholdPercent()).to.equal(
        await truthBounty.DEFAULT_SETTLEMENT_THRESHOLD_PERCENT()
      );
      expect(await truthBounty.rewardPercent()).to.equal(await truthBounty.DEFAULT_REWARD_PERCENT());
      expect(await truthBounty.slashPercent()).to.equal(await truthBounty.DEFAULT_SLASH_PERCENT());
      expect(await truthBounty.minReputationScore()).to.equal(
        await truthBounty.MIN_REPUTATION_SCORE()
      );
      expect(await truthBounty.maxReputationScore()).to.equal(
        await truthBounty.MAX_REPUTATION_SCORE()
      );
      expect(await truthBounty.defaultReputationScore()).to.equal(
        await truthBounty.DEFAULT_REPUTATION_SCORE()
      );
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

      await time.increase(VERIFICATION_WINDOW + 3601);

      await expect(truthBounty.settleClaim(claimId))
        .to.emit(truthBounty, "ClaimSettled")
        .withArgs(
          claimId,
          true, // passed
          ethers.parseEther("300"), // weighted for
          ethers.parseEther("100"), // weighted against
          anyValue,
          anyValue
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

      await time.increase(VERIFICATION_WINDOW + 3601);

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
      await time.increase(VERIFICATION_WINDOW + 3601);
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

    it("Should preserve settlement-time slash amounts when governance parameters change", async function () {
      const stakeAmount = ethers.parseEther("100");

      await truthBounty.connect(verifier1).vote(claimId, true, stakeAmount);
      await truthBounty.connect(verifier2).vote(claimId, false, stakeAmount);

      await time.increase(VERIFICATION_WINDOW + 3601);
      await truthBounty.settleClaim(claimId);

      const losingVote = await truthBounty.getVote(claimId, await verifier1.getAddress());
      expect(losingVote.slashAmount).to.equal(ethers.parseEther("20"));

      await truthBounty.setSlashPercent(100);

      const balanceBefore = await bountyToken.balanceOf(await verifier1.getAddress());
      await truthBounty.connect(verifier1).withdrawSettledStake(claimId);
      const balanceAfter = await bountyToken.balanceOf(await verifier1.getAddress());

      expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("80"));

      const verifierStake = await truthBounty.getVerifierStake(await verifier1.getAddress());
      expect(verifierStake.totalStaked).to.equal(ethers.parseEther("980"));
      expect(verifierStake.activeStakes).to.equal(0);
    });
  });

  describe("Pause Guards", function () {
    let claimId: bigint;

    beforeEach(async function () {
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("1000"));

      await truthBounty.connect(submitter).createClaim("QmPausedClaim");
      claimId = 0n;

      await truthBounty.connect(verifier1).vote(claimId, true, ethers.parseEther("100"));
      await truthBounty.connect(verifier2).vote(claimId, false, ethers.parseEther("100"));
    });

    it("Should revert settleClaim when paused", async function () {
      await time.increase(VERIFICATION_WINDOW + 3601);
      await truthBounty.pause();

      await expect(truthBounty.settleClaim(claimId)).to.be.revertedWithCustomError(
        truthBounty,
        "EnforcedPause"
      );
    });

    it("Should revert claimSettlementRewards when paused", async function () {
      await time.increase(VERIFICATION_WINDOW + 3601);
      await truthBounty.settleClaim(claimId);
      await truthBounty.pause();

      await expect(
        truthBounty.connect(verifier2).claimSettlementRewards(claimId)
      ).to.be.revertedWithCustomError(truthBounty, "EnforcedPause");
    });

    it("Should revert withdrawStake when paused", async function () {
      await truthBounty.pause();

      await expect(
        truthBounty.connect(verifier1).withdrawStake(ethers.parseEther("100"))
      ).to.be.revertedWithCustomError(truthBounty, "EnforcedPause");
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

    it("Should allow owner to update minimum stake amount and enforce it for new votes", async function () {
      const newMinStake = ethers.parseEther("200");

      await expect(truthBounty.setMinStakeAmount(newMinStake))
        .to.emit(truthBounty, "ParameterUpdatedByGovernance")
        .withArgs(
          await truthBounty.GOVERNANCE_PARAM_MIN_STAKE(),
          ethers.parseEther("100"),
          newMinStake
        );

      expect(await truthBounty.minStakeAmount()).to.equal(newMinStake);

      // Stake below the new minimum should fail
      await expect(truthBounty.connect(verifier1).stake(ethers.parseEther("150")))
        .to.be.revertedWith("Stake below minimum");

      // Stake equal to the new minimum should succeed
      await expect(truthBounty.connect(verifier1).stake(newMinStake))
        .to.emit(truthBounty, "StakeDeposited")
        .withArgs(await verifier1.getAddress(), newMinStake);
    });
  });

  describe("Reorg Protection", function () {
    let claimId: bigint;
    const CONFIRMATION_DELAY = 3600; // 1 hour default

    beforeEach(async function () {
      await truthBounty.connect(submitter).createClaim("QmReorgTest");
      claimId = 0n;

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("1000"));

      await truthBounty.connect(verifier1).vote(claimId, true, ethers.parseEther("100"));
      await truthBounty.connect(verifier2).vote(claimId, false, ethers.parseEther("100"));
    });

    it("Should revert settleClaim if called immediately after window closes (before confirmation delay)", async function () {
      // Only advance past the verification window — NOT past the confirmation delay
      await time.increase(VERIFICATION_WINDOW + 1);

      await expect(truthBounty.settleClaim(claimId)).to.be.revertedWith(
        "Confirmation delay pending"
      );
    });

    it("Should allow settleClaim after both verification window and confirmation delay have elapsed", async function () {
      await time.increase(VERIFICATION_WINDOW + CONFIRMATION_DELAY + 1);

      await expect(truthBounty.settleClaim(claimId)).to.emit(truthBounty, "ClaimSettled");
    });

    it("Should allow governance to update confirmationDelay", async function () {
      const newDelay = 2 * 3600; // 2 hours

      await expect(truthBounty.setConfirmationDelay(newDelay))
        .to.emit(truthBounty, "ParameterUpdatedByGovernance")
        .withArgs(
          await truthBounty.GOVERNANCE_PARAM_CONFIRMATION_DELAY(),
          CONFIRMATION_DELAY,
          newDelay
        );

      expect(await truthBounty.confirmationDelay()).to.equal(newDelay);
    });

    it("Should reject setConfirmationDelay above 7 days", async function () {
      const tooLong = 8 * 24 * 60 * 60; // 8 days

      await expect(truthBounty.setConfirmationDelay(tooLong)).to.be.revertedWith(
        "Invalid duration"
      );
    });

    it("Should reject setting confirmationDelay below 5 minutes (Reorg protection)", async function () {
      await expect(truthBounty.setConfirmationDelay(0)).to.be.revertedWith(
        "Invalid duration"
      );
      
      const fourMinutes = 4 * 60;
      await expect(truthBounty.setConfirmationDelay(fourMinutes)).to.be.revertedWith(
        "Invalid duration"
      );
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
    describe("BountyToken Change Mechanism", function () {
    it("Should allow the owner to update the bounty token address", async function () {
      const TruthBountyTokenFactory = await ethers.getContractFactory("TruthBountyToken");
      const newToken = await TruthBountyTokenFactory.deploy(await owner.getAddress());
      await newToken.waitForDeployment();

      // Directly execute the change mechanism
      await truthBounty.updateBountyToken(await newToken.getAddress());
        
      expect(await truthBounty.bountyToken()).to.equal(await newToken.getAddress());
    });

    it("Should fail if a non-owner tries to update the bounty token address", async function () {
      const randomAddress = "0x0000000000000000000000000000000000000001";
      
      await expect(
        truthBounty.connect(verifier1).updateBountyToken(randomAddress)
      ).to.be.revertedWith("Unauthorized");
    });
  });
});
