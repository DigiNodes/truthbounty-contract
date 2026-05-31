import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

/**
 * @title StaleReputation Tests
 * @notice Comprehensive test suite for the stale reputation issue fix
 * @dev Tests the previewEffectiveStake and voteWithValidation functions
 */
describe("Stale Reputation Fix - previewEffectiveStake", function () {
  let truthBounty: Contract;
  let bountyToken: Contract;
  let mockOracle: Contract;
  let owner: Signer;
  let submitter: Signer;
  let verifier1: Signer;
  let verifier2: Signer;

  const VERIFICATION_WINDOW = 7 * 24 * 60 * 60; // 7 days
  const MAX_REPUTATION_STALENESS = 1 * 60 * 60; // 1 hour

  beforeEach(async function () {
    [owner, submitter, verifier1, verifier2] = await ethers.getSigners();

    // Deploy Token
    const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
    bountyToken = await TruthBountyToken.deploy(await owner.getAddress());
    await bountyToken.waitForDeployment();

    // Deploy Mock Oracle
    const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
    mockOracle = await MockReputationOracle.deploy();
    await mockOracle.waitForDeployment();

    // Deploy TruthBountyWeighted
    const TruthBountyWeighted = await ethers.getContractFactory("TruthBountyWeighted");
    truthBounty = await TruthBountyWeighted.deploy(
      await bountyToken.getAddress(),
      await mockOracle.getAddress(),
      await owner.getAddress(),
      await owner.getAddress()
    );
    await truthBounty.waitForDeployment();

    // Fund contract with tokens for rewards
    await bountyToken.transfer(await truthBounty.getAddress(), ethers.parseEther("100000"));

    // Distribute tokens to verifiers
    await bountyToken.transfer(await verifier1.getAddress(), ethers.parseEther("10000"));
    await bountyToken.transfer(await verifier2.getAddress(), ethers.parseEther("10000"));

    // Approve staking
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

      expect(effectiveStake).to.equal(ethers.parseEther("2000")); // 1000 * 2.0
      expect(reputationScore).to.equal(ethers.parseEther("2.0"));
      expect(timestamp).to.be.at.least(blockTimeBefore);
      expect(timestamp).to.be.at.most(blockTimeAfter);
    });

    it("Should return different timestamps on different blocks", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("1000");

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      const [, , timestamp1] = await truthBounty.previewEffectiveStakeWithTimestamp(
        verifier1Addr,
        stakeAmount
      );

      // Mine a new block
      await time.mine(1);

      const [, , timestamp2] = await truthBounty.previewEffectiveStakeWithTimestamp(
        verifier1Addr,
        stakeAmount
      );

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
      const reputationScore = ethers.parseEther("2.5");

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await mockOracle.setReputationScore(verifier1Addr, reputationScore);
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      const blockTimeBefore = await time.latest();
      await truthBounty.connect(verifier1).vote(0, true, ethers.parseEther("100"));
      const blockTimeAfter = await time.latest();

      const snapshot = await truthBounty.getLastReputationSnapshot(verifier1Addr);

      expect(snapshot.reputationScore).to.equal(reputationScore);
      expect(snapshot.timestamp).to.be.at.least(blockTimeBefore);
      expect(snapshot.timestamp).to.be.at.most(blockTimeAfter);
    });
  });

  describe("checkReputationStaleness", function () {
    it("Should detect reputation change", async function () {
      const verifier1Addr = await verifier1.getAddress();

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      // Vote with reputation 2.0
      await truthBounty.connect(verifier1).vote(0, true, ethers.parseEther("100"));

      // Check staleness with old reputation
      const previewReputation = ethers.parseEther("2.0");
      let [hasChanged, currentReputation, timeSincePreview] = await truthBounty.checkReputationStaleness(
        verifier1Addr,
        previewReputation
      );

      expect(hasChanged).to.be.false;
      expect(currentReputation).to.equal(previewReputation);
      expect(timeSincePreview).to.equal(0);

      // Update reputation to 1.5
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("1.5"));

      [hasChanged, currentReputation, timeSincePreview] = await truthBounty.checkReputationStaleness(
        verifier1Addr,
        previewReputation
      );

      expect(hasChanged).to.be.true;
      expect(currentReputation).to.equal(ethers.parseEther("1.5"));
    });

    it("Should detect staleness by time", async function () {
      const verifier1Addr = await verifier1.getAddress();

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      // Vote with reputation 2.0
      await truthBounty.connect(verifier1).vote(0, true, ethers.parseEther("100"));

      // Check staleness immediately
      let [hasChanged] = await truthBounty.checkReputationStaleness(
        verifier1Addr,
        ethers.parseEther("2.0")
      );
      expect(hasChanged).to.be.false;

      // Advance time beyond MAX_REPUTATION_STALENESS
      await time.increase(MAX_REPUTATION_STALENESS + 1);

      [hasChanged] = await truthBounty.checkReputationStaleness(
        verifier1Addr,
        ethers.parseEther("2.0")
      );
      expect(hasChanged).to.be.true;
    });
  });

  describe("voteWithValidation", function () {
    it("Should reject vote if reputation changed too much", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("100");

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      // Set initial reputation
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      // Reputation degrades to 1.5 (25% drop)
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("1.5"));

      // Try to vote with validation expecting 2.0, allowing only 10% drift (1000 basis points)
      await expect(
        truthBounty.connect(verifier1).voteWithValidation(
          0,
          true,
          stakeAmount,
          ethers.parseEther("2.0"), // expectedReputation
          1000 // maxReputationDrift = 10% in basis points
        )
      ).to.be.revertedWith("Reputation changed more than allowed");
    });

    it("Should allow vote if reputation change is within tolerance", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("100");

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      // Set initial reputation
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      // Reputation degrades to 1.9 (5% drop)
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("1.9"));

      // Vote with validation expecting 2.0, allowing 10% drift
      await expect(
        truthBounty.connect(verifier1).voteWithValidation(
          0,
          true,
          stakeAmount,
          ethers.parseEther("2.0"), // expectedReputation
          1000 // maxReputationDrift = 10%
        )
      ).to.emit(truthBounty, "VoteCast");

      const vote = await truthBounty.getVote(0, verifier1Addr);
      expect(vote.effectiveStake).to.equal(ethers.parseEther("190")); // 100 * 1.9
      expect(vote.reputationScore).to.equal(ethers.parseEther("1.9"));
    });

    it("Should reject vote if reputation is too stale by time", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("100");

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      // Set initial reputation
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      // Advance time beyond MAX_REPUTATION_STALENESS
      await time.increase(MAX_REPUTATION_STALENESS + 1);

      // Try to vote - should fail due to staleness
      await expect(
        truthBounty.connect(verifier1).voteWithValidation(
          0,
          true,
          stakeAmount,
          ethers.parseEther("2.0"),
          0 // No drift limit
        )
      ).to.be.revertedWith("Reputation too stale");
    });

    it("Should skip validation if expectedReputation is 0", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("100");

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      // Set initial reputation
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      // Advance time beyond MAX_REPUTATION_STALENESS
      await time.increase(MAX_REPUTATION_STALENESS + 1);

      // Vote with expectedReputation = 0 should NOT validate staleness
      await expect(
        truthBounty.connect(verifier1).voteWithValidation(
          0,
          true,
          stakeAmount,
          0, // expectedReputation = 0 skips validation
          0
        )
      ).to.emit(truthBounty, "VoteCast");

      const vote = await truthBounty.getVote(0, verifier1Addr);
      expect(vote.reputationScore).to.equal(ethers.parseEther("2.0"));
    });

    it("Should record reputation snapshot on vote", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("100");

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.5"));

      const blockTimeBefore = await time.latest();
      await truthBounty.connect(verifier1).voteWithValidation(0, true, stakeAmount, 0, 0);
      const blockTimeAfter = await time.latest();

      const snapshot = await truthBounty.getLastReputationSnapshot(verifier1Addr);

      expect(snapshot.reputationScore).to.equal(ethers.parseEther("2.5"));
      expect(snapshot.timestamp).to.be.at.least(blockTimeBefore);
      expect(snapshot.timestamp).to.be.at.most(blockTimeAfter);
    });

    it("Should emit ReputationStalenessValidated event", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("100");

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      await expect(
        truthBounty.connect(verifier1).voteWithValidation(
          0,
          true,
          stakeAmount,
          ethers.parseEther("2.0"),
          1000
        )
      ).to.emit(truthBounty, "ReputationStalenessValidated")
        .withArgs(verifier1Addr, ethers.parseEther("2.0"), ethers.parseEther("2.0"), 1000);
    });

    it("Should emit ReputationSnapshotRecorded event", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("100");

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.5"));

      await expect(
        truthBounty.connect(verifier1).voteWithValidation(0, true, stakeAmount, 0, 0)
      ).to.emit(truthBounty, "ReputationSnapshotRecorded")
        .withArgs(verifier1Addr, ethers.parseEther("2.5"));
    });

    it("Should calculate correct drift percentage", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("100");

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      // Reputation = 1.0, expected = 1.1, drift = 10%
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("1.0"));

      // Should pass with 1000 basis points (10%) tolerance
      await expect(
        truthBounty.connect(verifier1).voteWithValidation(
          0,
          true,
          stakeAmount,
          ethers.parseEther("1.1"),
          1000
        )
      ).to.emit(truthBounty, "VoteCast");
    });
  });

  describe("Integration: Preview and Vote with Validation", function () {
    it("Should detect change between preview and vote using timestamps", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("1000");

      await truthBounty.connect(verifier1).stake(ethers.parseEther("5000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      // STEP 1: Preview with reputation 2.0
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));
      const [previewStake, previewRep, previewTime] = await truthBounty.previewEffectiveStakeWithTimestamp(
        verifier1Addr,
        stakeAmount
      );

      expect(previewStake).to.equal(ethers.parseEther("2000")); // 1000 * 2.0

      // STEP 2: Oracle updates (simulating snapshot change)
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("1.5"));

      // STEP 3: Vote with strict validation
      await expect(
        truthBounty.connect(verifier1).voteWithValidation(
          0,
          true,
          stakeAmount,
          previewRep,
          500 // Max 5% drift
        )
      ).to.be.revertedWith("Reputation changed more than allowed");

      // STEP 4: Vote without validation (or loose validation)
      await truthBounty.connect(verifier1).vote(0, true, stakeAmount);

      // Verify actual stake recorded
      const vote = await truthBounty.getVote(0, verifier1Addr);
      expect(vote.effectiveStake).to.equal(ethers.parseEther("1500")); // 1000 * 1.5
      expect(vote.effectiveStake).to.not.equal(previewStake);
    });

    it("Should allow vote when preview was recent and reputation stable", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const stakeAmount = ethers.parseEther("1000");

      await truthBounty.connect(verifier1).stake(ethers.parseEther("5000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      // Set reputation
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      // Preview
      const [, previewRep] = await truthBounty.previewEffectiveStakeWithTimestamp(
        verifier1Addr,
        stakeAmount
      );

      // Vote immediately with strict validation
      await expect(
        truthBounty.connect(verifier1).voteWithValidation(
          0,
          true,
          stakeAmount,
          previewRep,
          100 // Max 1% drift
        )
      ).to.emit(truthBounty, "VoteCast");

      const vote = await truthBounty.getVote(0, verifier1Addr);
      expect(vote.reputationScore).to.equal(previewRep);
      expect(vote.effectiveStake).to.equal(ethers.parseEther("2000")); // 1000 * 2.0
    });
  });

  describe("Backward Compatibility", function () {
    it("Should allow regular vote() without validation", async function () {
      const verifier1Addr = await verifier1.getAddress();

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      // Regular vote should work without any validation
      await expect(
        truthBounty.connect(verifier1).vote(0, true, ethers.parseEther("100"))
      ).to.emit(truthBounty, "VoteCast");

      const vote = await truthBounty.getVote(0, verifier1Addr);
      expect(vote.reputationScore).to.equal(ethers.parseEther("2.0"));
    });

    it("Should not affect settlement calculations", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const verifier2Addr = await verifier2.getAddress();

      await truthBounty.connect(verifier1).stake(ethers.parseEther("1000"));
      await truthBounty.connect(verifier2).stake(ethers.parseEther("1000"));
      await truthBounty.connect(submitter).createClaim("QmTestHash");

      // Both vote with different reputations
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));
      await truthBounty.connect(verifier1).vote(0, true, ethers.parseEther("100"));

      await mockOracle.setReputationScore(verifier2Addr, ethers.parseEther("1.0"));
      await truthBounty.connect(verifier2).vote(0, false, ethers.parseEther("100"));

      // Settle claim
      await time.increase(VERIFICATION_WINDOW + 3601);
      await truthBounty.settleClaim(0);

      const claim = await truthBounty.getClaim(0);
      expect(claim.settled).to.be.true;
      expect(claim.totalWeightedFor).to.equal(ethers.parseEther("200")); // 100 * 2.0
      expect(claim.totalWeightedAgainst).to.equal(ethers.parseEther("100")); // 100 * 1.0
    });
  });
});
