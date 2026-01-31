import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";

describe("VerifierSlashing", function () {
  // Fixture for deploying contracts
  async function deploySlashingFixture() {
    const [owner, admin, settlement, verifier1, verifier2, unauthorized] = await ethers.getSigners();

    // Deploy TruthBountyToken
    const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
    const token = await TruthBountyToken.deploy();

    // Deploy Staking contract
    const Staking = await ethers.getContractFactory("Staking");
    const staking = await Staking.deploy(await token.getAddress(), 86400); // 1 day lock

    // Deploy VerifierSlashing contract
    const VerifierSlashing = await ethers.getContractFactory("VerifierSlashing");
    const slashing = await VerifierSlashing.deploy(await staking.getAddress(), admin.address);

    // Set up the slashing contract in staking
    await staking.setSlashingContract(await slashing.getAddress());

    // Grant settlement role
    const SETTLEMENT_ROLE = await slashing.SETTLEMENT_ROLE();
    await slashing.connect(admin).grantRole(SETTLEMENT_ROLE, settlement.address);

    // Mint tokens and set up stakes
    const stakeAmount = ethers.parseEther("1000");
    await token.transfer(verifier1.address, stakeAmount);
    await token.transfer(verifier2.address, stakeAmount);

    // Approve and stake
    await token.connect(verifier1).approve(await staking.getAddress(), stakeAmount);
    await token.connect(verifier2).approve(await staking.getAddress(), stakeAmount);
    
    await staking.connect(verifier1).stake(stakeAmount);
    await staking.connect(verifier2).stake(stakeAmount);

    return {
      token,
      staking,
      slashing,
      owner,
      admin,
      settlement,
      verifier1,
      verifier2,
      unauthorized,
      stakeAmount,
      SETTLEMENT_ROLE
    };
  }

  describe("Deployment", function () {
    it("Should set the correct initial values", async function () {
      const { slashing, staking, admin } = await loadFixture(deploySlashingFixture);

      expect(await slashing.stakingContract()).to.equal(await staking.getAddress());
      expect(await slashing.maxSlashPercentage()).to.equal(50);
      expect(await slashing.slashCooldown()).to.equal(3600); // 1 hour
      expect(await slashing.hasRole(await slashing.ADMIN_ROLE(), admin.address)).to.be.true;
    });

    it("Should revert with invalid constructor parameters", async function () {
      const { admin } = await loadFixture(deploySlashingFixture);
      const VerifierSlashing = await ethers.getContractFactory("VerifierSlashing");

      await expect(
        VerifierSlashing.deploy(ethers.ZeroAddress, admin.address)
      ).to.be.revertedWithCustomError(VerifierSlashing, "InvalidStakingContract");

      await expect(
        VerifierSlashing.deploy(admin.address, ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(VerifierSlashing, "InvalidStakingContract");
    });
  });

  describe("Access Control", function () {
    it("Should only allow settlement role to slash", async function () {
      const { slashing, unauthorized, verifier1 } = await loadFixture(deploySlashingFixture);

      await expect(
        slashing.connect(unauthorized).slash(verifier1.address, 10, "Test reason")
      ).to.be.revertedWithCustomError(slashing, "UnauthorizedSlashing");
    });

    it("Should allow admin to grant and revoke settlement role", async function () {
      const { slashing, admin, unauthorized, SETTLEMENT_ROLE } = await loadFixture(deploySlashingFixture);

      // Grant role
      await slashing.connect(admin).grantSettlementRole(unauthorized.address);
      expect(await slashing.hasRole(SETTLEMENT_ROLE, unauthorized.address)).to.be.true;

      // Revoke role
      await slashing.connect(admin).revokeSettlementRole(unauthorized.address);
      expect(await slashing.hasRole(SETTLEMENT_ROLE, unauthorized.address)).to.be.false;
    });
  });

  describe("Slashing Functionality", function () {
    it("Should successfully slash a verifier", async function () {
      const { slashing, settlement, verifier1, stakeAmount } = await loadFixture(deploySlashingFixture);

      const slashPercentage = 20;
      const expectedSlashAmount = (stakeAmount * BigInt(slashPercentage)) / BigInt(100);

      await expect(
        slashing.connect(settlement).slash(verifier1.address, slashPercentage, "Incorrect verification")
      )
        .to.emit(slashing, "Slashed")
        .withArgs(
          verifier1.address,
          expectedSlashAmount,
          slashPercentage,
          stakeAmount - expectedSlashAmount,
          "Incorrect verification",
          settlement.address
        );

      // Check slash history
      const history = await slashing.getSlashHistory(verifier1.address);
      expect(history.length).to.equal(1);
      expect(history[0].amount).to.equal(expectedSlashAmount);
      expect(history[0].percentage).to.equal(slashPercentage);
      expect(history[0].reason).to.equal("Incorrect verification");

      // Check total slashed
      expect(await slashing.totalSlashed(verifier1.address)).to.equal(expectedSlashAmount);
    });

    it("Should revert with invalid percentage", async function () {
      const { slashing, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      await expect(
        slashing.connect(settlement).slash(verifier1.address, 0, "Test")
      ).to.be.revertedWithCustomError(slashing, "InvalidPercentage");

      await expect(
        slashing.connect(settlement).slash(verifier1.address, 101, "Test")
      ).to.be.revertedWithCustomError(slashing, "InvalidPercentage");
    });

    it("Should revert when trying to slash zero address", async function () {
      const { slashing, settlement } = await loadFixture(deploySlashingFixture);

      await expect(
        slashing.connect(settlement).slash(ethers.ZeroAddress, 10, "Test")
      ).to.be.revertedWithCustomError(slashing, "NoStakeToSlash");
    });

    it("Should revert when verifier has no stake", async function () {
      const { slashing, settlement, unauthorized } = await loadFixture(deploySlashingFixture);

      await expect(
        slashing.connect(settlement).slash(unauthorized.address, 10, "Test")
      ).to.be.revertedWithCustomError(slashing, "NoStakeToSlash");
    });

    it("Should enforce cooldown period", async function () {
      const { slashing, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      // First slash
      await slashing.connect(settlement).slash(verifier1.address, 10, "First slash");

      // Try to slash again immediately
      await expect(
        slashing.connect(settlement).slash(verifier1.address, 10, "Second slash")
      ).to.be.revertedWithCustomError(slashing, "SlashingTooFrequent");

      // Fast forward time past cooldown
      await time.increase(3601); // 1 hour + 1 second

      // Should work now
      await expect(
        slashing.connect(settlement).slash(verifier1.address, 10, "Second slash")
      ).to.not.be.reverted;
    });
  });

  describe("Batch Slashing", function () {
    it("Should successfully batch slash multiple verifiers", async function () {
      const { slashing, settlement, verifier1, verifier2 } = await loadFixture(deploySlashingFixture);

      const verifiers = [verifier1.address, verifier2.address];
      const percentages = [10, 15];
      const reasons = ["Reason 1", "Reason 2"];

      await expect(
        slashing.connect(settlement).batchSlash(verifiers, percentages, reasons)
      ).to.not.be.reverted;

      // Check both verifiers were slashed
      expect(await slashing.getSlashCount(verifier1.address)).to.equal(1);
      expect(await slashing.getSlashCount(verifier2.address)).to.equal(1);
    });

    it("Should revert with mismatched array lengths", async function () {
      const { slashing, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      await expect(
        slashing.connect(settlement).batchSlash(
          [verifier1.address],
          [10, 15], // Wrong length
          ["Reason"]
        )
      ).to.be.revertedWith("Array length mismatch");
    });
  });

  describe("View Functions", function () {
    it("Should correctly report slash cooldown status", async function () {
      const { slashing, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      // Initially should be able to slash
      expect(await slashing.canSlash(verifier1.address)).to.be.true;
      expect(await slashing.getSlashCooldownRemaining(verifier1.address)).to.equal(0);

      // Slash the verifier
      await slashing.connect(settlement).slash(verifier1.address, 10, "Test");

      // Should not be able to slash immediately
      expect(await slashing.canSlash(verifier1.address)).to.be.false;
      expect(await slashing.getSlashCooldownRemaining(verifier1.address)).to.be.greaterThan(0);

      // Fast forward past cooldown
      await time.increase(3601);

      // Should be able to slash again
      expect(await slashing.canSlash(verifier1.address)).to.be.true;
      expect(await slashing.getSlashCooldownRemaining(verifier1.address)).to.equal(0);
    });

    it("Should return correct slash history", async function () {
      const { slashing, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      // Slash twice with cooldown
      await slashing.connect(settlement).slash(verifier1.address, 10, "First reason");
      
      await time.increase(3601);
      await slashing.connect(settlement).slash(verifier1.address, 15, "Second reason");

      const history = await slashing.getSlashHistory(verifier1.address);
      expect(history.length).to.equal(2);
      expect(history[0].reason).to.equal("First reason");
      expect(history[1].reason).to.equal("Second reason");
      expect(await slashing.getSlashCount(verifier1.address)).to.equal(2);
    });
  });

  describe("Admin Functions", function () {
    it("Should allow admin to update slashing config", async function () {
      const { slashing, admin } = await loadFixture(deploySlashingFixture);

      await expect(
        slashing.connect(admin).updateSlashingConfig(75, 7200)
      )
        .to.emit(slashing, "SlashingConfigUpdated")
        .withArgs(75, 7200);

      expect(await slashing.maxSlashPercentage()).to.equal(75);
      expect(await slashing.slashCooldown()).to.equal(7200);
    });

    it("Should revert config update with invalid values", async function () {
      const { slashing, admin } = await loadFixture(deploySlashingFixture);

      await expect(
        slashing.connect(admin).updateSlashingConfig(101, 3600)
      ).to.be.revertedWith("Percentage too high");

      await expect(
        slashing.connect(admin).updateSlashingConfig(50, 8 * 24 * 3600) // 8 days
      ).to.be.revertedWith("Cooldown too long");
    });

    it("Should allow admin to pause and unpause", async function () {
      const { slashing, admin, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      // Pause the contract
      await slashing.connect(admin).pause();

      // Should not be able to slash when paused
      await expect(
        slashing.connect(settlement).slash(verifier1.address, 10, "Test")
      ).to.be.revertedWithCustomError(slashing, "EnforcedPause");

      // Unpause
      await slashing.connect(admin).unpause();

      // Should work again
      await expect(
        slashing.connect(settlement).slash(verifier1.address, 10, "Test")
      ).to.not.be.reverted;
    });

    it("Should allow admin to update staking contract", async function () {
      const { slashing, admin, unauthorized } = await loadFixture(deploySlashingFixture);

      await expect(
        slashing.connect(admin).updateStakingContract(unauthorized.address)
      )
        .to.emit(slashing, "StakingContractUpdated")
        .withArgs(unauthorized.address);

      expect(await slashing.stakingContract()).to.equal(unauthorized.address);
    });
  });

  describe("Integration with Staking Contract", function () {
    it("Should properly reduce stake in staking contract", async function () {
      const { slashing, staking, settlement, verifier1, stakeAmount } = await loadFixture(deploySlashingFixture);

      const slashPercentage = 25;
      const expectedSlashAmount = (stakeAmount * BigInt(slashPercentage)) / BigInt(100);

      // Check initial stake
      const [initialStake] = await staking.stakes(verifier1.address);
      expect(initialStake).to.equal(stakeAmount);

      // Slash the verifier
      await slashing.connect(settlement).slash(verifier1.address, slashPercentage, "Test slash");

      // Check reduced stake
      const [finalStake] = await staking.stakes(verifier1.address);
      expect(finalStake).to.equal(stakeAmount - expectedSlashAmount);
    });
  });

  describe("Edge Cases", function () {
    it("Should handle slashing when stake is very small", async function () {
      const { token, staking, slashing, settlement, unauthorized } = await loadFixture(deploySlashingFixture);

      // Give verifier a very small stake
      const smallStake = ethers.parseEther("0.001");
      await token.transfer(unauthorized.address, smallStake);
      await token.connect(unauthorized).approve(await staking.getAddress(), smallStake);
      await staking.connect(unauthorized).stake(smallStake);

      // Should still be able to slash
      await expect(
        slashing.connect(settlement).slash(unauthorized.address, 50, "Small stake test")
      ).to.not.be.reverted;
    });

    it("Should handle maximum slash percentage", async function () {
      const { slashing, admin, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      // Set max slash to 100%
      await slashing.connect(admin).updateSlashingConfig(100, 3600);

      // Should be able to slash 100%
      await expect(
        slashing.connect(settlement).slash(verifier1.address, 100, "Maximum slash")
      ).to.not.be.reverted;
    });
  });
});