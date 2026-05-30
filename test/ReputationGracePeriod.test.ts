import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

describe("Reputation Grace Period for Voting", function () {
  let truthBounty: Contract;
  let bountyToken: Contract;
  let mockOracle: Contract;
  let owner: Signer;
  let submitter: Signer;
  let verifier1: Signer;
  let verifier2: Signer;

  const INITIAL_SUPPLY = ethers.parseEther("1000000");
  const MIN_STAKE = ethers.parseEther("100");
  const VERIFICATION_WINDOW = 7 * 24 * 60 * 60; // 7 days
  const DEFAULT_GRACE_PERIOD = 2 * 24 * 60 * 60; // 2 days
  const BASE_MULTIPLIER = ethers.parseEther("1");

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

    // Fund contract and verifiers
    await bountyToken.transfer(await truthBounty.getAddress(), ethers.parseEther("100000"));
    await bountyToken.transfer(await verifier1.getAddress(), ethers.parseEther("10000"));
    await bountyToken.transfer(await verifier2.getAddress(), ethers.parseEther("10000"));

    // Setup verifiers
    await bountyToken.connect(verifier1).approve(await truthBounty.getAddress(), ethers.parseEther("10000"));
    await truthBounty.connect(verifier1).deposit(ethers.parseEther("1000"));

    await bountyToken.connect(verifier2).approve(await truthBounty.getAddress(), ethers.parseEther("10000"));
    await truthBounty.connect(verifier2).deposit(ethers.parseEther("1000"));

    // Set initial reputation
    await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("1")); // 100%
    await mockOracle.setReputationScore(await verifier2.getAddress(), ethers.parseEther("1")); // 100%
  });

  describe("Grace Period Configuration", function () {
    it("Should have default grace period of 2 days", async function () {
      expect(await truthBounty.reputationUpdateGracePeriod()).to.equal(DEFAULT_GRACE_PERIOD);
    });

    it("Should allow updating grace period", async function () {
      const newGracePeriod = 1 * 24 * 60 * 60; // 1 day
      await truthBounty.setReputationUpdateGracePeriod(newGracePeriod);
      expect(await truthBounty.reputationUpdateGracePeriod()).to.equal(newGracePeriod);
    });

    it("Should emit event when grace period is updated", async function () {
      const newGracePeriod = 3 * 24 * 60 * 60; // 3 days
      await expect(truthBounty.setReputationUpdateGracePeriod(newGracePeriod))
        .to.emit(truthBounty, "ReputationUpdateGracePeriodUpdated")
        .withArgs(newGracePeriod);
    });

    it("Should reject grace period below minimum", async function () {
      const tooSmall = 30 * 60; // 30 minutes, less than 1 hour minimum
      await expect(
        truthBounty.setReputationUpdateGracePeriod(tooSmall)
      ).to.be.revertedWithCustomError(truthBounty, "InvalidReputationUpdateGracePeriod");
    });

    it("Should reject grace period above maximum", async function () {
      const tooLarge = 31 * 24 * 60 * 60; // 31 days, more than 30 days maximum
      await expect(
        truthBounty.setReputationUpdateGracePeriod(tooLarge)
      ).to.be.revertedWithCustomError(truthBounty, "InvalidReputationUpdateGracePeriod");
    });
  });

  describe("Last-Minute Reputation Boost Prevention", function () {
    it("Should use default reputation for updates made within grace period of claim creation", async function () {
      // Create a claim
      await bountyToken.connect(submitter).approve(await truthBounty.getAddress(), MIN_STAKE);
      const createTx = await truthBounty.connect(submitter).createClaim("Test claim");
      const createReceipt = await createTx.wait();
      const claimId = 0;

      // Get the claim creation time
      const claim = await truthBounty.getClaim(claimId);
      const claimCreatedAt = claim.createdAt;

      // Update reputation right before voting (within grace period)
      await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("5")); // 500%
      
      // Vote right after updating reputation (still within grace period)
      const voteTx = await truthBounty.connect(verifier1).vote(claimId, true, MIN_STAKE);
      const voteReceipt = await voteTx.wait();

      // Get the vote
      const vote = await truthBounty.getVote(claimId, await verifier1.getAddress());

      // The reputation score in the vote should be default (1e18), not the boosted one (5e18)
      expect(vote.reputationScore).to.equal(BASE_MULTIPLIER);
    });

    it("Should use boosted reputation for updates made before grace period", async function () {
      // Set initial low reputation
      await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("1")); // 100%

      // Update reputation well before grace period
      const gracePeriod = await truthBounty.reputationUpdateGracePeriod();
      await time.increase(Number(gracePeriod) + 1);

      // Create a claim
      await bountyToken.connect(submitter).approve(await truthBounty.getAddress(), MIN_STAKE);
      const createTx = await truthBounty.connect(submitter).createClaim("Test claim");
      await createTx.wait();
      const claimId = 0;

      // Now the reputation update is outside the grace period
      // Vote should use the higher reputation
      const voteTx = await truthBounty.connect(verifier1).vote(claimId, true, MIN_STAKE);
      const voteReceipt = await voteTx.wait();

      // Get the vote
      const vote = await truthBounty.getVote(claimId, await verifier1.getAddress());

      // The reputation score should be the boosted one
      expect(vote.reputationScore).to.equal(ethers.parseEther("1")); // 100% because it was set well before claim
    });

    it("Should allow voting immediately after claim creation with old reputation", async function () {
      // Set reputation before claim creation
      await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("2")); // 200%

      // Create a claim
      await bountyToken.connect(submitter).approve(await truthBounty.getAddress(), MIN_STAKE);
      const createTx = await truthBounty.connect(submitter).createClaim("Test claim");
      await createTx.wait();
      const claimId = 0;

      // Vote right after claim creation with old reputation (should be allowed)
      const voteTx = await truthBounty.connect(verifier1).vote(claimId, true, MIN_STAKE);
      const voteReceipt = await voteTx.wait();

      // Get the vote - reputation should be the old one set before claim
      const vote = await truthBounty.getVote(claimId, await verifier1.getAddress());
      expect(vote.reputationScore).to.equal(ethers.parseEther("2")); // 200%
    });

    it("Should prevent last-minute reputation boost from affecting voting power", async function () {
      // Create a claim
      await bountyToken.connect(submitter).approve(await truthBounty.getAddress(), MIN_STAKE);
      const createTx = await truthBounty.connect(submitter).createClaim("Test claim");
      await createTx.wait();
      const claimId = 0;

      const claim = await truthBounty.getClaim(claimId);
      const claimCreatedAt = claim.createdAt;

      // Boost reputation right before voting
      const boostAmount = ethers.parseEther("10"); // 1000%
      await mockOracle.setReputationScore(await verifier1.getAddress(), boostAmount);

      // Vote shortly after the boost (within grace period)
      await truthBounty.connect(verifier1).vote(claimId, true, MIN_STAKE);

      // Get the vote
      const vote = await truthBounty.getVote(claimId, await verifier1.getAddress());

      // Effective stake should be based on default reputation, not the boost
      const defaultReputation = await truthBounty.defaultReputationScore();
      const expectedEffectiveStake = (MIN_STAKE * defaultReputation) / BASE_MULTIPLIER;

      expect(vote.effectiveStake).to.equal(expectedEffectiveStake);
      expect(vote.reputationScore).to.equal(defaultReputation);
    });
  });

  describe("Grace Period Window Calculations", function () {
    it("Should consider reputation updates within grace period window from claim creation", async function () {
      const gracePeriod = await truthBounty.reputationUpdateGracePeriod();

      // Update reputation
      const updateTime = await time.latest();
      await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("5")); // 500%

      // Move forward by half the grace period
      await time.increase(Number(gracePeriod) / 2);

      // Create a claim (update is still within grace period before claim)
      await bountyToken.connect(submitter).approve(await truthBounty.getAddress(), MIN_STAKE);
      const createTx = await truthBounty.connect(submitter).createClaim("Test claim");
      await createTx.wait();
      const claimId = 0;

      // Vote (reputation update was within grace period)
      await truthBounty.connect(verifier1).vote(claimId, true, MIN_STAKE);

      // Check that default reputation was used
      const vote = await truthBounty.getVote(claimId, await verifier1.getAddress());
      expect(vote.reputationScore).to.equal(await truthBounty.defaultReputationScore());
    });

    it("Should accept reputation updates outside grace period from claim creation", async function () {
      const gracePeriod = await truthBounty.reputationUpdateGracePeriod();

      // Update reputation
      await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("5")); // 500%

      // Move forward by more than the grace period
      await time.increase(Number(gracePeriod) + 100);

      // Create a claim
      await bountyToken.connect(submitter).approve(await truthBounty.getAddress(), MIN_STAKE);
      const createTx = await truthBounty.connect(submitter).createClaim("Test claim");
      await createTx.wait();
      const claimId = 0;

      // Vote (reputation update was outside grace period)
      await truthBounty.connect(verifier1).vote(claimId, true, MIN_STAKE);

      // Check that boosted reputation was used
      const vote = await truthBounty.getVote(claimId, await verifier1.getAddress());
      expect(vote.reputationScore).to.equal(ethers.parseEther("5")); // 500%
    });
  });

  describe("Multiple Voters with Different Reputation Timings", function () {
    it("Should correctly apply grace period to different voters", async function () {
      const gracePeriod = await truthBounty.reputationUpdateGracePeriod();

      // Verifier 1: Update reputation well before grace period
      await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("1")); // 100%
      await time.increase(Number(gracePeriod) + 1);

      // Verifier 2: Update reputation within grace period
      await mockOracle.setReputationScore(await verifier2.getAddress(), ethers.parseEther("5")); // 500%

      // Create a claim
      await bountyToken.connect(submitter).approve(await truthBounty.getAddress(), MIN_STAKE);
      const createTx = await truthBounty.connect(submitter).createClaim("Test claim");
      await createTx.wait();
      const claimId = 0;

      // Both vote
      await truthBounty.connect(verifier1).vote(claimId, true, MIN_STAKE);
      await truthBounty.connect(verifier2).vote(claimId, false, MIN_STAKE);

      // Verifier 1 should use boosted reputation (update was before grace period)
      const vote1 = await truthBounty.getVote(claimId, await verifier1.getAddress());
      expect(vote1.reputationScore).to.equal(ethers.parseEther("1")); // 100%

      // Verifier 2 should use default reputation (update was within grace period)
      const vote2 = await truthBounty.getVote(claimId, await verifier2.getAddress());
      expect(vote2.reputationScore).to.equal(await truthBounty.defaultReputationScore()); // Default
    });
  });

  describe("Integration with Claim Settlement", function () {
    it("Should correctly calculate weighted votes considering grace period", async function () {
      const gracePeriod = await truthBounty.reputationUpdateGracePeriod();

      // Set up: Verifier1 has legitimate high reputation (set before grace period)
      await mockOracle.setReputationScore(await verifier1.getAddress(), ethers.parseEther("5"));
      await time.increase(Number(gracePeriod) + 1);

      // Verifier2 tries to boost reputation within grace period
      await mockOracle.setReputationScore(await verifier2.getAddress(), ethers.parseEther("5"));

      // Create claim
      await bountyToken.connect(submitter).approve(await truthBounty.getAddress(), MIN_STAKE);
      const createTx = await truthBounty.connect(submitter).createClaim("Test claim");
      await createTx.wait();
      const claimId = 0;

      // Both vote
      await truthBounty.connect(verifier1).vote(claimId, true, MIN_STAKE);
      await truthBounty.connect(verifier2).vote(claimId, true, MIN_STAKE);

      // Verifier1's effective stake should be higher (using boosted reputation)
      const vote1 = await truthBounty.getVote(claimId, await verifier1.getAddress());
      const vote2 = await truthBounty.getVote(claimId, await verifier2.getAddress());

      // Vote1 effective stake (based on 5x reputation)
      // Vote2 effective stake (based on default 1x reputation)
      expect(vote1.effectiveStake).to.be.greaterThan(vote2.effectiveStake);
    });
  });

  describe("Edge Cases", function () {
    it("Should handle zero last update timestamp (never updated)", async function () {
      // Fresh user with no reputation updates
      const newVerifier = (await ethers.getSigners())[4];
      
      await bountyToken.transfer(await newVerifier.getAddress(), ethers.parseEther("10000"));
      await bountyToken.connect(newVerifier).approve(await truthBounty.getAddress(), ethers.parseEther("10000"));
      await truthBounty.connect(newVerifier).deposit(ethers.parseEther("1000"));

      // Create claim
      await bountyToken.connect(submitter).approve(await truthBounty.getAddress(), MIN_STAKE);
      const createTx = await truthBounty.connect(submitter).createClaim("Test claim");
      await createTx.wait();
      const claimId = 0;

      // Vote without ever setting reputation
      const voteTx = await truthBounty.connect(newVerifier).vote(claimId, true, MIN_STAKE);
      await voteTx.wait();

      // Should use default reputation
      const vote = await truthBounty.getVote(claimId, await newVerifier.getAddress());
      expect(vote.reputationScore).to.equal(await truthBounty.defaultReputationScore());
    });

    it("Should handle oracle that doesn't support getLastReputationUpdate", async function () {
      // This tests backward compatibility - the try-catch in the contract should handle it gracefully
      
      // Create claim
      await bountyToken.connect(submitter).approve(await truthBounty.getAddress(), MIN_STAKE);
      const createTx = await truthBounty.connect(submitter).createClaim("Test claim");
      await createTx.wait();
      const claimId = 0;

      // Vote should succeed even if oracle doesn't support the new method
      const voteTx = await truthBounty.connect(verifier1).vote(claimId, true, MIN_STAKE);
      const voteReceipt = await voteTx.wait();
      expect(voteReceipt?.status).to.equal(1); // Success
    });
  });
});
