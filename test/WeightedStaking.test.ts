import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("WeightedStaking", function () {
  let weightedStaking: Contract;
  let mockOracle: Contract;
  let owner: Signer;
  let user1: Signer;
  let user2: Signer;
  let user3: Signer;

  const BASE_MULTIPLIER = ethers.parseEther("1"); // 1e18
  const MIN_REPUTATION = ethers.parseEther("0.1"); // 10%
  const MAX_REPUTATION = ethers.parseEther("10"); // 1000%
  const DEFAULT_REPUTATION = ethers.parseEther("1"); // 100%

  beforeEach(async function () {
    [owner, user1, user2, user3] = await ethers.getSigners();

    // Deploy MockReputationOracle
    const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
    mockOracle = await MockReputationOracle.deploy();
    await mockOracle.waitForDeployment();

    // Deploy WeightedStaking
    const WeightedStaking = await ethers.getContractFactory("WeightedStaking");
    weightedStaking = await WeightedStaking.deploy(await mockOracle.getAddress());
    await weightedStaking.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the correct reputation oracle", async function () {
      const config = await weightedStaking.getConfiguration();
      expect(config.oracle).to.equal(await mockOracle.getAddress());
    });

    it("Should set correct default parameters", async function () {
      const config = await weightedStaking.getConfiguration();
      expect(config.minScore).to.equal(MIN_REPUTATION);
      expect(config.maxScore).to.equal(MAX_REPUTATION);
      expect(config.defaultScore).to.equal(DEFAULT_REPUTATION);
      expect(config.enabled).to.equal(true);
    });

    it("Should revert if oracle address is zero", async function () {
      const WeightedStaking = await ethers.getContractFactory("WeightedStaking");
      await expect(
        WeightedStaking.deploy(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(weightedStaking, "InvalidReputationOracle");
    });
  });

  describe("Weighted Stake Calculation", function () {
    const STAKE_AMOUNT = ethers.parseEther("1000"); // 1000 tokens

    it("Should calculate correct weighted stake with neutral reputation (1.0)", async function () {
      // Set neutral reputation (1.0 = 100%)
      await mockOracle.setReputationScore(await user1.getAddress(), ethers.parseEther("1"));

      const result = await weightedStaking.calculateWeightedStake(
        await user1.getAddress(),
        STAKE_AMOUNT
      );

      expect(result.rawStake).to.equal(STAKE_AMOUNT);
      expect(result.reputationScore).to.equal(ethers.parseEther("1"));
      expect(result.effectiveStake).to.equal(STAKE_AMOUNT); // 1000 * 1.0 = 1000
      expect(result.weight).to.equal(ethers.parseEther("1"));
    });

    it("Should calculate correct weighted stake with high reputation (3.0)", async function () {
      // Set high reputation (3.0 = 300%)
      await mockOracle.setReputationScore(await user1.getAddress(), ethers.parseEther("3"));

      const result = await weightedStaking.calculateWeightedStake(
        await user1.getAddress(),
        STAKE_AMOUNT
      );

      expect(result.rawStake).to.equal(STAKE_AMOUNT);
      expect(result.reputationScore).to.equal(ethers.parseEther("3"));
      expect(result.effectiveStake).to.equal(ethers.parseEther("3000")); // 1000 * 3.0 = 3000
      expect(result.weight).to.equal(ethers.parseEther("3"));
    });

    it("Should calculate correct weighted stake with low reputation (0.5)", async function () {
      // Set low reputation (0.5 = 50%)
      await mockOracle.setReputationScore(await user1.getAddress(), ethers.parseEther("0.5"));

      const result = await weightedStaking.calculateWeightedStake(
        await user1.getAddress(),
        STAKE_AMOUNT
      );

      expect(result.rawStake).to.equal(STAKE_AMOUNT);
      expect(result.reputationScore).to.equal(ethers.parseEther("0.5"));
      expect(result.effectiveStake).to.equal(ethers.parseEther("500")); // 1000 * 0.5 = 500
      expect(result.weight).to.equal(ethers.parseEther("0.5"));
    });

    it("Should use default reputation when user has no score", async function () {
      const result = await weightedStaking.calculateWeightedStake(
        await user1.getAddress(),
        STAKE_AMOUNT
      );

      expect(result.reputationScore).to.equal(DEFAULT_REPUTATION);
      expect(result.effectiveStake).to.equal(STAKE_AMOUNT); // Uses default 1.0
    });

    it("Should apply minimum reputation bound", async function () {
      // Set reputation below minimum (0.05 < 0.1)
      await mockOracle.setReputationScore(await user1.getAddress(), ethers.parseEther("0.05"));

      const result = await weightedStaking.calculateWeightedStake(
        await user1.getAddress(),
        STAKE_AMOUNT
      );

      // Should be clamped to minimum (0.1)
      expect(result.reputationScore).to.equal(MIN_REPUTATION);
      expect(result.effectiveStake).to.equal(ethers.parseEther("100")); // 1000 * 0.1 = 100
    });

    it("Should apply maximum reputation bound", async function () {
      // Set reputation above maximum (15 > 10)
      await mockOracle.setReputationScore(await user1.getAddress(), ethers.parseEther("15"));

      const result = await weightedStaking.calculateWeightedStake(
        await user1.getAddress(),
        STAKE_AMOUNT
      );

      // Should be clamped to maximum (10)
      expect(result.reputationScore).to.equal(MAX_REPUTATION);
      expect(result.effectiveStake).to.equal(ethers.parseEther("10000")); // 1000 * 10 = 10000
    });

    it("Should revert on zero stake amount", async function () {
      await expect(
        weightedStaking.calculateWeightedStake(await user1.getAddress(), 0)
      ).to.be.revertedWithCustomError(weightedStaking, "ZeroStakeAmount");
    });
  });

  describe("Weighted Staking Toggle", function () {
    const STAKE_AMOUNT = ethers.parseEther("1000");

    it("Should return equal weight when weighted staking is disabled", async function () {
      // Set high reputation
      await mockOracle.setReputationScore(await user1.getAddress(), ethers.parseEther("5"));

      // Disable weighted staking
      await weightedStaking.setWeightedStakingEnabled(false);

      const result = await weightedStaking.calculateWeightedStake(
        await user1.getAddress(),
        STAKE_AMOUNT
      );

      // Should ignore reputation and return 1:1
      expect(result.effectiveStake).to.equal(STAKE_AMOUNT);
      expect(result.weight).to.equal(BASE_MULTIPLIER);
    });

    it("Should emit event when toggling weighted staking", async function () {
      await expect(weightedStaking.setWeightedStakingEnabled(false))
        .to.emit(weightedStaking, "WeightedStakingToggled")
        .withArgs(false);
    });
  });

  describe("Batch Calculation", function () {
    it("Should calculate weighted stakes for multiple users", async function () {
      const users = [await user1.getAddress(), await user2.getAddress(), await user3.getAddress()];
      const stakes = [
        ethers.parseEther("1000"),
        ethers.parseEther("2000"),
        ethers.parseEther("500")
      ];

      // Set different reputations
      await mockOracle.setReputationScore(users[0], ethers.parseEther("1")); // 100%
      await mockOracle.setReputationScore(users[1], ethers.parseEther("2")); // 200%
      await mockOracle.setReputationScore(users[2], ethers.parseEther("0.5")); // 50%

      const results = await weightedStaking.batchCalculateWeightedStake(users, stakes);

      expect(results[0].effectiveStake).to.equal(ethers.parseEther("1000")); // 1000 * 1.0
      expect(results[1].effectiveStake).to.equal(ethers.parseEther("4000")); // 2000 * 2.0
      expect(results[2].effectiveStake).to.equal(ethers.parseEther("250"));  // 500 * 0.5
    });

    it("Should revert on array length mismatch", async function () {
      const users = [await user1.getAddress(), await user2.getAddress()];
      const stakes = [ethers.parseEther("1000")];

      await expect(
        weightedStaking.batchCalculateWeightedStake(users, stakes)
      ).to.be.revertedWith("Array length mismatch");
    });
  });

  describe("Oracle Fallback", function () {
    it("Should use default reputation when oracle is inactive", async function () {
      const STAKE_AMOUNT = ethers.parseEther("1000");

      // Set oracle to inactive
      await mockOracle.setActive(false);

      const result = await weightedStaking.calculateWeightedStake(
        await user1.getAddress(),
        STAKE_AMOUNT
      );

      expect(result.reputationScore).to.equal(DEFAULT_REPUTATION);
      expect(result.effectiveStake).to.equal(STAKE_AMOUNT);
    });
  });

  describe("Admin Functions", function () {
    it("Should allow owner to update reputation oracle", async function () {
      const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
      const newOracle = await MockReputationOracle.deploy();
      await newOracle.waitForDeployment();

      await expect(weightedStaking.setReputationOracle(await newOracle.getAddress()))
        .to.emit(weightedStaking, "ReputationOracleUpdated")
        .withArgs(await mockOracle.getAddress(), await newOracle.getAddress());

      const config = await weightedStaking.getConfiguration();
      expect(config.oracle).to.equal(await newOracle.getAddress());
    });

    it("Should revert when setting oracle to zero address", async function () {
      await expect(
        weightedStaking.setReputationOracle(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(weightedStaking, "InvalidReputationOracle");
    });

    it("Should allow owner to update reputation bounds", async function () {
      const newMin = ethers.parseEther("0.2");
      const newMax = ethers.parseEther("5");

      await expect(weightedStaking.setReputationBounds(newMin, newMax))
        .to.emit(weightedStaking, "ReputationBoundsUpdated")
        .withArgs(newMin, newMax);

      const config = await weightedStaking.getConfiguration();
      expect(config.minScore).to.equal(newMin);
      expect(config.maxScore).to.equal(newMax);
    });

    it("Should revert on invalid reputation bounds", async function () {
      // Min >= Max
      await expect(
        weightedStaking.setReputationBounds(ethers.parseEther("5"), ethers.parseEther("5"))
      ).to.be.revertedWithCustomError(weightedStaking, "InvalidReputationBounds");

      // Min = 0
      await expect(
        weightedStaking.setReputationBounds(0, ethers.parseEther("10"))
      ).to.be.revertedWithCustomError(weightedStaking, "InvalidReputationBounds");
    });

    it("Should allow owner to update default reputation", async function () {
      const newDefault = ethers.parseEther("1.5");

      await expect(weightedStaking.setDefaultReputationScore(newDefault))
        .to.emit(weightedStaking, "DefaultReputationUpdated")
        .withArgs(newDefault);

      const config = await weightedStaking.getConfiguration();
      expect(config.defaultScore).to.equal(newDefault);
    });

    it("Should revert when setting default reputation to zero", async function () {
      await expect(
        weightedStaking.setDefaultReputationScore(0)
      ).to.be.revertedWithCustomError(weightedStaking, "InvalidDefaultReputation");
    });

    it("Should prevent non-owner from calling admin functions", async function () {
      await expect(
        weightedStaking.connect(user1).setWeightedStakingEnabled(false)
      ).to.be.reverted;
    });
  });

  describe("Preview Weight", function () {
    it("Should preview correct weight for user", async function () {
      await mockOracle.setReputationScore(await user1.getAddress(), ethers.parseEther("2.5"));

      const weight = await weightedStaking.previewWeight(await user1.getAddress());

      expect(weight).to.equal(ethers.parseEther("2.5"));
    });

    it("Should return base multiplier when weighted staking disabled", async function () {
      await mockOracle.setReputationScore(await user1.getAddress(), ethers.parseEther("5"));
      await weightedStaking.setWeightedStakingEnabled(false);

      const weight = await weightedStaking.previewWeight(await user1.getAddress());

      expect(weight).to.equal(BASE_MULTIPLIER);
    });
  });

  describe("Record Weighted Stake", function () {
    it("Should emit event when recording weighted stake", async function () {
      const STAKE_AMOUNT = ethers.parseEther("1000");
      await mockOracle.setReputationScore(await user1.getAddress(), ethers.parseEther("2"));

      await expect(
        weightedStaking.calculateAndRecordWeightedStake(await user1.getAddress(), STAKE_AMOUNT)
      )
        .to.emit(weightedStaking, "WeightedStakeCalculated")
        .withArgs(
          await user1.getAddress(),
          STAKE_AMOUNT,
          ethers.parseEther("2"),
          ethers.parseEther("2000"),
          ethers.parseEther("2")
        );
    });
  });
});
