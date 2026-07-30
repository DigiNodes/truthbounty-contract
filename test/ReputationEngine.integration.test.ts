import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { ReputationEngine, TruthBountyWeighted, MockERC20, MockGovernanceController } from "../typechain-types";

describe("ReputationEngine Integration Tests", function () {
  let reputationEngine: ReputationEngine;
  let truthBountyWeighted: TruthBountyWeighted;
  let bountyToken: MockERC20;
  let mockGovernance: MockGovernanceController;
  
  let admin: SignerWithAddress;
  let updateRole: SignerWithAddress;
  let verifier1: SignerWithAddress;
  let verifier2: SignerWithAddress;
  let submitter: SignerWithAddress;

  const BASE_MULTIPLIER = 1e18;
  const DEFAULT_INITIAL_SCORE = 1e18;
  const MIN_STAKE_AMOUNT = 100 * 1e18;

  beforeEach(async function () {
    [admin, updateRole, verifier1, verifier2, submitter] = await ethers.getSigners();

    // Deploy mock governance controller
    const MockGovernanceFactory = await ethers.getContractFactory("MockGovernanceController");
    mockGovernance = await MockGovernanceFactory.deploy(admin.address);

    // Deploy mock ERC20 token
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    bountyToken = await MockERC20Factory.deploy("TruthBounty", "BOUNTY");

    // Mint tokens to verifiers
    await bountyToken.mint(verifier1.address, 10000e18);
    await bountyToken.mint(verifier2.address, 10000e18);

    // Deploy ReputationEngine
    const ReputationEngineFactory = await ethers.getContractFactory("ReputationEngine");
    reputationEngine = await ReputationEngineFactory.deploy(
      admin.address,
      await mockGovernance.getAddress()
    );

    // Grant UPDATE_ROLE to updateRole
    await reputationEngine.connect(admin).grantRole(
      await reputationEngine.UPDATE_ROLE(),
      updateRole.address
    );

    // Initialize reputations for verifiers
    await reputationEngine.connect(verifier1).initializeReputation(verifier1.address);
    await reputationEngine.connect(verifier2).initializeReputation(verifier2.address);

    // Deploy TruthBountyWeighted with ReputationEngine as oracle
    // Note: We need to create a wrapper that implements IReputationOracle
    // For this integration test, we'll use a simple adapter
  });

  describe("Reputation Engine + Staking Integration", function () {
    it("Should initialize reputation before staking", async function () {
      expect(await reputationEngine.reputationExists(verifier1.address)).to.be.true;
      expect(await reputationEngine.reputationExists(verifier2.address)).to.be.true;
    });

    it("Should record stake participation when verification occurs", async function () {
      const stakeAmount = 1000e18;
      
      await reputationEngine.connect(updateRole).recordSuccessfulVerification(
        verifier1.address,
        stakeAmount
      );

      const stats = await reputationEngine.getVerifierStatistics(verifier1.address);
      expect(stats.totalStake).to.equal(stakeAmount);
    });

    it("Should update protocol statistics on verification", async function () {
      const stakeAmount1 = 1000e18;
      const stakeAmount2 = 500e18;

      await reputationEngine.connect(updateRole).recordSuccessfulVerification(
        verifier1.address,
        stakeAmount1
      );

      await reputationEngine.connect(updateRole).recordFailedVerification(
        verifier2.address,
        stakeAmount2
      );

      const stats = await reputationEngine.getStatistics();
      expect(stats.totalSuccessfulVerifications).to.equal(1);
      expect(stats.totalFailedVerifications).to.equal(1);
      expect(stats.totalStakeParticipated).to.equal(stakeAmount1 + stakeAmount2);
    });

    it("Should track cumulative stake across multiple verifications", async function () {
      const stakeAmount1 = 1000e18;
      const stakeAmount2 = 500e18;

      await reputationEngine.connect(updateRole).recordSuccessfulVerification(
        verifier1.address,
        stakeAmount1
      );

      await reputationEngine.connect(updateRole).recordSuccessfulVerification(
        verifier1.address,
        stakeAmount2
      );

      const stats = await reputationEngine.getVerifierStatistics(verifier1.address);
      expect(stats.totalStake).to.equal(stakeAmount1 + stakeAmount2);
      expect(stats.successfulVerifications).to.equal(2);
    });
  });

  describe("Reputation Engine + Governance Integration", function () {
    it("Should allow governance to update reputation bounds", async function () {
      const newMin = 5e17;
      const newMax = 5e18;

      await reputationEngine.connect(admin).setReputationBounds(newMin, newMax);

      expect(await reputationEngine.minReputationScore()).to.equal(newMin);
      expect(await reputationEngine.maxReputationScore()).to.equal(newMax);
    });

    it("Should allow governance to update default initial score", async function () {
      const newDefault = 2e18;

      await reputationEngine.connect(admin).setDefaultInitialScore(newDefault);

      expect(await reputationEngine.defaultInitialScore()).to.equal(newDefault);
    });

    it("Should emit governance parameter update events", async function () {
      const newMin = 5e17;
      const newMax = 5e18;

      await expect(reputationEngine.connect(admin).setReputationBounds(newMin, newMax))
        .to.emit(reputationEngine, "ParameterUpdatedByGovernance")
        .withArgs(
          ethers.keccak256(ethers.toUtf8Bytes("REPUTATION_MIN_SCORE")),
          1e17,
          newMin
        );
    });

    it("Should respect initialization restriction for security", async function () {
      await reputationEngine.connect(admin).setInitializationRestriction(true);

      // Non-UPDATE_ROLE should fail
      await expect(
        reputationEngine.connect(admin).initializeReputation(admin.address)
      ).to.be.revertedWithCustomError(reputationEngine, "UnauthorizedUpdate");

      // UPDATE_ROLE should succeed
      await reputationEngine.connect(updateRole).initializeReputation(admin.address);
      expect(await reputationEngine.reputationExists(admin.address)).to.be.true;
    });
  });

  describe("Reputation Engine + Reward Integration", function () {
    it("Should record rewards earned by verifiers", async function () {
      const rewardAmount = 500e18;

      await reputationEngine.connect(updateRole).recordRewardEarned(
        verifier1.address,
        rewardAmount
      );

      const stats = await reputationEngine.getStatistics();
      expect(stats.totalRewardsEarned).to.equal(rewardAmount);
    });

    it("Should accumulate rewards across multiple distributions", async function () {
      const reward1 = 300e18;
      const reward2 = 200e18;

      await reputationEngine.connect(updateRole).recordRewardEarned(
        verifier1.address,
        reward1
      );

      await reputationEngine.connect(updateRole).recordRewardEarned(
        verifier2.address,
        reward2
      );

      const stats = await reputationEngine.getStatistics();
      expect(stats.totalRewardsEarned).to.equal(reward1 + reward2);
    });
  });

  describe("Reputation Engine + Dispute Integration", function () {
    it("Should record disputed claims", async function () {
      const stakeAmount = 1000e18;

      await reputationEngine.connect(updateRole).recordDisputedClaim(
        verifier1.address,
        stakeAmount
      );

      const stats = await reputationEngine.getVerifierStatistics(verifier1.address);
      expect(stats.disputedVerifications).to.equal(1);
      expect(stats.totalStake).to.equal(stakeAmount);
    });

    it("Should update protocol dispute statistics", async function () {
      await reputationEngine.connect(updateRole).recordDisputedClaim(
        verifier1.address,
        1000e18
      );

      await reputationEngine.connect(updateRole).recordDisputedClaim(
        verifier2.address,
        500e18
      );

      const stats = await reputationEngine.getStatistics();
      expect(stats.totalDisputedClaims).to.equal(2);
    });
  });

  describe("Reputation Engine + Batch Operations", function () {
    it("Should batch update multiple verifiers efficiently", async function () {
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
    });

    it("Should update protocol statistics on batch operations", async function () {
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

      const stats = await reputationEngine.getStatistics();
      expect(stats.totalSuccessfulVerifications).to.equal(8);
      expect(stats.totalFailedVerifications).to.equal(3);
      expect(stats.totalDisputedClaims).to.equal(1);
    });
  });

  describe("Reputation Engine + Weight Calculation Integration", function () {
    it("Should calculate weight based on reputation score", async function () {
      const stakeAmount = 1000e18;
      
      // Update reputation to 2x
      await reputationEngine.connect(updateRole).updateReputationScore(
        verifier1.address,
        2e18
      );

      const weight = await reputationEngine.calculateWeight(stakeAmount, verifier1.address);
      expect(weight).to.equal(stakeAmount * 2);
    });

    it("Should cap weight at 10x maximum", async function () {
      const stakeAmount = 1000e18;
      
      // Set reputation to 20x (should be capped at 10x)
      await reputationEngine.connect(updateRole).updateReputationScore(
        verifier1.address,
        20e18
      );

      const weight = await reputationEngine.calculateWeight(stakeAmount, verifier1.address);
      expect(weight).to.equal(stakeAmount * 10);
    });

    it("Should provide deterministic weight calculations", async function () {
      const stakeAmount = 1000e18;
      
      const weight1 = await reputationEngine.calculateWeight(stakeAmount, verifier1.address);
      const weight2 = await reputationEngine.calculateWeight(stakeAmount, verifier1.address);
      
      expect(weight1).to.equal(weight2);
    });
  });

  describe("Reputation Engine + Security Integration", function () {
    it("Should prevent unauthorized reputation modifications", async function () {
      await expect(
        reputationEngine.connect(verifier1).updateReputationScore(
          verifier1.address,
          2e18
        )
      ).to.be.reverted;
    });

    it("Should prevent unauthorized verification recording", async function () {
      await expect(
        reputationEngine.connect(verifier1).recordSuccessfulVerification(
          verifier1.address,
          1000e18
        )
      ).to.be.reverted;
    });

    it("Should validate reputation bounds on updates", async function () {
      await expect(
        reputationEngine.connect(updateRole).updateReputationScore(
          verifier1.address,
          0
        )
      ).to.be.revertedWithCustomError(reputationEngine, "InvalidReputationScore");

      await expect(
        reputationEngine.connect(updateRole).updateReputationScore(
          verifier1.address,
          100e18
        )
      ).to.be.revertedWithCustomError(reputationEngine, "InvalidReputationScore");
    });

    it("Should prevent duplicate reputation initialization", async function () {
      await expect(
        reputationEngine.connect(verifier1).initializeReputation(verifier1.address)
      ).to.be.revertedWithCustomError(reputationEngine, "VerifierAlreadyExists");
    });
  });

  describe("Reputation Engine + Event Integration", function () {
    it("Should emit events for reputation initialization", async function () {
      await expect(reputationEngine.connect(updateRole).initializeReputation(admin.address))
        .to.emit(reputationEngine, "ReputationCreated")
        .withArgs(admin.address);
    });

    it("Should emit events for reputation score updates", async function () {
      await expect(reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, 2e18))
        .to.emit(reputationEngine, "ReputationScoreUpdated");
    });

    it("Should emit events for verification statistics updates", async function () {
      await expect(reputationEngine.connect(updateRole).recordSuccessfulVerification(verifier1.address, 1000e18))
        .to.emit(reputationEngine, "VerificationStatsUpdated");
    });

    it("Should emit events for protocol statistics updates", async function () {
      await expect(reputationEngine.connect(updateRole).recordSuccessfulVerification(verifier1.address, 1000e18))
        .to.emit(reputationEngine, "ProtocolStatisticsUpdated");
    });
  });

  describe("Reputation Engine + Pause Integration", function () {
    it("Should prevent operations when paused", async function () {
      const pauser = admin; // Admin has PAUSER_ROLE by default
      
      await reputationEngine.connect(pauser).pause();

      await expect(
        reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, 2e18)
      ).to.be.revertedWithCustomError(reputationEngine, "EnforcedPause");
    });

    it("Should allow operations after unpausing", async function () {
      const pauser = admin;
      
      await reputationEngine.connect(pauser).pause();
      await reputationEngine.connect(pauser).unpause();

      await reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, 2e18);
      expect(await reputationEngine.getReputationScore(verifier1.address)).to.equal(2e18);
    });
  });

  describe("Reputation Engine + Multi-Verifier Scenarios", function () {
    it("Should handle multiple verifiers with different reputations", async function () {
      // Set different reputation scores
      await reputationEngine.connect(updateRole).updateReputationScore(verifier1.address, 2e18);
      await reputationEngine.connect(updateRole).updateReputationScore(verifier2.address, 1.5e18);

      const stakeAmount = 1000e18;

      const weight1 = await reputationEngine.calculateWeight(stakeAmount, verifier1.address);
      const weight2 = await reputationEngine.calculateWeight(stakeAmount, verifier2.address);

      expect(weight1).to.equal(stakeAmount * 2);
      expect(weight2).to.equal(stakeAmount * 1.5);
    });

    it("Should track statistics for all verifiers independently", async function () {
      await reputationEngine.connect(updateRole).recordSuccessfulVerification(verifier1.address, 1000e18);
      await reputationEngine.connect(updateRole).recordFailedVerification(verifier2.address, 500e18);

      const stats1 = await reputationEngine.getVerifierStatistics(verifier1.address);
      const stats2 = await reputationEngine.getVerifierStatistics(verifier2.address);

      expect(stats1.successfulVerifications).to.equal(1);
      expect(stats1.failedVerifications).to.equal(0);
      expect(stats2.successfulVerifications).to.equal(0);
      expect(stats2.failedVerifications).to.equal(1);
    });

    it("Should aggregate protocol statistics correctly", async function () {
      await reputationEngine.connect(updateRole).recordSuccessfulVerification(verifier1.address, 1000e18);
      await reputationEngine.connect(updateRole).recordSuccessfulVerification(verifier2.address, 500e18);
      await reputationEngine.connect(updateRole).recordFailedVerification(verifier1.address, 200e18);

      const stats = await reputationEngine.getStatistics();
      expect(stats.totalSuccessfulVerifications).to.equal(2);
      expect(stats.totalFailedVerifications).to.equal(1);
      expect(stats.totalStakeParticipated).to.equal(1700e18);
    });
  });
});
