import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("Tie Resolution", function () {
  const MIN_STAKE = ethers.parseEther("100");
  const VERIFICATION_WINDOW = 7 * 24 * 60 * 60;
  const CONFIRMATION_DELAY = 1 * 60 * 60;

  async function deployFixture() {
    const [owner, submitter, verifier1, verifier2] = await ethers.getSigners();

    const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
    const token = await TruthBountyToken.deploy(owner.address);
    await token.waitForDeployment();

    const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
    const oracle = await MockReputationOracle.deploy();
    await oracle.waitForDeployment();

    const TruthBounty = await ethers.getContractFactory("TruthBounty");
    const legacy = await TruthBounty.deploy(
      await token.getAddress(),
      owner.address,
      ethers.ZeroAddress
    );
    await legacy.waitForDeployment();

    const TruthBountyWeighted = await ethers.getContractFactory("TruthBountyWeighted");
    const weighted = await TruthBountyWeighted.deploy(
      await token.getAddress(),
      await oracle.getAddress(),
      owner.address,
      ethers.ZeroAddress
    );
    await weighted.waitForDeployment();

    const fundAmount = ethers.parseEther("1000");
    for (const verifier of [verifier1, verifier2]) {
      await token.transfer(verifier.address, fundAmount);
      await token.connect(verifier).approve(await legacy.getAddress(), fundAmount);
      await token.connect(verifier).approve(await weighted.getAddress(), fundAmount);
    }

    return { owner, submitter, verifier1, verifier2, token, oracle, legacy, weighted };
  }

  async function prepareTie(contract: any, submitter: any, verifier1: any, verifier2: any) {
    await contract.connect(verifier1).stake(MIN_STAKE);
    await contract.connect(verifier2).stake(MIN_STAKE);

    const tx = await contract.connect(submitter).createClaim("ipfs://tie-case");
    await tx.wait();

    await contract.connect(verifier1).vote(0, true, MIN_STAKE);
    await contract.connect(verifier2).vote(0, false, MIN_STAKE);

    await time.increase(VERIFICATION_WINDOW + CONFIRMATION_DELAY + 1);
    await contract.settleClaim(0);
  }

  it("refunds all stake on an exact tie in TruthBounty", async function () {
    const { submitter, verifier1, verifier2, legacy, token } = await deployFixture();

    await prepareTie(legacy, submitter, verifier1, verifier2);

    const settlement = await legacy.settlementResults(0);
    expect(settlement.totalRewards).to.equal(0);
    expect(settlement.totalSlashed).to.equal(0);
    expect(settlement.winnerStake).to.equal(0);
    expect(settlement.loserStake).to.equal(0);

    const before1 = await token.balanceOf(verifier1.address);
    const before2 = await token.balanceOf(verifier2.address);

    await expect(legacy.connect(verifier1).claimSettlementRewards(0))
      .to.emit(legacy, "StakeWithdrawn")
      .withArgs(verifier1.address, MIN_STAKE);

    await expect(legacy.connect(verifier2).withdrawSettledStake(0))
      .to.emit(legacy, "StakeWithdrawn")
      .withArgs(verifier2.address, MIN_STAKE);

    const after1 = await token.balanceOf(verifier1.address);
    const after2 = await token.balanceOf(verifier2.address);

    expect(after1 - before1).to.equal(MIN_STAKE);
    expect(after2 - before2).to.equal(MIN_STAKE);
  });

  it("refunds all stake on an exact tie in TruthBountyWeighted", async function () {
    const { submitter, verifier1, verifier2, weighted, token } = await deployFixture();

    await prepareTie(weighted, submitter, verifier1, verifier2);

    const settlement = await weighted.settlementResults(0);
    expect(settlement.totalRewards).to.equal(0);
    expect(settlement.totalSlashed).to.equal(0);
    expect(settlement.winnerWeightedStake).to.equal(0);
    expect(settlement.loserWeightedStake).to.equal(0);

    const before1 = await token.balanceOf(verifier1.address);
    const before2 = await token.balanceOf(verifier2.address);

    await expect(weighted.connect(verifier1).claimSettlementRewards(0))
      .to.emit(weighted, "StakeWithdrawn")
      .withArgs(verifier1.address, MIN_STAKE);

    await expect(weighted.connect(verifier2).withdrawSettledStake(0))
      .to.emit(weighted, "StakeWithdrawn")
      .withArgs(verifier2.address, MIN_STAKE);

    const after1 = await token.balanceOf(verifier1.address);
    const after2 = await token.balanceOf(verifier2.address);

    expect(after1 - before1).to.equal(MIN_STAKE);
    expect(after2 - before2).to.equal(MIN_STAKE);
  });
});
