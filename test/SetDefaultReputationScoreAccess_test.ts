import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

/**
 * Issue #158 — Missing onlyGovernanceOrAdmin on setDefaultReputationScore
 *
 * setDefaultReputationScore previously used `onlyRole(ADMIN_ROLE)`, which is
 * inconsistent with every sibling reputation-parameter setter
 * (setMinReputationScore, setMaxReputationScore, setWeightedStakingEnabled,
 * setSqrtWeighting) and locked the governance controller out of updating this
 * parameter. The guard is now `onlyGovernanceOrAdmin`, which admits
 * GOVERNANCE_ROLE, DEFAULT_ADMIN_ROLE, or the emergencyAdmin.
 *
 * These tests deploy with a DISTINCT admin and governance controller so the
 * difference between the two guards is observable (the existing
 * WeightedStaking_test.ts fixture uses the same signer for both roles, which
 * would mask the change).
 */
describe("WeightedStaking — setDefaultReputationScore access control (#158)", function () {
  let weightedStaking: Contract;
  let mockOracle: Contract;
  let admin: Signer;        // holds DEFAULT_ADMIN_ROLE + ADMIN_ROLE
  let governance: Signer;   // holds GOVERNANCE_ROLE only
  let outsider: Signer;     // holds nothing

  const DEFAULT_REPUTATION = ethers.parseEther("1");
  const NEW_DEFAULT = ethers.parseEther("1.5");

  beforeEach(async function () {
    [admin, governance, outsider] = await ethers.getSigners();

    const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
    mockOracle = await MockReputationOracle.deploy();
    await mockOracle.waitForDeployment();

    const WeightedStaking = await ethers.getContractFactory("contracts/WeightedStaking.sol:WeightedStaking");
    // initialAdmin = admin, governanceController = governance (DISTINCT addresses)
    weightedStaking = await WeightedStaking.deploy(
      await mockOracle.getAddress(),
      await admin.getAddress(),
      await governance.getAddress()
    );
    await weightedStaking.waitForDeployment();
  });

  describe("Authorized callers", function () {
    it("Should allow the admin (DEFAULT_ADMIN_ROLE) to update the default score", async function () {
      await expect(weightedStaking.connect(admin).setDefaultReputationScore(NEW_DEFAULT))
        .to.emit(weightedStaking, "DefaultReputationUpdated")
        .withArgs(NEW_DEFAULT);

      const config = await weightedStaking.getConfiguration();
      expect(config.defaultScore).to.equal(NEW_DEFAULT);
    });

    it("Should allow the governance controller (GOVERNANCE_ROLE) to update the default score", async function () {
      // This is the core of the fix: under the old onlyRole(ADMIN_ROLE) guard
      // this call reverted, locking governance out of the parameter.
      await expect(weightedStaking.connect(governance).setDefaultReputationScore(NEW_DEFAULT))
        .to.emit(weightedStaking, "DefaultReputationUpdated")
        .withArgs(NEW_DEFAULT);

      const config = await weightedStaking.getConfiguration();
      expect(config.defaultScore).to.equal(NEW_DEFAULT);
    });
  });

  describe("Unauthorized callers", function () {
    it("Should revert with UnauthorizedGovernance when called by an outsider", async function () {
      await expect(
        weightedStaking.connect(outsider).setDefaultReputationScore(NEW_DEFAULT)
      ).to.be.revertedWithCustomError(weightedStaking, "UnauthorizedGovernance");

      // State must be unchanged after a rejected call.
      const config = await weightedStaking.getConfiguration();
      expect(config.defaultScore).to.equal(DEFAULT_REPUTATION);
    });
  });

  describe("Input validation is preserved", function () {
    it("Should still revert with InvalidDefaultReputation on a zero score (admin)", async function () {
      await expect(
        weightedStaking.connect(admin).setDefaultReputationScore(0)
      ).to.be.revertedWithCustomError(weightedStaking, "InvalidDefaultReputation");
    });

    it("Should still revert with InvalidDefaultReputation on a zero score (governance)", async function () {
      await expect(
        weightedStaking.connect(governance).setDefaultReputationScore(0)
      ).to.be.revertedWithCustomError(weightedStaking, "InvalidDefaultReputation");
    });

    it("Should reject a zero score for an outsider on the access check, not the value check", async function () {
      // Access control runs before input validation, so an outsider sending 0
      // gets UnauthorizedGovernance (not InvalidDefaultReputation).
      await expect(
        weightedStaking.connect(outsider).setDefaultReputationScore(0)
      ).to.be.revertedWithCustomError(weightedStaking, "UnauthorizedGovernance");
    });
  });

  describe("Consistency with sibling setters", function () {
    it("setDefaultReputationScore now matches setDefaultReputationScoreByGov on access", async function () {
      // Both governance-or-admin paths should land the same value and emit.
      await weightedStaking.connect(governance).setDefaultReputationScore(NEW_DEFAULT);
      expect((await weightedStaking.getConfiguration()).defaultScore).to.equal(NEW_DEFAULT);

      const another = ethers.parseEther("2");
      await weightedStaking.connect(governance).setDefaultReputationScoreByGov(another);
      expect((await weightedStaking.getConfiguration()).defaultScore).to.equal(another);
    });
  });
});
