import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

describe("RewardEngine SC-011 Distribution", function () {
  async function deployFixture() {
    const [admin, distributor, verifier, verifierTwo, outsider] =
      await ethers.getSigners();

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

    const funding = ethers.parseEther("100000");
    await token.approve(await rewards.getAddress(), funding);
    await rewards.fundRewardPool(funding);

    const settlementA = ethers.id("settlement-a");
    const settlementB = ethers.id("settlement-b");
    const calculationA = ethers.id("calculation-a");
    const calculationB = ethers.id("calculation-b");

    return {
      admin,
      distributor,
      verifier,
      verifierTwo,
      outsider,
      token,
      oracle,
      rewards,
      funding,
      settlementA,
      settlementB,
      calculationA,
      calculationB,
    };
  }

  function distributionId(
    recipient: string,
    claimId: bigint,
    settlementId: string,
    calculationId: string
  ) {
    return ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "bytes32", "bytes32"],
        [recipient, claimId, settlementId, calculationId]
      )
    );
  }

  it("funds the Treasury-backed reward pool", async function () {
    const { rewards, token, funding } = await loadFixture(deployFixture);

    expect(await rewards.totalFunded()).to.equal(funding);
    expect(await token.balanceOf(await rewards.getAddress())).to.equal(funding);
    expect(await rewards.availableRewardBalance()).to.equal(funding);
  });

  it("allocates a claimable reward and records complete metadata", async function () {
    const {
      rewards,
      distributor,
      verifier,
      settlementA,
      calculationA,
    } = await loadFixture(deployFixture);

    const amount = ethers.parseEther("250");
    const claimId = 77n;

    const id = distributionId(
      verifier.address,
      claimId,
      settlementA,
      calculationA
    );

    await expect(
      rewards.connect(distributor).allocateReward(
        verifier.address,
        claimId,
        settlementA,
        calculationA,
        amount,
        false
      )
    )
      .to.emit(rewards, "RewardAllocated")
      .withArgs(
        verifier.address,
        claimId,
        settlementA,
        id,
        amount,
        false
      );

    const record = await rewards.rewardDistributions(id);

    expect(record.recipient).to.equal(verifier.address);
    expect(record.claimId).to.equal(claimId);
    expect(record.settlementId).to.equal(settlementA);
    expect(record.calculationId).to.equal(calculationA);
    expect(record.amount).to.equal(amount);
    expect(record.status).to.equal(1);
    expect(record.distributionId).to.equal(id);

    expect(await rewards.claimableRewards(verifier.address)).to.equal(amount);
    expect(await rewards.totalAllocated()).to.equal(amount);
    expect(await rewards.totalReserved()).to.equal(amount);
    expect(await rewards.totalDistributed()).to.equal(0);
  });

  it("allows the recipient to claim an allocated reward", async function () {
    const {
      rewards,
      token,
      distributor,
      verifier,
      settlementA,
      calculationA,
    } = await loadFixture(deployFixture);

    const amount = ethers.parseEther("500");
    const claimId = 10n;

    const id = distributionId(
      verifier.address,
      claimId,
      settlementA,
      calculationA
    );

    await rewards.connect(distributor).allocateReward(
      verifier.address,
      claimId,
      settlementA,
      calculationA,
      amount,
      false
    );

    await expect(rewards.connect(verifier).claimReward(id))
      .to.emit(rewards, "RewardClaimed")
      .withArgs(verifier.address, id, amount);

    expect(await token.balanceOf(verifier.address)).to.equal(amount);
    expect(await rewards.claimableRewards(verifier.address)).to.equal(0);
    expect(await rewards.totalReserved()).to.equal(0);
    expect(await rewards.totalDistributed()).to.equal(amount);

    const record = await rewards.rewardDistributions(id);
    expect(record.status).to.equal(2);
  });

  it("supports immediate automatic reward distribution", async function () {
    const {
      rewards,
      token,
      distributor,
      verifier,
      settlementA,
      calculationA,
    } = await loadFixture(deployFixture);

    const amount = ethers.parseEther("100");

    await expect(
      rewards.connect(distributor).allocateReward(
        verifier.address,
        1,
        settlementA,
        calculationA,
        amount,
        true
      )
    )
      .to.emit(rewards, "RewardDistributed")
      .withArgs(verifier.address, 1, settlementA, amount);

    expect(await token.balanceOf(verifier.address)).to.equal(amount);
    expect(await rewards.totalDistributed()).to.equal(amount);
    expect(await rewards.totalReserved()).to.equal(0);
  });

  it("rejects duplicate settlement reward allocation", async function () {
    const {
      rewards,
      distributor,
      verifier,
      settlementA,
      calculationA,
    } = await loadFixture(deployFixture);

    const amount = ethers.parseEther("50");

    await rewards.connect(distributor).allocateReward(
      verifier.address,
      9,
      settlementA,
      calculationA,
      amount,
      false
    );

    await expect(
      rewards.connect(distributor).allocateReward(
        verifier.address,
        9,
        settlementA,
        calculationA,
        amount,
        false
      )
    ).to.be.revertedWithCustomError(
      rewards,
      "DuplicateRewardSettlement"
    );
  });

  it("prevents unauthorized reward allocation and claiming", async function () {
    const {
      rewards,
      distributor,
      verifier,
      outsider,
      settlementA,
      calculationA,
    } = await loadFixture(deployFixture);

    const amount = ethers.parseEther("25");

    await expect(
      rewards.connect(outsider).allocateReward(
        verifier.address,
        3,
        settlementA,
        calculationA,
        amount,
        false
      )
    ).to.be.reverted;

    const id = distributionId(
      verifier.address,
      3n,
      settlementA,
      calculationA
    );

    await rewards.connect(distributor).allocateReward(
      verifier.address,
      3,
      settlementA,
      calculationA,
      amount,
      false
    );

    await expect(
      rewards.connect(outsider).claimReward(id)
    ).to.be.revertedWithCustomError(
      rewards,
      "UnauthorizedRewardClaim"
    );
  });

  it("prevents reward-pool overspending", async function () {
    const {
      rewards,
      distributor,
      verifier,
      funding,
      settlementA,
      calculationA,
    } = await loadFixture(deployFixture);

    await expect(
      rewards.connect(distributor).allocateReward(
        verifier.address,
        4,
        settlementA,
        calculationA,
        funding + 1n,
        false
      )
    ).to.be.revertedWithCustomError(
      rewards,
      "InsufficientRewardPool"
    );
  });

  it("supports batched allocation and batched claiming", async function () {
    const {
      rewards,
      token,
      distributor,
      verifier,
      settlementA,
      settlementB,
      calculationA,
      calculationB,
    } = await loadFixture(deployFixture);

    const firstAmount = ethers.parseEther("40");
    const secondAmount = ethers.parseEther("60");

    const firstId = distributionId(
      verifier.address,
      101n,
      settlementA,
      calculationA
    );

    const secondId = distributionId(
      verifier.address,
      102n,
      settlementB,
      calculationB
    );

    await expect(
      rewards.connect(distributor).allocateRewardsBatch(
        [verifier.address, verifier.address],
        [101, 102],
        [settlementA, settlementB],
        [calculationA, calculationB],
        [firstAmount, secondAmount],
        [false, false]
      )
    )
      .to.emit(rewards, "BatchRewardAllocationCompleted")
      .withArgs(2);

    await expect(
      rewards.connect(verifier).claimRewardsBatch([firstId, secondId])
    )
      .to.emit(rewards, "BatchRewardClaimCompleted")
      .withArgs(
        verifier.address,
        2,
        firstAmount + secondAmount
      );

    expect(await token.balanceOf(verifier.address)).to.equal(
      firstAmount + secondAmount
    );

    expect(await rewards.totalDistributed()).to.equal(
      firstAmount + secondAmount
    );

    expect(await rewards.totalReserved()).to.equal(0);
  });

  it("preserves Treasury accounting after mixed distributions", async function () {
    const {
      rewards,
      token,
      distributor,
      verifier,
      verifierTwo,
      funding,
      settlementA,
      settlementB,
      calculationA,
      calculationB,
    } = await loadFixture(deployFixture);

    const immediateAmount = ethers.parseEther("125");
    const reservedAmount = ethers.parseEther("275");

    await rewards.connect(distributor).allocateReward(
      verifier.address,
      201,
      settlementA,
      calculationA,
      immediateAmount,
      true
    );

    await rewards.connect(distributor).allocateReward(
      verifierTwo.address,
      202,
      settlementB,
      calculationB,
      reservedAmount,
      false
    );

    const contractBalance = await token.balanceOf(
      await rewards.getAddress()
    );

    expect(contractBalance).to.equal(funding - immediateAmount);
    expect(await rewards.totalAllocated()).to.equal(
      immediateAmount + reservedAmount
    );
    expect(await rewards.totalDistributed()).to.equal(immediateAmount);
    expect(await rewards.totalReserved()).to.equal(reservedAmount);

    expect(await rewards.availableRewardBalance()).to.equal(
      funding - immediateAmount - reservedAmount
    );
  });
});
