import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";

async function getSlashHistoryHelper(slashing: any, verifier: string, offset: number, limit: number) {
  const res = await slashing.getSlashHistory(verifier, offset, limit);
  const history = [];
  for (let i = 0; i < res.timestamps.length; i++) {
    history.push({
      timestamp: res.timestamps[i],
      amount: res.amounts[i],
      percentage: res.percentages[i],
      reason: ethers.decodeBytes32String(res.reasons[i]),
      slashedBy: res.slashedBys[i]
    });
  }
  return history;
}

describe("VerifierSlashing", function () {
  // Fixture for deploying contracts
  async function deploySlashingFixture() {
    console.log("DEBUG: Getting signers...");
    const [owner, admin, settlement, verifier1, verifier2, unauthorized] = await ethers.getSigners();

    console.log("DEBUG: Deploying TruthBountyToken...");
    const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
    const token = await TruthBountyToken.deploy(owner.address);
    console.log("DEBUG: TruthBountyToken deployed at:", await token.getAddress());

    console.log("DEBUG: Deploying Staking...");
    const Staking = await ethers.getContractFactory("Staking");
    const staking = await Staking.deploy(await token.getAddress(), 86400, owner.address); // 1 day lock
    console.log("DEBUG: Staking deployed at:", await staking.getAddress());

    console.log("DEBUG: Deploying VerifierSlashing...");
    const VerifierSlashing = await ethers.getContractFactory("VerifierSlashing");
    const slashing = await VerifierSlashing.deploy(await staking.getAddress(), admin.address, admin.address);
    console.log("DEBUG: VerifierSlashing deployed at:", await slashing.getAddress());

    // Set up the slashing contract in staking
    await staking.connect(owner).setSlashingContract(await slashing.getAddress());

    // Grant settlement role through the resolver-role timelock
    const SETTLEMENT_ROLE = await slashing.SETTLEMENT_ROLE();
    await slashing.connect(admin).scheduleResolverRoleGrant(settlement.address);
    await time.increase(2 * 24 * 60 * 60);
    await staking.executeResolverRoleGrant(await slashing.getAddress());
    await slashing.executeResolverRoleGrant(settlement.address);

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
        VerifierSlashing.deploy(ethers.ZeroAddress, admin.address, admin.address)
      ).to.be.revertedWithCustomError(VerifierSlashing, "InvalidStakingContract");

      await expect(
        VerifierSlashing.deploy(admin.address, ethers.ZeroAddress, admin.address)
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

      // Grant role through the timelock
      await slashing.connect(admin).grantSettlementRole(unauthorized.address);
      expect(await slashing.hasRole(SETTLEMENT_ROLE, unauthorized.address)).to.be.false;
      await time.increase(2 * 24 * 60 * 60);
      await slashing.executeResolverRoleGrant(unauthorized.address);
      expect(await slashing.hasRole(SETTLEMENT_ROLE, unauthorized.address)).to.be.true;

      // Revoke role through the timelock
      await slashing.connect(admin).revokeSettlementRole(unauthorized.address);
      expect(await slashing.hasRole(SETTLEMENT_ROLE, unauthorized.address)).to.be.true;
      await time.increase(2 * 24 * 60 * 60);
      await slashing.executeResolverRoleRevoke(unauthorized.address);
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
      try {
        const history = await getSlashHistoryHelper(slashing, verifier1.address, 0, 10);
        expect(history.length).to.equal(1);
        expect(history[0].amount).to.equal(expectedSlashAmount);
        expect(history[0].percentage).to.equal(slashPercentage);
        expect(history[0].reason).to.equal("Incorrect verification");
      } catch (err: any) {
        console.error("DIAGNOSTIC ERROR IN TEST:", err);
        throw err;
      }

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
      ).to.be.revertedWithCustomError(slashing, "BatchLengthMismatch");
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

      const history = await getSlashHistoryHelper(slashing, verifier1.address, 0, 10);
      expect(history.length).to.equal(2);
      expect(history[0].reason).to.equal("First reason");
      expect(history[1].reason).to.equal("Second reason");
      expect(await slashing.getSlashCount(verifier1.address)).to.equal(2);
    });

    it("Should return paginated slash history pages", async function () {
      const { slashing, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      await slashing.connect(settlement).slash(verifier1.address, 10, "First reason");
      await time.increase(3601);
      await slashing.connect(settlement).slash(verifier1.address, 15, "Second reason");
      await time.increase(3601);
      await slashing.connect(settlement).slash(verifier1.address, 20, "Third reason");

      const page1 = await getSlashHistoryHelper(slashing, verifier1.address, 0, 2);
      expect(page1.length).to.equal(2);
      expect(page1[0].reason).to.equal("First reason");
      expect(page1[1].reason).to.equal("Second reason");

      const page2 = await getSlashHistoryHelper(slashing, verifier1.address, 2, 2);
      expect(page2.length).to.equal(1);
      expect(page2[0].reason).to.equal("Third reason");

      const emptyPage = await getSlashHistoryHelper(slashing, verifier1.address, 4, 2);
      expect(emptyPage.length).to.equal(0);
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

  describe("Economic Enforcement Framework", function () {
    it("Should initialize default offence configurations", async function () {
      const { slashing } = await loadFixture(deploySlashingFixture);
      const offenceId = await slashing.OFFENCE_VERIFICATION_FRAUD();
      const config = await slashing.offenceConfigs(offenceId);
      expect(config.slashPercentage).to.equal(50);
      expect(config.reputationPenalty).to.equal(30);
      expect(config.active).to.be.true;
    });

    it("Should successfully execute penalty and route slashed tokens to Treasury", async function () {
      const { token, staking, slashing, admin, settlement, verifier1, stakeAmount } = await loadFixture(deploySlashingFixture);

      const [,, reserve, secFund, insFund, burnAddr] = await ethers.getSigners();
      
      // Set treasury routing splits
      await slashing.connect(admin).setTreasuryRouting(
        reserve.address,
        secFund.address,
        insFund.address,
        burnAddr.address,
        20, // reserve %
        30, // secFund %
        40, // insFund %
        10  // burnAddr %
      );

      // Verify routing config lookup
      const routing = await slashing.getTreasuryRouting();
      expect(routing._treasuryReserve).to.equal(reserve.address);
      expect(routing._pctTreasuryReserve).to.equal(20);

      const offenceId = await slashing.OFFENCE_VERIFICATION_FRAUD();
      
      // Execute penalty (Verification Fraud: 50% slash, 7 days suspension)
      await expect(
        slashing.connect(settlement).executePenalty(verifier1.address, offenceId, "Fraud detected")
      ).to.emit(slashing, "StakeSlashed");

      // Verify Staking balance reduced
      const [finalStake] = await staking.stakes(verifier1.address);
      expect(finalStake).to.equal(stakeAmount / BigInt(2));

      // Verify splits routed correctly
      const expectedSlashed = stakeAmount / BigInt(2);
      expect(await token.balanceOf(reserve.address)).to.equal((expectedSlashed * BigInt(20)) / BigInt(100));
      expect(await token.balanceOf(secFund.address)).to.equal((expectedSlashed * BigInt(30)) / BigInt(100));
      expect(await token.balanceOf(insFund.address)).to.equal((expectedSlashed * BigInt(40)) / BigInt(100));
      expect(await token.balanceOf(burnAddr.address)).to.equal((expectedSlashed * BigInt(10)) / BigInt(100));
    });

    it("Should enforce suspensions and permanent bans", async function () {
      const { slashing, admin, settlement, verifier1 } = await loadFixture(deploySlashingFixture);

      const collusionOffence = await slashing.OFFENCE_VERIFICATION_COLLUSION();
      
      expect(await slashing.isSuspended(verifier1.address)).to.be.false;
      expect(await slashing.isBanned(verifier1.address)).to.be.false;

      // Collusion offence triggers a permanent ban
      await slashing.connect(settlement).executePenalty(verifier1.address, collusionOffence, "Colluded in verification");

      expect(await slashing.isSuspended(verifier1.address)).to.be.true;
      expect(await slashing.isBanned(verifier1.address)).to.be.true;

      // Try to slash again and expect revert
      await expect(
        slashing.connect(settlement).slash(verifier1.address, 10, "Subsequent slash attempt")
      ).to.be.revertedWithCustomError(slashing, "VerifierBanned");
    });
  });
});