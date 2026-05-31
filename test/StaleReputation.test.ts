import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

describe("Stale Reputation Fix - previewEffectiveStake", function () {
  let truthBounty: Contract;
  let bountyToken: Contract;
  let mockOracle: Contract;
  let submitter: Signer;
  let verifier1: Signer;
  let verifier2: Signer;

  const VERIFICATION_WINDOW = 7 * 24 * 60 * 60;
  const MAX_REPUTATION_STALENESS = 1 * 60 * 60;

  beforeEach(async function () {
    const signers = await ethers.getSigners();
    const owner = signers[0];
    [, submitter, verifier1, verifier2] = signers;

    const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
    bountyToken = await TruthBountyToken.deploy(await owner.getAddress());
    await bountyToken.waitForDeployment();

    const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
    mockOracle = await MockReputationOracle.deploy();
    await mockOracle.waitForDeployment();

    const TruthBountyWeighted = await ethers.getContractFactory("TruthBountyWeighted");
    truthBounty = await TruthBountyWeighted.deploy(
      await bountyToken.getAddress(),
      await mockOracle.getAddress(),
      await owner.getAddress(),
      await owner.getAddress()
    );
    await truthBounty.waitForDeployment();

    await bountyToken.transfer(await truthBounty.getAddress(), ethers.parseEther("100000"));
    await bountyToken.transfer(await verifier1.getAddress(), ethers.parseEther("10000"));
    await bountyToken.transfer(await verifier2.getAddress(), ethers.parseEther("10000"));
    await bountyToken.connect(verifier1).approve(await truthBounty.getAddress(), ethers.MaxUint256);
    await bountyToken.connect(verifier2).approve(await truthBounty.getAddress(), ethers.MaxUint256);
  });

  describe("previewEffectiveStakeWithTimestamp", function () {
    it("Should return timestamp with preview data", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("1000");

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      const blockTimeBefore = await time.latest();
      const [effectiveStake, reputationScore, timestamp] = await truthBounty.previewEffectiveStakeWithTimestamp(
        verifier1Addr,
        stakeAmount
      );
      const blockTimeAfter = await time.latest();

      expect(effectiveStake).to.equal(ethers.parseEther("2000"));
      expect(reputationScore).to.equal(ethers.parseEther("2.0"));
      expect(timestamp).to.be.at.least(blockTimeBefore);
      expect(timestamp).to.be.at.most(blockTimeAfter);
    });

    it("Should return different timestamps on different blocks", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("1000");

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      const [, , timestamp1] = await truthBounty.previewEffectiveStakeWithTimestamp(verifier1Addr, stakeAmount);
      await time.increase(1);
      const [, , timestamp2] = await truthBounty.previewEffectiveStakeWithTimestamp(verifier1Addr, stakeAmount);

      expect(timestamp2).to.be.greaterThan(timestamp1);
    });
  });

  describe("getLastReputationSnapshot", function () {
    it("Should return empty snapshot initially", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const snapshot = await truthBounty.getLastReputationSnapshot(verifier1Addr);

      expect(snapshot.reputationScore).to.equal(0);
      expect(snapshot.timestamp).to.equal(0);
    });

    it("Should record snapshot after vote", async function () {
      const verifier1Addr = await verifier1.getAddress();
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.5"));

      await truthBounty.connect(verifier1).voteWithValidation(0, true, ethers.parseEther("100"), 0, 0);

      const snapshot = await truthBounty.getLastReputationSnapshot(verifier1Addr);
      expect(snapshot.reputationScore).to.equal(ethers.parseEther("2.5"));
      expect(snapshot.timestamp).to.be.greaterThan(0);
    });
  });

  describe("checkReputationStaleness", function () {
    it("Should detect reputation change", async function () {
      const verifier1Addr = await verifier1.getAddress();

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");
      await truthBounty.connect(verifier1).vote(0, true, ethers.parseEther("100"));

      const [hasChanged, currentReputation, timeSincePreview] = await truthBounty.checkReputationStaleness(
        verifier1Addr,
        ethers.parseEther("2.0")
      );

      expect(hasChanged).to.be.false;
      expect(currentReputation).to.equal(ethers.parseEther("2.0"));
      expect(timeSincePreview).to.equal(0);

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("1.5"));

      const [changedAgain, currentReputationAgain] = await truthBounty.checkReputationStaleness(
        verifier1Addr,
        ethers.parseEther("2.0")
      );

      expect(changedAgain).to.be.true;
      expect(currentReputationAgain).to.equal(ethers.parseEther("1.5"));
    });

    it("Should detect staleness by time", async function () {
      const verifier1Addr = await verifier1.getAddress();

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");
      await truthBounty.connect(verifier1).vote(0, true, ethers.parseEther("100"));

      const [hasChanged] = await truthBounty.checkReputationStaleness(verifier1Addr, ethers.parseEther("2.0"));
      expect(hasChanged).to.be.false;

      await time.increase(MAX_REPUTATION_STALENESS + 1);

      const [staleNow] = await truthBounty.checkReputationStaleness(verifier1Addr, ethers.parseEther("2.0"));
      expect(staleNow).to.be.true;
    });
  });

  describe("voteWithValidation", function () {
    it("Should reject vote if reputation changed too much", async function () {
      const verifier1Addr = await verifier1.getAddress();
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("1.5"));

      await expect(
        truthBounty.connect(verifier1).voteWithValidation(0, true, ethers.parseEther("100"), ethers.parseEther("2.0"), 1000)
      ).to.be.revertedWith("Reputation changed more than allowed");
    });

    it("Should allow vote if reputation change is within tolerance", async function () {
      const verifier1Addr = await verifier1.getAddress();
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("1.9"));

      await expect(
        truthBounty.connect(verifier1).voteWithValidation(0, true, ethers.parseEther("100"), ethers.parseEther("2.0"), 1000)
      ).to.emit(truthBounty, "VoteCast");

      const vote = await truthBounty.getVote(0, verifier1Addr);
      expect(vote.effectiveStake).to.equal(ethers.parseEther("190"));
      expect(vote.reputationScore).to.equal(ethers.parseEther("1.9"));
    });

    it("Should reject vote if reputation is too stale by time", async function () {
      const verifier1Addr = await verifier1.getAddress();
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));
      await time.increase(MAX_REPUTATION_STALENESS + 1);

      await expect(
        truthBounty.connect(verifier1).voteWithValidation(0, true, ethers.parseEther("100"), ethers.parseEther("2.0"), 0)
      ).to.be.revertedWith("Reputation too stale");
    });

    it("Should skip validation if expectedReputation is 0", async function () {
      const verifier1Addr = await verifier1.getAddress();
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));
      await time.increase(MAX_REPUTATION_STALENESS + 1);

      await expect(
        truthBounty.connect(verifier1).voteWithValidation(0, true, ethers.parseEther("100"), 0, 0)
      ).to.emit(truthBounty, "VoteCast");

      const vote = await truthBounty.getVote(0, verifier1Addr);
      expect(vote.reputationScore).to.equal(ethers.parseEther("2.0"));
    });

    it("Should record reputation snapshot on vote", async function () {
      const verifier1Addr = await verifier1.getAddress();
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.5"));

      await truthBounty.connect(verifier1).voteWithValidation(0, true, ethers.parseEther("100"), 0, 0);

      const snapshot = await truthBounty.getLastReputationSnapshot(verifier1Addr);
      expect(snapshot.reputationScore).to.equal(ethers.parseEther("2.5"));
    });

    it("Should emit ReputationStalenessValidated event", async function () {
      const verifier1Addr = await verifier1.getAddress();
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      await expect(
        truthBounty.connect(verifier1).voteWithValidation(0, true, ethers.parseEther("100"), ethers.parseEther("2.0"), 1000)
      ).to.emit(truthBounty, "ReputationStalenessValidated")
        .withArgs(verifier1Addr, ethers.parseEther("2.0"), ethers.parseEther("2.0"), 1000);
    });

    it("Should emit ReputationSnapshotRecorded event", async function () {
      const verifier1Addr = await verifier1.getAddress();
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.5"));

      await expect(
        truthBounty.connect(verifier1).voteWithValidation(0, true, ethers.parseEther("100"), 0, 0)
      ).to.emit(truthBounty, "ReputationSnapshotRecorded")
        .withArgs(verifier1Addr, ethers.parseEther("2.5"), anyValue);
    });

    it("Should calculate correct drift percentage", async function () {
      const verifier1Addr = await verifier1.getAddress();
      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("1.0"));

      await expect(
        truthBounty.connect(verifier1).voteWithValidation(0, true, ethers.parseEther("100"), ethers.parseEther("1.1"), 1000)
      ).to.emit(truthBounty, "VoteCast");
    });
  });

  describe("Integration: Preview and Vote with Validation", function () {
    it("Should detect change between preview and vote using timestamps", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("1000");

      await truthBounty.connect(verifier1).stake(ethers.parseEther("5000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));
      const [previewStake, previewRep] = await truthBounty.previewEffectiveStakeWithTimestamp(verifier1Addr, stakeAmount);
      expect(previewStake).to.equal(ethers.parseEther("2000"));

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("1.5"));
      await expect(
        truthBounty.connect(verifier1).voteWithValidation(0, true, stakeAmount, previewRep, 500)
      ).to.be.revertedWith("Reputation changed more than allowed");

      await truthBounty.connect(verifier1).vote(0, true, stakeAmount);
      const vote = await truthBounty.getVote(0, verifier1Addr);
      expect(vote.effectiveStake).to.equal(ethers.parseEther("1000"));
      expect(vote.effectiveStake).to.not.equal(previewStake);
    });

    it("Should allow vote when preview was recent and reputation stable", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("1000");

      await truthBounty.connect(verifier1).stake(ethers.parseEther("5000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      const [, previewRep] = await truthBounty.previewEffectiveStakeWithTimestamp(verifier1Addr, stakeAmount);

      await expect(
        truthBounty.connect(verifier1).voteWithValidation(0, true, stakeAmount, previewRep, 100)
      ).to.emit(truthBounty, "VoteCast");

      const vote = await truthBounty.getVote(0, verifier1Addr);
      expect(vote.reputationScore).to.equal(previewRep);
      expect(vote.effectiveStake).to.equal(ethers.parseEther("2000"));
    });
  });

  describe("Backward Compatibility", function () {
    it("Should allow regular vote() without validation", async function () {
      const verifier1Addr = await verifier1.getAddress();

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      await expect(truthBounty.connect(verifier1).vote(0, true, ethers.parseEther("100"))).to.emit(truthBounty, "VoteCast");

      const vote = await truthBounty.getVote(0, verifier1Addr);
      expect(vote.reputationScore).to.equal(await truthBounty.defaultReputationScore());
    });

    it("Should not affect settlement calculations", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const verifier2Addr = await verifier2.getAddress();

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));
      await truthBounty.connect(verifier1).vote(0, true, ethers.parseEther("100"));
      await mockOracle.setReputationScore(verifier2Addr, ethers.parseEther("1.0"));
      await truthBounty.connect(verifier2).vote(0, false, ethers.parseEther("100"));

      await time.increase(VERIFICATION_WINDOW + 3601);
      await truthBounty.settleClaim(0);

      const claim = await truthBounty.getClaim(0);
      expect(claim.settled).to.be.true;
      expect(claim.totalWeightedFor).to.equal(ethers.parseEther("100"));
      expect(claim.totalWeightedAgainst).to.equal(ethers.parseEther("100"));
    });
  });
});
