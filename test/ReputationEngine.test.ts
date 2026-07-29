import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { ReputationEngine, MockGovernanceController } from "../typechain-types";

describe("ReputationEngine", function () {
  let reputationEngine: ReputationEngine;
  let mockGovernance: MockGovernanceController;
  let admin: SignerWithAddress;
  let updateRole: SignerWithAddress;
  let pauser: SignerWithAddress;
  let verifier1: SignerWithAddress;
  let verifier2: SignerWithAddress;
  let user: SignerWithAddress;

  const BASE_MULTIPLIER = 1e18;
  const DEFAULT_INITIAL_SCORE = 1e18;
  const MIN_REPUTATION_SCORE = 1e17;
  const MAX_REPUTATION_SCORE = 10e18;

  beforeEach(async function () {
    [admin, updateRole, pauser, verifier1, verifier2, user] = await ethers.getSigners();

    // Deploy mock governance controller
    const MockGovernanceFactory = await ethers.getContractFactory("MockGovernanceController");
    mockGovernance = await MockGovernanceFactory.deploy(admin.address);

    // Deploy ReputationEngine
    const ReputationEngineFactory = await ethers.getContractFactory("ReputationEngine");
    reputationEngine = await ReputationEngineFactory.deploy(
      admin.address,
      await mockGovernance.getAddress()
    );

    // Grant roles
    await reputationEngine.connect(admin).grantRole(
      await reputationEngine.UPDATE_ROLE(),
      updateRole.address
    );
    await reputationEngine.connect(admin).grantRole(
      await reputationEngine.PAUSER_ROLE(),
      pauser.address
    );
  });

  describe("Deployment", function () {
    it("Should set the correct admin", async function () {
      expect(await reputationEngine.hasRole(await reputationEngine.DEFAULT_ADMIN_ROLE(), admin.address)).to.be.true;
    });

    it("Should set the correct default initial score", async function () {
      expect(await reputationEngine.defaultInitialScore()).to.equal(DEFAULT_INITIAL_SCORE);
    });

    it("Should set the correct reputation bounds", async function () {
      expect(await reputationEngine.minReputationScore()).to.equal(MIN_REPUTATION_SCORE);
      expect(await reputationEngine.maxReputationScore()).to.equal(MAX_REPUTATION_SCORE);
    });

    it("Should initialize protocol stats to zero", async function () {
      const stats = await reputationEngine.getStatistics();
      expect(stats.totalVerifiers).to.equal(0);
      expect(stats.totalSuccessfulVerifications).to.equal(0);
      expect(stats.totalFailedVerifications).to.equal(0);
      expect(stats.totalDisputedClaims).to.equal(0);
      expect(stats.totalRewardsEarned).to.equal(0);
      expect(stats.totalStakeParticipated).to.equal(0);
    });
  });

  describe("Reputation Initialization", function () {
    it("Should initialize reputation for a new verifier", async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);

      const reputation = await reputationEngine.getReputation(verifier1.address);
      expect(reputation.exists).to.be.true;
      expect(reputation.score).to.equal(DEFAULT_INITIAL_SCORE);
      expect(reputation.successfulVerifications).to.equal(0);
      expect(reputation.failedVerifications).to.equal(0);
      expect(reputation.disputedVerifications).to.equal(0);
      expect(reputation.totalStake).to.equal(0);
    });

    it("Should increment total verifiers count", async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);
      await reputationEngine.connect(verifier2).initializeReputation(verifier2.address);

      const stats = await reputationEngine.getStatistics();
      expect(stats.totalVerifiers).to.equal(2);
    });

    it("Should emit ReputationCreated event", async function () {
      await expect(reputationEngine.connect(verifier1).initializeReputation(verifier1.address))
        .to.emit(reputationEngine, "ReputationCreated")
        .withArgs(verifier1.address);
    });

    it("Should emit ReputationInitialized event", async function () {
      await expect(reputationEngine.connect(verifier1).initializeReputation(verifier1.address))
        .to.emit(reputationEngine, "ReputationInitialized")
        .withArgs(verifier1.address, DEFAULT_INITIAL_SCORE, await ethers.provider.getBlock("latest").then(b => b!.timestamp));
    });

    it("Should revert when initializing duplicate verifier", async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);

      await expect(
        reputationEngine.connect(verifier1).initializeReputation(verifier1.address)
      ).to.be.revertedWithCustomError(reputationEngine, "VerifierAlreadyExists");
    });

    it("Should revert when initializing with zero address", async function () {
      await expect(
        reputationEngine.connect(user).initializeReputation(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(reputationEngine, "InvalidZeroAddress");
    });

    it("Should allow initialization with custom score by UPDATE_ROLE", async function () {
      const customScore = 2e18;
      await reputationEngine.connect(updateRole).initializeReputationWithScore(
        verifier1.address,
        customScore
      );

      const reputation = await reputationEngine.getReputation(verifier1.address);
      expect(reputation.score).to.equal(customScore);
    });

    it("Should revert when non-UPDATE_ROLE tries custom initialization", async function () {
      await expect(
        reputationEngine.connect(verifier1).initializeReputationWithScore(
          verifier1.address,
          2e18
        )
      ).to.be.reverted;
    });

    it("Should revert when custom score is below minimum", async function () {
      await expect(
        reputationEngine.connect(updateRole).initializeReputationWithScore(
          verifier1.address,
          MIN_REPUTATION_SCORE - 1
        )
      ).to.be.revertedWithCustomError(reputationEngine, "InvalidReputationScore");
    });

    it("Should revert when custom score is above maximum", async function () {
      await expect(
        reputationEngine.connect(updateRole).initializeReputationWithScore(
          verifier1.address,
          MAX_REPUTATION_SCORE + 1
        )
      ).to.be.revertedWithCustomError(reputationEngine, "InvalidReputationScore");
    });

    it("Should respect initialization restriction when enabled", async function () {
      await reputationEngine.connect(admin).setInitializationRestriction(true);

      await expect(
        reputationEngine.connect(verifier1).initializeReputation(verifier1.address)
      ).to.be.revertedWithCustomError(reputationEngine, "UnauthorizedUpdate");
    });

    it("Should allow UPDATE_ROLE to initialize even when restricted", async function () {
      await reputationEngine.connect(admin).setInitializationRestriction(true);

      await reputationEngine.connect(updateRole).initializeReputation(verifier1.address);

      expect(await reputationEngine.reputationExists(verifier1.address)).to.be.true;
    });
  });

  describe("Reputation Retrieval", function () {
    beforeEach(async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);
    });

    it("Should get full reputation record", async function () {
      const reputation = await reputationEngine.getReputation(verifier1.address);
      expect(reputation.exists).to.be.true;
      expect(reputation.score).to.equal(DEFAULT_INITIAL_SCORE);
    });

    it("Should get reputation score", async function () {
      const score = await reputationEngine.getReputationScore(verifier1.address);
      expect(score).to.equal(DEFAULT_INITIAL_SCORE);
    });

    it("Should check if reputation exists", async function () {
      expect(await reputationEngine.reputationExists(verifier1.address)).to.be.true;
      expect(await reputationEngine.reputationExists(verifier2.address)).to.be.false;
    });

    it("Should revert when getting reputation for non-existent verifier", async function () {
      await expect(
        reputationEngine.getReputation(verifier2.address)
      ).to.be.revertedWithCustomError(reputationEngine, "VerifierNotFound");
    });

    it("Should revert when getting reputation score for non-existent verifier", async function () {
      await expect(
        reputationEngine.getReputationScore(verifier2.address)
      ).to.be.revertedWithCustomError(reputationEngine, "VerifierNotFound");
    });
  });

  describe("Reputation Weight Calculation", function () {
    beforeEach(async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);
    });

    it("Should calculate reputation multiplier for default score", async function () {
      const multiplier = await reputationEngine.calculateReputationMultiplier(verifier1.address);
      expect(multiplier).to.equal(BASE_MULTIPLIER);
    });

    it("Should calculate reputation multiplier for custom score", async function () {
      await reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, 2e18);
      
      const multiplier = await reputationEngine.calculateReputationMultiplier(verifier1.address);
      expect(multiplier).to.equal(2e18);
    });

    it("Should cap multiplier at 10x", async function () {
      await reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, 20e18);
      
      const multiplier = await reputationEngine.calculateReputationMultiplier(verifier1.address);
      expect(multiplier).to.equal(10e18);
    });

    it("Should calculate verification weight", async function () {
      const stakeAmount = 1000e18;
      const weight = await reputationEngine.calculateWeight(stakeAmount, verifier1.address);
      
      expect(weight).to.equal(stakeAmount); // 1x multiplier for default score
    });

    it("Should calculate verification weight with custom reputation", async function () {
      await reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, 2e18);
      
      const stakeAmount = 1000e18;
      const weight = await reputationEngine.calculateWeight(stakeAmount, verifier1.address);
      
      expect(weight).to.equal(stakeAmount * 2); // 2x multiplier
    });

    it("Should revert when calculating multiplier for non-existent verifier", async function () {
      await expect(
        reputationEngine.calculateReputationMultiplier(verifier2.address)
      ).to.be.revertedWithCustomError(reputationEngine, "VerifierNotFound");
    });

    it("Should revert when calculating weight for non-existent verifier", async function () {
      await expect(
        reputationEngine.calculateWeight(1000e18, verifier2.address)
      ).to.be.revertedWithCustomError(reputationEngine, "VerifierNotFound");
    });
  });

  describe("View Helpers", function () {
    beforeEach(async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);
    });

    it("Should check if verifier is eligible", async function () {
      expect(await reputationEngine.isEligibleVerifier(verifier1.address)).to.be.true;
      expect(await reputationEngine.isEligibleVerifier(verifier2.address)).to.be.false;
    });

    it("Should get protocol statistics", async function () {
      const stats = await reputationEngine.getStatistics();
      expect(stats.totalVerifiers).to.equal(1);
    });

    it("Should get verifier statistics", async function () {
      const stats = await reputationEngine.getVerifierStatistics(verifier1.address);
      expect(stats.successfulVerifications).to.equal(0);
      expect(stats.failedVerifications).to.equal(0);
      expect(stats.disputedVerifications).to.equal(0);
      expect(stats.totalStake).to.equal(0);
    });

    it("Should revert when getting statistics for non-existent verifier", async function () {
      await expect(
        reputationEngine.getVerifierStatistics(verifier2.address)
      ).to.be.revertedWithCustomError(reputationEngine, "VerifierNotFound");
    });
  });

  describe("Reputation Update Functions", function () {
    beforeEach(async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);
      await reputationEngine.connect(verifier2).initializeReputation(verifier2.address);
    });

    it("Should update reputation score by UPDATE_ROLE", async function () {
      const newScore = 2e18;
      await reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, newScore);

      const reputation = await reputationEngine.getReputation(verifier1.address);
      expect(reputation.score).to.equal(newScore);
    });

    it("Should emit ReputationScoreUpdated event", async function () {
      const newScore = 2e18;
      await expect(reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, newScore))
        .to.emit(reputationEngine, "ReputationScoreUpdated")
        .withArgs(verifier1.address, DEFAULT_INITIAL_SCORE, newScore, await ethers.provider.getBlock("latest").then(b => b!.timestamp));
    });

    it("Should revert when updating score below minimum", async function () {
      await expect(
        reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, MIN_REPUTATION_SCORE - 1)
      ).to.be.revertedWithCustomError(reputationEngine, "InvalidReputationScore");
    });

    it("Should revert when updating score above maximum", async function () {
      await expect(
        reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, MAX_REPUTATION_SCORE + 1)
      ).to.be.revertedWithCustomError(reputationEngine, "InvalidReputationScore");
    });

    it("Should revert when non-UPDATE_ROLE updates score", async function () {
      await expect(
        reputationEngine.connect(verifier1).updateReputationScore(verifier1.address, 2e18)
      ).to.be.reverted;
    });

    it("Should record successful verification", async function () {
      const stakeAmount = 1000e18;
      await reputationEngine.connect(updateRole).recordSuccessfulVerification(verifier1.address, stakeAmount);

      const reputation = await reputationEngine.getReputation(verifier1.address);
      expect(reputation.successfulVerifications).to.equal(1);
      expect(reputation.totalStake).to.equal(stakeAmount);

      const stats = await reputationEngine.getStatistics();
      expect(stats.totalSuccessfulVerifications).to.equal(1);
      expect(stats.totalStakeParticipated).to.equal(stakeAmount);
    });

    it("Should emit VerificationStatsUpdated on successful verification", async function () {
      const stakeAmount = 1000e18;
      await expect(reputationEngine.connect(updateRole).recordSuccessfulVerification(verifier1.address, stakeAmount))
        .to.emit(reputationEngine, "VerificationStatsUpdated");
    });

    it("Should record failed verification", async function () {
      const stakeAmount = 1000e18;
      await reputationEngine.connect(updateRole).recordFailedVerification(verifier1.address, stakeAmount);

      const reputation = await reputationEngine.getReputation(verifier1.address);
      expect(reputation.failedVerifications).to.equal(1);
      expect(reputation.totalStake).to.equal(stakeAmount);

      const stats = await reputationEngine.getStatistics();
      expect(stats.totalFailedVerifications).to.equal(1);
      expect(stats.totalStakeParticipated).to.equal(stakeAmount);
    });

    it("Should record disputed claim", async function () {
      const stakeAmount = 1000e18;
      await reputationEngine.connect(updateRole).recordDisputedClaim(verifier1.address, stakeAmount);

      const reputation = await reputationEngine.getReputation(verifier1.address);
      expect(reputation.disputedVerifications).to.equal(1);
      expect(reputation.totalStake).to.equal(stakeAmount);

      const stats = await reputationEngine.getStatistics();
      expect(stats.totalDisputedClaims).to.equal(1);
      expect(stats.totalStakeParticipated).to.equal(stakeAmount);
    });

    it("Should record reward earned", async function () {
      const rewardAmount = 500e18;
      await reputationEngine.connect(updateRole).recordRewardEarned(verifier1.address, rewardAmount);

      const stats = await reputationEngine.getStatistics();
      expect(stats.totalRewardsEarned).to.equal(rewardAmount);
    });

    it("Should batch update verification statistics", async function () {
      const verifiers = [verifier1.address, verifier2.address];
      const successCount = [5, 3];
      const failCount = [2, 1];
      const disputeCount = [1, 0];

      await reputationEngine.connect(updateRole).batchUpdateVerificationStats(
        verifiers,
        successCount,
        failCount,
        disputeCount
      );

      const rep1 = await reputationEngine.getReputation(verifier1.address);
      expect(rep1.successfulVerifications).to.equal(5);
      expect(rep1.failedVerifications).to.equal(2);
      expect(rep1.disputedVerifications).to.equal(1);

      const rep2 = await reputationEngine.getReputation(verifier2.address);
      expect(rep2.successfulVerifications).to.equal(3);
      expect(rep2.failedVerifications).to.equal(1);
      expect(rep2.disputedVerifications).to.equal(0);

      const stats = await reputationEngine.getStatistics();
      expect(stats.totalSuccessfulVerifications).to.equal(8);
      expect(stats.totalFailedVerifications).to.equal(3);
      expect(stats.totalDisputedClaims).to.equal(1);
    });

    it("Should revert on batch update with array length mismatch", async function () {
      await expect(
        reputationEngine.connect(updateRole).batchUpdateVerificationStats(
          [verifier1.address, verifier2.address],
          [5, 3],
          [2], // Wrong length
          [1, 0]
        )
      ).to.be.revertedWith("Array length mismatch");
    });

    it("Should revert when non-UPDATE_ROLE records verification", async function () {
      await expect(
        reputationEngine.connect(verifier1).recordSuccessfulVerification(verifier1.address, 1000e18)
      ).to.be.reverted;
    });
  });

  describe("Governance Functions", function () {
    it("Should set reputation bounds by admin", async function () {
      const newMin = 5e17;
      const newMax = 5e18;

      await reputationEngine.connect(admin).setReputationBounds(newMin, newMax);

      expect(await reputationEngine.minReputationScore()).to.equal(newMin);
      expect(await reputationEngine.maxReputationScore()).to.equal(newMax);
    });

    it("Should emit ReputationBoundsUpdated event", async function () {
      const newMin = 5e17;
      const newMax = 5e18;

      await expect(reputationEngine.connect(admin).setReputationBounds(newMin, newMax))
        .to.emit(reputationEngine, "ReputationBoundsUpdated")
        .withArgs(MIN_REPUTATION_SCORE, MAX_REPUTATION_SCORE, newMin, newMax);
    });

    it("Should revert when setting invalid bounds (min >= max)", async function () {
      await expect(
        reputationEngine.connect(admin).setReputationBounds(1e18, 1e18)
      ).to.be.revertedWithCustomError(reputationEngine, "InvalidReputationBounds");
    });

    it("Should revert when setting min to zero", async function () {
      await expect(
        reputationEngine.connect(admin).setReputationBounds(0, 1e18)
      ).to.be.revertedWithCustomError(reputationEngine, "InvalidReputationBounds");
    });

    it("Should set default initial score by admin", async function () {
      const newDefault = 2e18;

      await reputationEngine.connect(admin).setDefaultInitialScore(newDefault);

      expect(await reputationEngine.defaultInitialScore()).to.equal(newDefault);
    });

    it("Should emit DefaultInitialScoreUpdated event", async function () {
      const newDefault = 2e18;

      await expect(reputationEngine.connect(admin).setDefaultInitialScore(newDefault))
        .to.emit(reputationEngine, "DefaultInitialScoreUpdated")
        .withArgs(DEFAULT_INITIAL_SCORE, newDefault);
    });

    it("Should revert when setting default score to zero", async function () {
      await expect(
        reputationEngine.connect(admin).setDefaultInitialScore(0)
      ).to.be.revertedWithCustomError(reputationEngine, "InvalidReputationScore");
    });

    it("Should toggle initialization restriction by admin", async function () {
      await reputationEngine.connect(admin).setInitializationRestriction(true);
      expect(await reputationEngine.restrictedInitialization()).to.be.true;

      await reputationEngine.connect(admin).setInitializationRestriction(false);
      expect(await reputationEngine.restrictedInitialization()).to.be.false;
    });

    it("Should emit InitializationRestrictionToggled event", async function () {
      await expect(reputationEngine.connect(admin).setInitializationRestriction(true))
        .to.emit(reputationEngine, "InitializationRestrictionToggled")
        .withArgs(true);
    });

    it("Should revert when non-admin toggles restriction", async function () {
      await expect(
        reputationEngine.connect(verifier1).setInitializationRestriction(true)
      ).to.be.reverted;
    });
  });

  describe("Pause Functions", function () {
    it("Should pause contract by pauser", async function () {
      await reputationEngine.connect(pauser).pause();
      expect(await reputationEngine.paused()).to.be.true;
    });

    it("Should unpause contract by pauser", async function () {
      await reputationEngine.connect(pauser).pause();
      await reputationEngine.connect(pauser).unpause();
      expect(await reputationEngine.paused()).to.be.false;
    });

    it("Should revert when non-pauser tries to pause", async function () {
      await expect(
        reputationEngine.connect(verifier1).pause()
      ).to.be.reverted;
    });

    it("Should prevent initialization when paused", async function () {
      await reputationEngine.connect(pauser).pause();

      await expect(
        reputationEngine.connect(verifier2).initializeReputation(verifier2.address)
      ).to.be.revertedWithCustomError(reputationEngine, "EnforcedPause");
    });

    it("Should prevent updates when paused", async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);
      await reputationEngine.connect(pauser).pause();

      await expect(
        reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, 2e18)
      ).to.be.revertedWithCustomError(reputationEngine, "EnforcedPause");
    });
  });

  describe("Security Tests", function () {
    it("Should prevent unauthorized reputation modification", async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);

      await expect(
        reputationEngine.connect(verifier2).updateReputationScore(verifier1.address, 2e18)
      ).to.be.reverted;
    });

    it("Should prevent duplicate profile creation", async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);

      await expect(
        reputationEngine.connect(verifier1).initializeReputation(verifier1.address)
      ).to.be.revertedWithCustomError(reputationEngine, "VerifierAlreadyExists");
    });

    it("Should validate address on initialization", async function () {
      await expect(
        reputationEngine.connect(user).initializeReputation(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(reputationEngine, "InvalidZeroAddress");
    });

    it("Should enforce reputation bounds on updates", async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);

      await expect(
        reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, 0)
      ).to.be.revertedWithCustomError(reputationEngine, "InvalidReputationScore");

      await expect(
        reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, 100e18)
      ).to.be.revertedWithCustomError(reputationEngine, "InvalidReputationScore");
    });
  });

  describe("Gas Optimization", function () {
    it("Should efficiently initialize reputation", async function () {
      const tx = await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);
      const receipt = await tx.wait();
      
      console.log("Gas used for initializeReputation:", receipt?.gasUsed.toString());
    });

    it("Should efficiently get reputation", async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);
      
      const tx = await reputationEngine.getReputation(verifier1.address);
      const receipt = await tx.wait();
      
      console.log("Gas used for getReputation:", receipt?.gasUsed.toString());
    });

    it("Should efficiently calculate weight", async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);
      
      const tx = await reputationEngine.calculateWeight(1000e18, verifier1.address);
      const receipt = await tx.wait();
      
      console.log("Gas used for calculateWeight:", receipt?.gasUsed.toString());
    });

    it("Should efficiently record verification", async function () {
      await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);
      
      const tx = await reputationEngine.connect(updateRole).recordSuccessfulVerification(verifier1.address, 1000e18);
      const receipt = await tx.wait();
      
      console.log("Gas used for recordSuccessfulVerification:", receipt?.gasUsed.toString());
    });
  });
});
