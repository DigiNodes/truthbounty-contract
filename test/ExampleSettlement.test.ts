import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

describe("ExampleSettlement", function () {
  async function deployFixture() {
    const [owner, verifier, claimant, other] = await ethers.getSigners();

    // Deploy TruthBountyToken
    const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
    const token = await TruthBountyToken.deploy(owner.address);

    // Deploy Mock/Staking just to satisfy VerifierSlashing dependencies
    const Staking = await ethers.getContractFactory("Staking");
    const staking = await Staking.deploy(await token.getAddress(), 86400, owner.address);

    // Deploy VerifierSlashing
    const VerifierSlashing = await ethers.getContractFactory("VerifierSlashing");
    const slashing = await VerifierSlashing.deploy(await staking.getAddress(), owner.address);

    // Deploy ExampleSettlement
    const ExampleSettlement = await ethers.getContractFactory("ExampleSettlement");
    const settlement = await ExampleSettlement.deploy(
      await slashing.getAddress(),
      await token.getAddress()
    );

    // Grant settlement role to the ExampleSettlement contract on the slashing contract
    const SETTLEMENT_ROLE = await slashing.SETTLEMENT_ROLE();
    await slashing.grantRole(SETTLEMENT_ROLE, await settlement.getAddress());

    // Setup stakes for verifier to allow slashing tests
    const stakeAmount = ethers.parseEther("1000");
    await token.transfer(verifier.address, stakeAmount);
    await token.connect(verifier).approve(await staking.getAddress(), stakeAmount);
    await staking.connect(verifier).stake(stakeAmount);
    await staking.setSlashingContract(await slashing.getAddress());

    return {
      token,
      staking,
      slashing,
      settlement,
      owner,
      verifier,
      claimant,
      other,
      stakeAmount,
    };
  }

  describe("Deployment", function () {
    it("Should deploy successfully and set the correct state variables", async function () {
      const { settlement, slashing, token } = await loadFixture(deployFixture);

      expect(await settlement.slashingContract()).to.equal(await slashing.getAddress());
      expect(await settlement.bountyToken()).to.equal(await token.getAddress());
    });

    it("Should revert if slashing contract address is zero", async function () {
      const { token } = await loadFixture(deployFixture);
      const ExampleSettlement = await ethers.getContractFactory("ExampleSettlement");
      await expect(
        ExampleSettlement.deploy(ethers.ZeroAddress, await token.getAddress())
      ).to.be.revertedWith("Invalid slashing contract");
    });

    it("Should revert if token address is zero", async function () {
      const { slashing } = await loadFixture(deployFixture);
      const ExampleSettlement = await ethers.getContractFactory("ExampleSettlement");
      await expect(
        ExampleSettlement.deploy(await slashing.getAddress(), ethers.ZeroAddress)
      ).to.be.revertedWith("Invalid token address");
    });
  });

  describe("Claim Lifecycle", function () {
    it("Should allow submitting a claim", async function () {
      const { settlement, verifier, claimant } = await loadFixture(deployFixture);

      await expect(settlement.connect(claimant).submitClaim(verifier.address, "ipfs://somehash"))
        .to.emit(settlement, "ClaimSubmitted")
        .withArgs(0, claimant.address, verifier.address);

      const claim = await settlement.getClaims(0); // claims mapping is public, but let's check view helper if available
      // wait, the mapping is claims(uint256) -> claimant, verifier, data, status, timestamp, verificationCorrect
      const claimDetails = await settlement.claims(0);
      expect(claimDetails.claimant).to.equal(claimant.address);
      expect(claimDetails.verifier).to.equal(verifier.address);
      expect(claimDetails.data).to.equal("ipfs://somehash");
      expect(claimDetails.status).to.equal(0); // ClaimStatus.Pending
    });

    it("Should allow settling a claim and slash the verifier if incorrect", async function () {
      const { settlement, slashing, verifier, claimant, owner, staking } = await loadFixture(deployFixture);

      await settlement.connect(claimant).submitClaim(verifier.address, "ipfs://somehash");

      // Verify and settle (incorrect decision, should trigger slashing)
      const slashPercentage = 20; // incorrectVerificationSlashPercentage is 20%
      const initialStake = (await staking.stakes(verifier.address)).amount;

      await expect(settlement.connect(owner).settleClaim(0, false, false))
        .to.emit(settlement, "ClaimSettled")
        .withArgs(0, false)
        .and.to.emit(settlement, "VerifierSlashed")
        .withArgs(0, verifier.address, slashPercentage, "Incorrect verification for claim #0");

      const finalStake = (await staking.stakes(verifier.address)).amount;
      expect(finalStake).to.equal(initialStake - (initialStake * BigInt(slashPercentage)) / BigInt(100));
    });

    it("Should allow settling a claim and slash the verifier with higher percentage if malicious", async function () {
      const { settlement, verifier, claimant, owner, staking } = await loadFixture(deployFixture);

      await settlement.connect(claimant).submitClaim(verifier.address, "ipfs://somehash");

      const slashPercentage = 50; // maliciousVerificationSlashPercentage is 50%
      const initialStake = (await staking.stakes(verifier.address)).amount;

      await expect(settlement.connect(owner).settleClaim(0, false, true))
        .to.emit(settlement, "ClaimSettled")
        .withArgs(0, false)
        .and.to.emit(settlement, "VerifierSlashed")
        .withArgs(0, verifier.address, slashPercentage, "Malicious verification for claim #0");

      const finalStake = (await staking.stakes(verifier.address)).amount;
      expect(finalStake).to.equal(initialStake - (initialStake * BigInt(slashPercentage)) / BigInt(100));
    });

    it("Should not slash if verification was correct", async function () {
      const { settlement, verifier, claimant, owner, staking } = await loadFixture(deployFixture);

      await settlement.connect(claimant).submitClaim(verifier.address, "ipfs://somehash");

      const initialStake = (await staking.stakes(verifier.address)).amount;

      await expect(settlement.connect(owner).settleClaim(0, true, false))
        .to.emit(settlement, "ClaimSettled")
        .withArgs(0, true)
        .to.not.emit(settlement, "VerifierSlashed");

      const finalStake = (await staking.stakes(verifier.address)).amount;
      expect(finalStake).to.equal(initialStake);
    });

    it("Should batch settle claims", async function () {
      const { settlement, verifier, claimant, owner } = await loadFixture(deployFixture);

      await settlement.connect(claimant).submitClaim(verifier.address, "hash1");
      await settlement.connect(claimant).submitClaim(verifier.address, "hash2");

      await expect(
        settlement.connect(owner).batchSettleClaims([0, 1], [true, true], [false, false])
      ).to.emit(settlement, "ClaimSettled");
    });
  });

  describe("Admin Functions", function () {
    it("Should allow owner to update slashing percentages", async function () {
      const { settlement, owner } = await loadFixture(deployFixture);

      await settlement.connect(owner).updateSlashingPercentages(30, 60);
      expect(await settlement.incorrectVerificationSlashPercentage()).to.equal(30);
      expect(await settlement.maliciousVerificationSlashPercentage()).to.equal(60);
    });

    it("Should revert if owner tries to update invalid slashing percentages", async function () {
      const { settlement, owner } = await loadFixture(deployFixture);

      await expect(
        settlement.connect(owner).updateSlashingPercentages(101, 50)
      ).to.be.revertedWith("Invalid percentage");

      await expect(
        settlement.connect(owner).updateSlashingPercentages(30, 20)
      ).to.be.revertedWith("Malicious penalty should be higher");
    });

    it("Should allow owner to update slashing contract", async function () {
      const { settlement, owner, other } = await loadFixture(deployFixture);

      await settlement.connect(owner).updateSlashingContract(other.address);
      expect(await settlement.slashingContract()).to.equal(other.address);
    });
  });
});
