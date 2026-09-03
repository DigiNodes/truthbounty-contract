import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { deployCanonicalV2, CanonicalV2Suite } from "../../scripts/deployCanonicalV2";

describe("Canonical Modular Deployment Composition (SC-031)", () => {
  let deployer: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let suite: CanonicalV2Suite;

  beforeEach(async () => {
    [deployer, user1, user2] = await ethers.getSigners();
    suite = await deployCanonicalV2(deployer);
  });

  describe("Dependency Ordering & Initialization", () => {
    it("deploys all canonical V2 modules with non-zero addresses", async () => {
      expect(await suite.governanceController.getAddress()).to.not.equal(ethers.ZeroAddress);
      expect(await suite.token.getAddress()).to.not.equal(ethers.ZeroAddress);
      expect(await suite.oracle.getAddress()).to.not.equal(ethers.ZeroAddress);
      expect(await suite.claimRegistry.getAddress()).to.not.equal(ethers.ZeroAddress);
      expect(await suite.truthBountyWeighted.getAddress()).to.not.equal(ethers.ZeroAddress);
      expect(await suite.aggregator.getAddress()).to.not.equal(ethers.ZeroAddress);
      expect(await suite.provisionalSettlementEngine.getAddress()).to.not.equal(ethers.ZeroAddress);
      expect(await suite.appealVerificationRound.getAddress()).to.not.equal(ethers.ZeroAddress);
    });

    it("correctly wires cross-module references", async () => {
      // ProvisionalSettlementEngine references ClaimRegistry and Aggregator
      expect(await suite.provisionalSettlementEngine.claimRegistry()).to.equal(
        await suite.claimRegistry.getAddress()
      );
      expect(await suite.provisionalSettlementEngine.aggregator()).to.equal(
        await suite.aggregator.getAddress()
      );

      // Aggregator references VerificationSource (TruthBountyWeighted)
      expect(await suite.aggregator.verificationSource()).to.equal(
        await suite.truthBountyWeighted.getAddress()
      );

      // AppealVerificationRound references Token, ClaimRegistry, Oracle
      expect(await suite.appealVerificationRound.stakingToken()).to.equal(
        await suite.token.getAddress()
      );
      expect(await suite.appealVerificationRound.claimRegistry()).to.equal(
        await suite.claimRegistry.getAddress()
      );
    });

    it("wires REGISTRY_UPDATER_ROLE on ClaimRegistry to ProvisionalSettlementEngine", async () => {
      const REGISTRY_UPDATER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("REGISTRY_UPDATER_ROLE"));
      expect(
        await suite.claimRegistry.hasRole(
          REGISTRY_UPDATER_ROLE,
          await suite.provisionalSettlementEngine.getAddress()
        )
      ).to.be.true;
    });
  });

  describe("Legacy Exclusion & Security Checks", () => {
    it("does not grant REGISTRY_UPDATER_ROLE or admin to unapproved or legacy addresses", async () => {
      const REGISTRY_UPDATER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("REGISTRY_UPDATER_ROLE"));
      expect(await suite.claimRegistry.hasRole(REGISTRY_UPDATER_ROLE, user1.address)).to.be.false;
      expect(await suite.claimRegistry.hasRole(REGISTRY_UPDATER_ROLE, user2.address)).to.be.false;
    });

    it("supports deployer privilege finalization", async () => {
      const finalizedSuite = await deployCanonicalV2(deployer, { finalizeDeployerRoles: true });
      const REGISTRY_UPDATER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("REGISTRY_UPDATER_ROLE"));

      expect(
        await finalizedSuite.claimRegistry.hasRole(
          REGISTRY_UPDATER_ROLE,
          await finalizedSuite.provisionalSettlementEngine.getAddress()
        )
      ).to.be.true;
    });
  });

  describe("Idempotency & Isolation", () => {
    it("deploys independent isolated instances across consecutive runs", async () => {
      const suite2 = await deployCanonicalV2(deployer);
      expect(await suite2.claimRegistry.getAddress()).to.not.equal(
        await suite.claimRegistry.getAddress()
      );
      expect(await suite2.provisionalSettlementEngine.getAddress()).to.not.equal(
        await suite.provisionalSettlementEngine.getAddress()
      );
    });
  });
});
