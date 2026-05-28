import { expect } from "chai";
import { ethers } from "hardhat";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

describe("ReputationReceiver", function () {
  async function deployFixture() {
    const [admin, receiver, user] = await ethers.getSigners();

    const MockReputationOracle =
      await ethers.getContractFactory("MockReputationOracle");
    const oracle = await MockReputationOracle.deploy();
    await oracle.waitForDeployment();

    const ReputationReceiver =
      await ethers.getContractFactory("ReputationReceiver");
    const reputationReceiver = await ReputationReceiver.deploy(
      admin.address,
      await oracle.getAddress()
    );
    await reputationReceiver.waitForDeployment();

    return { admin, receiver, user, oracle, reputationReceiver };
  }

  function leafFor(user: string, score: bigint, timestamp: bigint) {
    return ethers.solidityPackedKeccak256(
      ["address", "uint256", "uint256"],
      [user, score, timestamp]
    );
  }

  it("rejects invalid constructor addresses", async function () {
    const [admin] = await ethers.getSigners();
    const MockReputationOracle =
      await ethers.getContractFactory("MockReputationOracle");
    const oracle = await MockReputationOracle.deploy();
    await oracle.waitForDeployment();

    const ReputationReceiver =
      await ethers.getContractFactory("ReputationReceiver");

    await expect(
      ReputationReceiver.deploy(ethers.ZeroAddress, await oracle.getAddress())
    ).to.be.revertedWithCustomError(ReputationReceiver, "InvalidAdmin");

    await expect(
      ReputationReceiver.deploy(admin.address, ethers.ZeroAddress)
    ).to.be.revertedWithCustomError(ReputationReceiver, "InvalidOracle");
  });

  it("rejects invalid snapshot roots", async function () {
    const { reputationReceiver } = await deployFixture();

    await expect(
      reputationReceiver.verifySnapshotRoot(0, 1, ethers.keccak256("0x01"))
    ).to.be.revertedWithCustomError(
      reputationReceiver,
      "InvalidSourceChainId"
    );

    await expect(
      reputationReceiver.verifySnapshotRoot(1, 1, ethers.ZeroHash)
    ).to.be.revertedWithCustomError(
      reputationReceiver,
      "InvalidSnapshotRoot"
    );
  });

  it("rejects malformed bridged reputation payloads before proof verification", async function () {
    const { reputationReceiver, user } = await deployFixture();
    const score = 42n;
    const timestamp = 1_700_000_000n;
    const root = leafFor(user.address, score, timestamp);
    await reputationReceiver.verifySnapshotRoot(1, 1, root);

    await expect(
      reputationReceiver.receiveBridgedReputation(
        ethers.ZeroAddress,
        1,
        1,
        score,
        timestamp,
        [],
        0
      )
    ).to.be.revertedWithCustomError(reputationReceiver, "InvalidUser");

    await expect(
      reputationReceiver.receiveBridgedReputation(
        user.address,
        0,
        1,
        score,
        timestamp,
        [],
        0
      )
    ).to.be.revertedWithCustomError(
      reputationReceiver,
      "InvalidSourceChainId"
    );

    await expect(
      reputationReceiver.receiveBridgedReputation(
        user.address,
        1,
        1,
        score,
        0,
        [],
        0
      )
    ).to.be.revertedWithCustomError(reputationReceiver, "InvalidTimestamp");

    await expect(
      reputationReceiver.receiveBridgedReputation(
        user.address,
        1,
        1,
        score,
        timestamp,
        [],
        1
      )
    ).to.be.revertedWithCustomError(reputationReceiver, "InvalidProofIndex");
  });

  it("rejects oversized Merkle proofs", async function () {
    const { reputationReceiver, user } = await deployFixture();
    const oversizedProof = Array.from({ length: 65 }, (_, index) =>
      ethers.keccak256(ethers.toUtf8Bytes(`proof-${index}`))
    );

    await expect(
      reputationReceiver.receiveBridgedReputation(
        user.address,
        1,
        1,
        42,
        1_700_000_000,
        oversizedProof,
        0
      )
    ).to.be.revertedWithCustomError(reputationReceiver, "ProofTooLong");
  });

  it("accepts a valid one-leaf bridged reputation payload", async function () {
    const { reputationReceiver, user } = await deployFixture();
    const score = 42n;
    const timestamp = 1_700_000_000n;
    const root = leafFor(user.address, score, timestamp);

    await reputationReceiver.verifySnapshotRoot(1, 1, root);

    await expect(
      reputationReceiver.receiveBridgedReputation(
        user.address,
        1,
        1,
        score,
        timestamp,
        [],
        0
      )
    )
      .to.emit(reputationReceiver, "ReputationBridged")
      .withArgs(user.address, 1, score, anyValue);

    expect(await reputationReceiver.getBridgedReputation(user.address, 1)).to
      .equal(score);
  });
});
