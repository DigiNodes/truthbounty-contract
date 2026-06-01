import { expect } from "chai";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";

describe("ReputationReceiver", function () {
  async function deployFixture() {
    const [admin, user, other] = await ethers.getSigners();

    const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
    const ReputationReceiver = await ethers.getContractFactory("ReputationReceiver");

    const oracle = await MockReputationOracle.deploy();
    await oracle.waitForDeployment();

    const receiver = await ReputationReceiver.deploy(admin.address, await oracle.getAddress());
    await receiver.waitForDeployment();

    return { admin, user, other, oracle, receiver };
  }

  function makeLeaf(user: string, score: number, timestamp: number): string {
    const inner = ethers.solidityPackedKeccak256(
      ["address", "uint256", "uint256"],
      [user, score, timestamp]
    );
    return ethers.keccak256(ethers.solidityPacked(["bytes32"], [inner]));
  }

  function makeRoot(left: string, right: string): string {
    return ethers.keccak256(ethers.solidityPacked(["bytes32", "bytes32"], [left, right]));
  }

  it("accepts bridged reputation with calldata proof and stores state", async function () {
    const { admin, user, other, receiver } = await loadFixture(deployFixture);

    await receiver.connect(admin).setChainSupport(1, true);

    const latestBlock = await ethers.provider.getBlock("latest");
    const timestamp = latestBlock.timestamp + 5;
    const score = 1234;

    const leaf = makeLeaf(user.address, score, timestamp);
    const sibling = makeLeaf(other.address, 42, timestamp);
    const root = makeRoot(leaf, sibling);

    await receiver.connect(admin).verifySnapshotRoot(1, 1, root);

    await expect(
      receiver.connect(admin).receiveBridgedReputation(
        user.address,
        1,
        1,
        score,
        timestamp,
        [sibling],
        0
      )
    )
      .to.emit(receiver, "ReputationBridged")
      .withArgs(user.address, 1, score, anyValue);

    expect(await receiver.getBridgedReputation(user.address, 1)).to.equal(score);
    expect(await receiver.isLeafUsed(user.address, score, timestamp)).to.equal(true);
  });

  it("prevents replay of the same bridged leaf", async function () {
    const { admin, user, other, receiver } = await loadFixture(deployFixture);

    await receiver.connect(admin).setChainSupport(1, true);

    const latestBlock = await ethers.provider.getBlock("latest");
    const timestamp = latestBlock.timestamp + 8;
    const score = 2000;

    const leaf = makeLeaf(user.address, score, timestamp);
    const sibling = makeLeaf(other.address, 77, timestamp);
    const root = makeRoot(leaf, sibling);

    await receiver.connect(admin).verifySnapshotRoot(1, 1, root);

    await receiver.connect(admin).receiveBridgedReputation(
      user.address,
      1,
      1,
      score,
      timestamp,
      [sibling],
      0
    );

    await expect(
      receiver.connect(admin).receiveBridgedReputation(
        user.address,
        1,
        1,
        score,
        timestamp,
        [sibling],
        0
      )
    ).to.be.revertedWithCustomError(receiver, "LeafAlreadyUsed");
  });

  it("reverts when the proof is invalid", async function () {
    const { admin, user, other, receiver } = await loadFixture(deployFixture);

    await receiver.connect(admin).setChainSupport(1, true);

    const latestBlock = await ethers.provider.getBlock("latest");
    const timestamp = latestBlock.timestamp + 12;
    const score = 3000;

    const leaf = makeLeaf(user.address, score, timestamp);
    const sibling = makeLeaf(other.address, 123, timestamp);
    const root = makeRoot(leaf, sibling);

    await receiver.connect(admin).verifySnapshotRoot(1, 1, root);

    const badSibling = makeLeaf(user.address, 9999, timestamp);

    await expect(
      receiver.connect(admin).receiveBridgedReputation(
        user.address,
        1,
        1,
        score,
        timestamp,
        [badSibling],
        0
      )
    ).to.be.revertedWithCustomError(receiver, "InvalidProof");
  });

  it("reverts when proof length exceeds limit", async function () {
    const { admin, user, other, receiver } = await loadFixture(deployFixture);

    await receiver.connect(admin).setChainSupport(1, true);

    const latestBlock = await ethers.provider.getBlock("latest");
    const timestamp = latestBlock.timestamp + 20;
    const score = 4000;

    const leaf = makeLeaf(user.address, score, timestamp);
    const sibling = makeLeaf(other.address, 11, timestamp);
    const root = makeRoot(leaf, sibling);

    await receiver.connect(admin).verifySnapshotRoot(1, 1, root);

    // Build an oversized proof (MAX_PROOF_DEPTH + 1)
    const depth = Number(await receiver.MAX_PROOF_DEPTH());
    const bigProof = new Array(depth + 1).fill(sibling);

    await expect(
      receiver.connect(admin).receiveBridgedReputation(
        user.address,
        1,
        1,
        score,
        timestamp,
        bigProof,
        0
      )
    ).to.be.revertedWithCustomError(receiver, "InvalidProofLength");
  });

  it("reverts when proofIndex is out of range", async function () {
    const { admin, user, other, receiver } = await loadFixture(deployFixture);

    await receiver.connect(admin).setChainSupport(1, true);

    const latestBlock = await ethers.provider.getBlock("latest");
    const timestamp = latestBlock.timestamp + 25;
    const score = 5000;

    const leaf = makeLeaf(user.address, score, timestamp);
    const sibling = makeLeaf(other.address, 22, timestamp);
    const root = makeRoot(leaf, sibling);

    await receiver.connect(admin).verifySnapshotRoot(1, 1, root);

    // proof length 1 -> maxLeaves = 2, so proofIndex 2 is invalid
    await expect(
      receiver.connect(admin).receiveBridgedReputation(
        user.address,
        1,
        1,
        score,
        timestamp,
        [sibling],
        2
      )
    ).to.be.revertedWithCustomError(receiver, "InvalidProofIndex");
  });

  it("reverts when timestamp is too old", async function () {
    const { admin, user, other, receiver } = await loadFixture(deployFixture);

    await receiver.connect(admin).setChainSupport(1, true);

    const latestBlock = await ethers.provider.getBlock("latest");
    const maxAge = Number(await receiver.MAX_TIMESTAMP_AGE());
    const timestamp = latestBlock.timestamp - maxAge - 10;
    const score = 6000;

    const leaf = makeLeaf(user.address, score, timestamp);
    const sibling = makeLeaf(other.address, 33, timestamp);
    const root = makeRoot(leaf, sibling);

    await receiver.connect(admin).verifySnapshotRoot(1, 1, root);

    await expect(
      receiver.connect(admin).receiveBridgedReputation(
        user.address,
        1,
        1,
        score,
        timestamp,
        [sibling],
        0
      )
    ).to.be.revertedWithCustomError(receiver, "TimestampTooOld");
  });

  it("reverts when snapshotId is zero", async function () {
    const { admin, user, other, receiver } = await loadFixture(deployFixture);

    await receiver.connect(admin).setChainSupport(1, true);

    const latestBlock = await ethers.provider.getBlock("latest");
    const timestamp = latestBlock.timestamp + 30;
    const score = 7000;

    const leaf = makeLeaf(user.address, score, timestamp);
    const sibling = makeLeaf(other.address, 44, timestamp);
    const root = makeRoot(leaf, sibling);

    // don't verify root under snapshot 0 (invalid)

    await expect(
      receiver.connect(admin).receiveBridgedReputation(
        user.address,
        1,
        0,
        score,
        timestamp,
        [sibling],
        0
      )
    ).to.be.revertedWithCustomError(receiver, "InvalidSnapshotId");
  });
});
