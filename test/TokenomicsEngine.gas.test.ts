import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

const BPS_DENOMINATOR = 10_000;

describe("TokenomicsEngine Gas Benchmarks", function () {
  async function deployFixture() {
    const [admin, distributor, sender, other] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockERC20");
    const token = await Token.deploy("Protocol Token", "TKN");

    const TreasuryAccounting = await ethers.getContractFactory("TreasuryAccounting");
    const treasury = await TreasuryAccounting.deploy(
      await token.getAddress(),
      ethers.ZeroAddress,
      await admin.getAddress()
    );

    await treasury.waitForDeployment();

    const TokenomicsEngine = await ethers.getContractFactory("TokenomicsEngine");
    const engine = await TokenomicsEngine.deploy(
      await treasury.getAddress(),
      await token.getAddress(),
      await admin.getAddress(),
      ethers.ZeroAddress
    );

    await engine.waitForDeployment();

    const distributorRole = await engine.DISTRIBUTOR_ROLE();
    await engine.grantRole(distributorRole, await distributor.getAddress());

    const adminRole = await treasury.ADMIN_ROLE();
    await treasury.grantRole(adminRole, await admin.getAddress());
    await treasury.setMinStakingReserveRatio(0);

    const funding = ethers.parseEther("100000");
    await token.mint(await distributor.getAddress(), funding);
    await token.connect(distributor).approve(await engine.getAddress(), funding);

    return {
      engine,
      token,
      treasury,
      admin,
      distributor,
      sender,
      funding,
    };
  }

  it("measures gas for single source distribution", async function () {
    const { engine, distributor, sender } = await loadFixture(deployFixture);
    const amount = ethers.parseEther("1000");

    const tx = await engine
      .connect(distributor)
      .distributeRevenue(0, amount);
    const receipt = await tx.wait();

    console.log(`distributeRevenue gas: ${receipt?.gasUsed.toString()}`);
    expect(receipt?.gasUsed).to.be.greaterThan(0);
  });

  it("measures gas for multi-source batch allocation", async function () {
    const { engine, distributor, sender } = await loadFixture(deployFixture);
    const amount = ethers.parseEther("1000");

    const sources = [0, 1, 2, 3, 4];
    const amounts = [
      amount / 5n,
      amount / 5n,
      amount / 5n,
      amount / 5n,
      amount - (4n * (amount / 5n)),
    ];

    const tx = await engine
      .connect(distributor)
      .allocateBatch(sources, amounts);
    const receipt = await tx.wait();

    console.log(`allocateBatch gas (5 sources): ${receipt?.gasUsed.toString()}`);
    expect(receipt?.gasUsed).to.be.greaterThan(0);
  });

  it("measures gas for allocation configuration update", async function () {
    const { engine, admin } = await loadFixture(deployFixture);

    const newConfig = {
      verifierRewardsBPS: 5000,
      treasuryReserveBPS: 3000,
      ecosystemIncentivesBPS: 0,
      governanceIncentivesBPS: 1000,
      protocolDevelopmentBPS: 500,
      emergencyReserveBPS: 500,
      active: true,
    };

    const tx = await engine
      .connect(admin)
      .setSourceAllocation(0, newConfig);
    const receipt = await tx.wait();

    console.log(`setSourceAllocation gas: ${receipt?.gasUsed.toString()}`);
    expect(receipt?.gasUsed).to.be.greaterThan(0);
  });

  it("measures gas for emission limit update", async function () {
    const { engine, admin } = await loadFixture(deployFixture);

    const tx = await engine
      .connect(admin)
      .setEmissionLimit(ethers.parseEther("50000"));
    const receipt = await tx.wait();

    console.log(`setEmissionLimit gas: ${receipt?.gasUsed.toString()}`);
    expect(receipt?.gasUsed).to.be.greaterThan(0);
  });

  it("measures gas for reward multiplier update", async function () {
    const { engine, admin } = await loadFixture(deployFixture);

    const tx = await engine.connect(admin).setRewardMultiplier(ethers.parseEther("2"));
    const receipt = await tx.wait();

    console.log(`setRewardMultiplier gas: ${receipt?.gasUsed.toString()}`);
    expect(receipt?.gasUsed).to.be.greaterThan(0);
  });

  it("measures gas for treasury reserve target update", async function () {
    const { engine, admin } = await loadFixture(deployFixture);

    const tx = await engine.connect(admin).setTreasuryReserveTarget(3000);
    const receipt = await tx.wait();

    console.log(`setTreasuryReserveTarget gas: ${receipt?.gasUsed.toString()}`);
    expect(receipt?.gasUsed).to.be.greaterThan(0);
  });
});
