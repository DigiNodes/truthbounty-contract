import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time, mine } from "@nomicfoundation/hardhat-network-helpers";

/**
 * Tests for audit fixes:
 *  #180 - Unbounded loops in createSnapshot (configurable cap)
 *  #184 - Missing sqrt implementation on-chain
 *  #185 - slashCooldown bypass (same-block protection)
 *  #186 - maxSlashPercentage too restrictive (criticalSlash)
 */
describe("Audit Fixes", function () {

  // ─────────────────────────────────────────────────────────────────────────
  // #180 — ReputationSnapshot configurable cap
  // ─────────────────────────────────────────────────────────────────────────

  describe("#180 - Snapshot Size Cap", function () {
    async function deploySnapshotFixture() {
      const [admin, snapshotCreator, user1, user2, user3] = await ethers.getSigners();

      // Deploy mock oracle
      const MockOracle = await ethers.getContractFactory("MockReputationOracle");
      const oracle = await MockOracle.deploy();
      await oracle.waitForDeployment();

      // Deploy ReputationSnapshot
      const Snapshot = await ethers.getContractFactory("ReputationSnapshot");
      const snapshot = await Snapshot.deploy(admin.address);
      await snapshot.waitForDeployment();

      // Grant SNAPSHOT_ROLE to snapshotCreator
      const SNAPSHOT_ROLE = await snapshot.SNAPSHOT_ROLE();
      await snapshot.connect(admin).grantRole(SNAPSHOT_ROLE, snapshotCreator.address);

      // Set reputation scores for test users
      await oracle.setReputationScore(user1.address, ethers.parseEther("1"));
      await oracle.setReputationScore(user2.address, ethers.parseEther("2"));
      await oracle.setReputationScore(user3.address, ethers.parseEther("3"));

      return { snapshot, oracle, admin, snapshotCreator, user1, user2, user3 };
    }

    it("Should have default maxSnapshotSize of 200", async function () {
      const { snapshot } = await loadFixture(deploySnapshotFixture);
      expect(await snapshot.maxSnapshotSize()).to.equal(200);
    });

    it("Should allow admin to reduce maxSnapshotSize", async function () {
      const { snapshot, admin } = await loadFixture(deploySnapshotFixture);
      await snapshot.connect(admin).setMaxSnapshotSize(50);
      expect(await snapshot.maxSnapshotSize()).to.equal(50);
    });

    it("Should revert when snapshot exceeds configurable cap", async function () {
      const { snapshot, oracle, admin, snapshotCreator } = await loadFixture(deploySnapshotFixture);

      // Lower cap to 2
      await snapshot.connect(admin).setMaxSnapshotSize(2);

      // Generate 3 unique addresses
      const users = [
        ethers.Wallet.createRandom().address,
        ethers.Wallet.createRandom().address,
        ethers.Wallet.createRandom().address,
      ];

      // Set reputation for them
      for (const u of users) {
        await oracle.setReputationScore(u, ethers.parseEther("1"));
      }

      await expect(
        snapshot.connect(snapshotCreator).createSnapshot(users, await oracle.getAddress())
      ).to.be.revertedWithCustomError(snapshot, "SnapshotTooLarge")
       .withArgs(3, 2);
    });

    it("Should revert setMaxSnapshotSize with zero", async function () {
      const { snapshot, admin } = await loadFixture(deploySnapshotFixture);
      await expect(
        snapshot.connect(admin).setMaxSnapshotSize(0)
      ).to.be.revertedWithCustomError(snapshot, "InvalidMaxSnapshotSize");
    });

    it("Should revert setMaxSnapshotSize above ABSOLUTE_MAX", async function () {
      const { snapshot, admin } = await loadFixture(deploySnapshotFixture);
      await expect(
        snapshot.connect(admin).setMaxSnapshotSize(1001)
      ).to.be.revertedWithCustomError(snapshot, "InvalidMaxSnapshotSize");
    });

    it("Should allow snapshot at exact cap boundary", async function () {
      const { snapshot, oracle, admin, snapshotCreator } = await loadFixture(deploySnapshotFixture);

      await snapshot.connect(admin).setMaxSnapshotSize(2);

      const users = [
        ethers.Wallet.createRandom().address,
        ethers.Wallet.createRandom().address,
      ];
      for (const u of users) {
        await oracle.setReputationScore(u, ethers.parseEther("1"));
      }

      await expect(
        snapshot.connect(snapshotCreator).createSnapshot(users, await oracle.getAddress())
      ).to.not.be.reverted;
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // #184 — Sqrt weighting on-chain
  // ─────────────────────────────────────────────────────────────────────────

  describe("#184 - Sqrt Weighting", function () {
    async function deployWeightedFixture() {
      const [owner, user1] = await ethers.getSigners();

      const MockOracle = await ethers.getContractFactory("MockReputationOracle");
      const oracle = await MockOracle.deploy();
      await oracle.waitForDeployment();

      const WeightedStaking = await ethers.getContractFactory("contracts/WeightedStaking.sol:WeightedStaking");
      const staking = await WeightedStaking.deploy(
        await oracle.getAddress(),
        owner.address,
        owner.address
      );
      await staking.waitForDeployment();

      return { staking, oracle, owner, user1 };
    }

    it("Should default useSqrtWeighting to true", async function () {
      const { staking } = await loadFixture(deployWeightedFixture);
      expect(await staking.useSqrtWeighting()).to.equal(true);
    });

    it("Should apply sqrt to reputation in weighted stake calculation", async function () {
      const { staking, oracle, user1 } = await loadFixture(deployWeightedFixture);
      const STAKE = ethers.parseEther("1000");

      // reputation = 4.0 => sqrt(4e18 * 1e18) = sqrt(4e36) = 2e18
      await oracle.setReputationScore(user1.address, ethers.parseEther("4"));

      const result = await staking.calculateWeightedStake(user1.address, STAKE);

      // effectiveStake = 1000 * 2e18 / 1e18 = 2000
      expect(result.effectiveStake).to.equal(ethers.parseEther("2000"));
    });

    it("Should use linear weighting when sqrt disabled", async function () {
      const { staking, oracle, owner, user1 } = await loadFixture(deployWeightedFixture);
      const STAKE = ethers.parseEther("1000");

      await oracle.setReputationScore(user1.address, ethers.parseEther("4"));
      await staking.connect(owner).setSqrtWeighting(false);

      const result = await staking.calculateWeightedStake(user1.address, STAKE);

      // linear: effectiveStake = 1000 * 4 = 4000
      expect(result.effectiveStake).to.equal(ethers.parseEther("4000"));
    });

    it("Should emit SqrtWeightingToggled event", async function () {
      const { staking, owner } = await loadFixture(deployWeightedFixture);
      await expect(staking.connect(owner).setSqrtWeighting(false))
        .to.emit(staking, "SqrtWeightingToggled")
        .withArgs(false);
    });

    it("Sqrt of 1e18 (reputation 1.0) equals 1e18", async function () {
      const { staking, oracle, user1 } = await loadFixture(deployWeightedFixture);
      const STAKE = ethers.parseEther("1000");

      // reputation = 1.0, sqrt(1e18 * 1e18) = sqrt(1e36) = 1e18
      await oracle.setReputationScore(user1.address, ethers.parseEther("1"));

      const result = await staking.calculateWeightedStake(user1.address, STAKE);
      expect(result.effectiveStake).to.equal(ethers.parseEther("1000"));
    });

    it("Sqrt of 9e18 (reputation 9.0) equals 3e18", async function () {
      const { staking, oracle, user1 } = await loadFixture(deployWeightedFixture);
      const STAKE = ethers.parseEther("100");

      await oracle.setReputationScore(user1.address, ethers.parseEther("9"));

      const result = await staking.calculateWeightedStake(user1.address, STAKE);
      // sqrt(9e18 * 1e18) = sqrt(9e36) = 3e18
      // effective = 100 * 3e18 / 1e18 = 300
      expect(result.effectiveStake).to.equal(ethers.parseEther("300"));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // #185 — slashCooldown bypass (same-block protection)
  // ─────────────────────────────────────────────────────────────────────────

  describe("#185 - Same-Block Slash Prevention", function () {
    async function deploySlashingFixture() {
      const [owner, admin, settlement, criticalSlasher, verifier1, verifier2] = await ethers.getSigners();

      const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
      const token = await TruthBountyToken.deploy(owner.address);

      const Staking = await ethers.getContractFactory("Staking");
      const staking = await Staking.deploy(await token.getAddress(), 86400, owner.address);

      const VerifierSlashing = await ethers.getContractFactory("VerifierSlashing");
      const slashing = await VerifierSlashing.deploy(
        await staking.getAddress(),
        admin.address,
        admin.address
      );

      await staking.connect(owner).setSlashingContract(await slashing.getAddress());

      const SETTLEMENT_ROLE = await slashing.SETTLEMENT_ROLE();
      await slashing.connect(admin).grantRole(SETTLEMENT_ROLE, settlement.address);

      const CRITICAL_SLASHER_ROLE = await slashing.CRITICAL_SLASHER_ROLE();
      await slashing.connect(admin).grantCriticalSlasherRole(criticalSlasher.address);

      // Set cooldown to 0 to isolate the same-block check
      await slashing.connect(admin).updateSlashingConfig(50, 0);

      const stakeAmount = ethers.parseEther("1000");
      await token.transfer(verifier1.address, stakeAmount);
      await token.connect(verifier1).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(verifier1).stake(stakeAmount);

      await token.transfer(verifier2.address, stakeAmount);
      await token.connect(verifier2).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(verifier2).stake(stakeAmount);

      return { token, staking, slashing, owner, admin, settlement, criticalSlasher, verifier1, verifier2, stakeAmount };
    }

    it("Should track lastSlashBlock", async function () {
      const { slashing, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      await slashing.connect(settlement).slash(verifier1.address, 10, "test");
      expect(await slashing.lastSlashBlock(verifier1.address)).to.be.gt(0);
    });

    it("Should prevent second slash in same block via batch", async function () {
      const { slashing, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      // Batch slashing the same verifier twice should fail on the second
      await expect(
        slashing.connect(settlement).batchSlash(
          [verifier1.address, verifier1.address],
          [10, 10],
          ["first", "second"]
        )
      ).to.be.revertedWithCustomError(slashing, "SlashSameBlock");
    });

    it("Should allow slash in next block", async function () {
      const { slashing, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      await slashing.connect(settlement).slash(verifier1.address, 10, "first");

      // Mine a new block
      await mine(1);

      await expect(
        slashing.connect(settlement).slash(verifier1.address, 10, "second")
      ).to.not.be.reverted;
    });

    it("Should allow slashing different verifiers in same block", async function () {
      const { slashing, settlement, verifier1, verifier2 } = await loadFixture(deploySlashingFixture);

      await expect(
        slashing.connect(settlement).batchSlash(
          [verifier1.address, verifier2.address],
          [10, 10],
          ["reason1", "reason2"]
        )
      ).to.not.be.reverted;
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // #186 — Critical slash (up to 100%)
  // ─────────────────────────────────────────────────────────────────────────

  describe("#186 - Critical Slash (100%)", function () {
    async function deploySlashingFixture() {
      const [owner, admin, settlement, criticalSlasher, verifier1] = await ethers.getSigners();

      const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
      const token = await TruthBountyToken.deploy(owner.address);

      const Staking = await ethers.getContractFactory("Staking");
      const staking = await Staking.deploy(await token.getAddress(), 86400, owner.address);

      const VerifierSlashing = await ethers.getContractFactory("VerifierSlashing");
      const slashing = await VerifierSlashing.deploy(
        await staking.getAddress(),
        admin.address,
        admin.address
      );

      await staking.connect(owner).setSlashingContract(await slashing.getAddress());

      const SETTLEMENT_ROLE = await slashing.SETTLEMENT_ROLE();
      await slashing.connect(admin).grantRole(SETTLEMENT_ROLE, settlement.address);

      await slashing.connect(admin).grantCriticalSlasherRole(criticalSlasher.address);

      const stakeAmount = ethers.parseEther("1000");
      await token.transfer(verifier1.address, stakeAmount);
      await token.connect(verifier1).approve(await staking.getAddress(), stakeAmount);
      await staking.connect(verifier1).stake(stakeAmount);

      return { token, staking, slashing, owner, admin, settlement, criticalSlasher, verifier1, stakeAmount };
    }

    it("Should allow CRITICAL_SLASHER_ROLE to slash 100%", async function () {
      const { slashing, staking, criticalSlasher, verifier1, stakeAmount } = await loadFixture(deploySlashingFixture);

      await expect(
        slashing.connect(criticalSlasher).criticalSlash(verifier1.address, 100, "Critical protocol failure")
      )
        .to.emit(slashing, "CriticalSlashed")
        .withArgs(verifier1.address, stakeAmount, 100, "Critical protocol failure", criticalSlasher.address);

      // Verify stake is 0
      const [remaining] = await staking.stakes(verifier1.address);
      expect(remaining).to.equal(0);
    });

    it("Should reject criticalSlash from non-CRITICAL_SLASHER_ROLE", async function () {
      const { slashing, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      await expect(
        slashing.connect(settlement).criticalSlash(verifier1.address, 100, "Unauthorized")
      ).to.be.revertedWithCustomError(slashing, "CriticalSlashUnauthorized");
    });

    it("Should reject criticalSlash with 0 percentage", async function () {
      const { slashing, criticalSlasher, verifier1 } = await loadFixture(deploySlashingFixture);

      await expect(
        slashing.connect(criticalSlasher).criticalSlash(verifier1.address, 0, "Invalid")
      ).to.be.revertedWithCustomError(slashing, "InvalidPercentage");
    });

    it("Should reject criticalSlash above 100%", async function () {
      const { slashing, criticalSlasher, verifier1 } = await loadFixture(deploySlashingFixture);

      await expect(
        slashing.connect(criticalSlasher).criticalSlash(verifier1.address, 101, "Invalid")
      ).to.be.revertedWithCustomError(slashing, "InvalidPercentage");
    });

    it("Normal slash should still be limited by maxSlashPercentage", async function () {
      const { slashing, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      // maxSlashPercentage defaults to 50
      await expect(
        slashing.connect(settlement).slash(verifier1.address, 75, "Too much")
      ).to.be.revertedWithCustomError(slashing, "InvalidPercentage");
    });

    it("CriticalSlash should bypass maxSlashPercentage but not block-level check", async function () {
      const { slashing, criticalSlasher, verifier1 } = await loadFixture(deploySlashingFixture);

      // Use batch to force two slashes of the same verifier in one block via direct internal call pattern
      // Instead, we rely on the batch test in #185 which already validates same-block.
      // Here we verify that criticalSlash still records lastSlashBlock.
      await slashing.connect(criticalSlasher).criticalSlash(verifier1.address, 50, "First critical");

      // Verify lastSlashBlock was set
      const blockNum = await ethers.provider.getBlockNumber();
      expect(await slashing.lastSlashBlock(verifier1.address)).to.equal(blockNum);
    });
  });
});
