import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

describe("RewardEngine SC-011 Fuzz and Invariants", function () {
  async function deployFixture() {
    const [admin, distributor, verifier] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockRewardToken");
    const token = await Token.deploy();

    const Oracle = await ethers.getContractFactory(
      "MockRewardReputationOracle"
    );
    const oracle = await Oracle.deploy();

    const RewardEngine = await ethers.getContractFactory("RewardEngine");
    const rewards = await RewardEngine.deploy(
      await oracle.getAddress(),
      admin.address,
      admin.address
    );

    await rewards.setRewardToken(await token.getAddress());

    const distributorRole = await rewards.DISTRIBUTOR_ROLE();
    await rewards.grantRole(distributorRole, distributor.address);

    const funding = ethers.parseEther("1000000");
    await token.approve(await rewards.getAddress(), funding);
    await rewards.fundRewardPool(funding);

    return {
      admin,
      distributor,
      verifier,
      token,
      oracle,
      rewards,
      funding,
    };
  }

  function settlementId(index: number): string {
    return ethers.keccak256(
      ethers.solidityPacked(["string", "uint256"], ["settlement", index])
    );
  }

  function calculationId(index: number): string {
    return ethers.keccak256(
      ethers.solidityPacked(["string", "uint256"], ["calculation", index])
    );
  }

  it("allocates deterministic rewards across varied amounts", async function () {
    const { rewards, distributor, verifier } =
      await loadFixture(deployFixture);

    const amounts = [
      1n,
      ethers.parseEther("0.001"),
      ethers.parseEther("1"),
      ethers.parseEther("17"),
      ethers.parseEther("100"),
      ethers.parseEther("999"),
      ethers.parseEther("5000"),
    ];

    let expectedReserved = 0n;

    for (let i = 0; i < amounts.length; i++) {
      await rewards.connect(distributor).allocateReward(
        verifier.address,
        i + 1,
        settlementId(i),
        calculationId(i),
        amounts[i],
        false
      );

      expectedReserved += amounts[i];
    }

    expect(await rewards.totalAllocated()).to.equal(expectedReserved);
    expect(await rewards.totalReserved()).to.equal(expectedReserved);
    expect(await rewards.claimableRewards(verifier.address)).to.equal(
      expectedReserved
    );
  });

  it("preserves reward-pool accounting invariant", async function () {
    const {
      rewards,
      token,
      distributor,
      verifier,
      funding,
    } = await loadFixture(deployFixture);

    const immediateAmounts = [
      ethers.parseEther("10"),
      ethers.parseEther("20"),
      ethers.parseEther("30"),
    ];

    const claimableAmounts = [
      ethers.parseEther("15"),
      ethers.parseEther("25"),
      ethers.parseEther("35"),
    ];

    let expectedDistributed = 0n;
    let expectedReserved = 0n;

    for (let i = 0; i < immediateAmounts.length; i++) {
      await rewards.connect(distributor).allocateReward(
        verifier.address,
        100 + i,
        settlementId(100 + i),
        calculationId(100 + i),
        immediateAmounts[i],
        true
      );

      expectedDistributed += immediateAmounts[i];
    }

    for (let i = 0; i < claimableAmounts.length; i++) {
      await rewards.connect(distributor).allocateReward(
        verifier.address,
        200 + i,
        settlementId(200 + i),
        calculationId(200 + i),
        claimableAmounts[i],
        false
      );

      expectedReserved += claimableAmounts[i];
    }

    const engineBalance = await token.balanceOf(
      await rewards.getAddress()
    );

    expect(await rewards.totalDistributed()).to.equal(expectedDistributed);
    expect(await rewards.totalReserved()).to.equal(expectedReserved);

    expect(engineBalance + expectedDistributed).to.equal(funding);

    expect(
      (await rewards.availableRewardBalance()) + expectedReserved
    ).to.equal(engineBalance);
  });

  it("never distributes more than total funded rewards", async function () {
    const {
      rewards,
      distributor,
      verifier,
      funding,
    } = await loadFixture(deployFixture);

    await rewards.connect(distributor).allocateReward(
      verifier.address,
      1,
      settlementId(1),
      calculationId(1),
      funding,
      true
    );

    expect(await rewards.totalDistributed()).to.equal(funding);
    expect(await rewards.availableRewardBalance()).to.equal(0);

    await expect(
      rewards.connect(distributor).allocateReward(
        verifier.address,
        2,
        settlementId(2),
        calculationId(2),
        1,
        true
      )
    ).to.be.revertedWithCustomError(
      rewards,
      "InsufficientRewardPool"
    );
  });

  it("rejects replayed settlement allocations", async function () {
    const { rewards, distributor, verifier } =
      await loadFixture(deployFixture);

    const amount = ethers.parseEther("10");
    const settlement = settlementId(700);
    const calculation = calculationId(700);

    await rewards.connect(distributor).allocateReward(
      verifier.address,
      700,
      settlement,
      calculation,
      amount,
      false
    );

    for (let i = 0; i < 5; i++) {
      await expect(
        rewards.connect(distributor).allocateReward(
          verifier.address,
          700,
          settlement,
          calculation,
          amount,
          false
        )
      ).to.be.revertedWithCustomError(
        rewards,
        "DuplicateRewardSettlement"
      );
    }
  });

  it("records gas for reward allocation and claiming", async function () {
    const { rewards, distributor, verifier } =
      await loadFixture(deployFixture);

    const amount = ethers.parseEther("100");

    const allocationTx = await rewards
      .connect(distributor)
      .allocateReward(
        verifier.address,
        900,
        settlementId(900),
        calculationId(900),
        amount,
        false
      );

    const allocationReceipt = await allocationTx.wait();

    const distributionId = ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "bytes32", "bytes32"],
        [
          verifier.address,
          900,
          settlementId(900),
          calculationId(900),
        ]
      )
    );

    const claimTx = await rewards
      .connect(verifier)
      .claimReward(distributionId);

    const claimReceipt = await claimTx.wait();

    console.log(
      `allocateReward gas: ${allocationReceipt?.gasUsed.toString()}`
    );

    console.log(
      `claimReward gas: ${claimReceipt?.gasUsed.toString()}`
    );

    expect(allocationReceipt?.gasUsed).to.be.greaterThan(0);
    expect(claimReceipt?.gasUsed).to.be.greaterThan(0);
  });
});
