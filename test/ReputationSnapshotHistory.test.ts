import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("SC-013 — Verifier Reputation Snapshot & Historical Consistency", function () {
  let truthBounty: Contract;
  let bountyToken: Contract;
  let mockOracle: Contract;
  let owner: Signer;
  let submitter: Signer;
  let verifier1: Signer;
  let verifier2: Signer;
  let verifier3: Signer;

  const VERIFICATION_WINDOW = 7 * 24 * 60 * 60; // 7 days
  const CONFIRMATION_DELAY = 1 * 60 * 60; // 1 hour
  const EPOCH_DURATION = 7 * 24 * 60 * 60; // 7 days

  beforeEach(async function () {
    [owner, submitter, verifier1, verifier2, verifier3] = await ethers.getSigners();

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
    const stakeAmount = ethers.parseEther("1000");
    await bountyToken.transfer(await verifier1.getAddress(), stakeAmount);
    await bountyToken.transfer(await verifier2.getAddress(), stakeAmount);
    await bountyToken.transfer(await verifier3.getAddress(), stakeAmount);

    // Approve & stake tokens
    await bountyToken.connect(verifier1).approve(await truthBounty.getAddress(), ethers.MaxUint256);
    await bountyToken.connect(verifier2).approve(await truthBounty.getAddress(), ethers.MaxUint256);
    await bountyToken.connect(verifier3).approve(await truthBounty.getAddress(), ethers.MaxUint256);

    await truthBounty.connect(verifier1).stake(stakeAmount);
    await truthBounty.connect(verifier2).stake(stakeAmount);
    await truthBounty.connect(verifier3).stake(stakeAmount);
  });

  describe("Snapshot Structure & Vote Capture", function () {
    it("Should capture immutable reputation snapshot fields during vote submission", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const initialRep = ethers.parseEther("2.0"); // 2.0x multiplier
      await mockOracle.setReputationScore(verifier1Addr, initialRep);

      // Move past the reputation update grace period so the updated score applies
      await time.increase(2 * 24 * 60 * 60 + 1);

      // Create a claim (claimId = 0)
      await truthBounty.connect(submitter).createClaim("IPFS_HASH_001");
      const claimId = 0;

      // Vote on claim
      const voteStake = ethers.parseEther("500");
      const tx = await truthBounty.connect(verifier1).vote(claimId, true, voteStake);
      const receipt = await tx.wait();
      const block = await ethers.provider.getBlock(receipt.blockNumber);
      const expectedTimestamp = block!.timestamp;
      const expectedEpoch = Math.floor(expectedTimestamp / EPOCH_DURATION);

      // Inspect via getHistoricalVerification
      const [reputationUsed, snapshotTimestamp, snapshotEpoch, aggregationContribution] =
        await truthBounty.getHistoricalVerification(claimId, verifier1Addr);

      expect(reputationUsed).to.equal(initialRep);
      expect(snapshotTimestamp).to.equal(expectedTimestamp);
      expect(snapshotEpoch).to.equal(expectedEpoch);
      expect(aggregationContribution).to.equal(voteStake * 2n);

      // Inspect via getVerification
      const verification = await truthBounty.getVerification(claimId, verifier1Addr);
      expect(verification.verifier).to.equal(verifier1Addr);
      expect(verification.reputationSnapshot).to.equal(initialRep);
      expect(verification.snapshotTimestamp).to.equal(expectedTimestamp);
      expect(verification.snapshotEpoch).to.equal(expectedEpoch);
      expect(verification.snapshotRoot).to.equal(ethers.ZeroHash);
      expect(verification.effectiveStake).to.equal(voteStake * 2n);
      expect(verification.stakeAmount).to.equal(voteStake);
      expect(verification.support).to.be.true;

      // Inspect via getVerificationSnapshot
      const [repSnap, snapTime, snapEpoch, snapRoot] = await truthBounty.getVerificationSnapshot(
        claimId,
        verifier1Addr
      );
      expect(repSnap).to.equal(initialRep);
      expect(snapTime).to.equal(expectedTimestamp);
      expect(snapEpoch).to.equal(expectedEpoch);
      expect(snapRoot).to.equal(ethers.ZeroHash);
    });

    it("Should revert historical queries for users who have not voted", async function () {
      await truthBounty.connect(submitter).createClaim("IPFS_HASH_002");
      const nonVoter = await verifier2.getAddress();

      await expect(
        truthBounty.getHistoricalVerification(0, nonVoter)
      ).to.be.revertedWith("No vote cast");

      await expect(
        truthBounty.getVerification(0, nonVoter)
      ).to.be.revertedWith("No vote cast");

      await expect(
        truthBounty.getVerificationSnapshot(0, nonVoter)
      ).to.be.revertedWith("No vote cast");
    });
  });

  describe("Snapshot Immutability under Oracle Reputation Changes", function () {
    it("Should maintain historical vote weight when verifier reputation changes post-vote", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const initialRep = ethers.parseEther("1.5");
      await mockOracle.setReputationScore(verifier1Addr, initialRep);

      // Move past the reputation update grace period so the updated score applies
      await time.increase(2 * 24 * 60 * 60 + 1);

      await truthBounty.connect(submitter).createClaim("IPFS_HASH_IMMUTABLE");
      const claimId = 0;
      const voteStake = ethers.parseEther("400");

      // Vote with initial 1.5x reputation -> effective stake = 600
      await truthBounty.connect(verifier1).vote(claimId, true, voteStake);

      // Verify recorded effective stake is 600
      const voteBefore = await truthBounty.getVote(claimId, verifier1Addr);
      expect(voteBefore.effectiveStake).to.equal(ethers.parseEther("600"));

      // Mutate oracle reputation post-vote to 8.0x (8e18)
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("8.0"));

      // Stored vote and verification snapshot MUST NOT change
      const voteAfter = await truthBounty.getVote(claimId, verifier1Addr);
      expect(voteAfter.effectiveStake).to.equal(ethers.parseEther("600"));
      expect(voteAfter.reputationScore).to.equal(initialRep);

      const historical = await truthBounty.getHistoricalVerification(claimId, verifier1Addr);
      expect(historical.reputationUsed).to.equal(initialRep);
      expect(historical.aggregationContribution).to.equal(ethers.parseEther("600"));
    });
  });

  describe("Deterministic Settlement & Aggregation Immunity", function () {
    it("Should settle claim outcome using snapshot values regardless of oracle mutations", async function () {
      const verifier1Addr = await verifier1.getAddress();
      const verifier2Addr = await verifier2.getAddress();

      // Verifier 1 votes FOR with 1.0x rep and 500 stake -> weighted 500
      // Verifier 2 votes AGAINST with 2.0x rep and 300 stake -> weighted 600
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("1.0"));
      await mockOracle.setReputationScore(verifier2Addr, ethers.parseEther("2.0"));

      // Move past the reputation update grace period so the updated scores apply
      await time.increase(2 * 24 * 60 * 60 + 1);

      await truthBounty.connect(submitter).createClaim("CLAIM_SETTLEMENT_TEST");
      const claimId = 0;

      await truthBounty.connect(verifier1).vote(claimId, true, ethers.parseEther("500"));
      await truthBounty.connect(verifier2).vote(claimId, false, ethers.parseEther("300"));

      const claimBefore = await truthBounty.getClaim(claimId);
      expect(claimBefore.totalWeightedFor).to.equal(ethers.parseEther("500"));
      expect(claimBefore.totalWeightedAgainst).to.equal(ethers.parseEther("600"));

      // Massive inflation attack: inflate verifier 1 reputation to 10.0x after voting
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("10.0"));

      // Fast forward past verification window + confirmation delay
      await time.increase(VERIFICATION_WINDOW + CONFIRMATION_DELAY + 1);

      // Settle claim
      await truthBounty.settleClaim(claimId);

      const claimAfter = await truthBounty.getClaim(claimId);
      expect(claimAfter.settled).to.be.true;

      // Settlement result must match snapshot aggregation (against won: 600 vs 500)
      const settlement = await truthBounty.settlementResults(claimId);
      expect(settlement.passed).to.be.false; // FOR had 500 / 1100 = ~45.4% < 60% threshold
      expect(settlement.winnerWeightedStake).to.equal(ethers.parseEther("600"));
      expect(settlement.loserWeightedStake).to.equal(ethers.parseEther("500"));
    });
  });

  describe("Multi-Epoch Snapshots & Time Traversal", function () {
    it("Should record accurate epochs across time jumps", async function () {
      const verifier1Addr = await verifier1.getAddress();
      await mockOracle.setReputationScore(verifier1Addr, ethers.parseEther("2.0"));

      // Epoch 0 vote
      await truthBounty.connect(submitter).createClaim("CLAIM_EPOCH_0");
      await truthBounty.connect(verifier1).vote(0, true, ethers.parseEther("100"));

      const verifEpoch0 = await truthBounty.getVerification(0, verifier1Addr);

      // Jump 14 days (2 full epochs)
      await time.increase(14 * 24 * 60 * 60);

      // Epoch 2 vote (creates claimId 1)
      await truthBounty.connect(submitter).createClaim("CLAIM_EPOCH_2");
      await truthBounty.connect(verifier1).vote(1, true, ethers.parseEther("100"));

      const verifEpoch2 = await truthBounty.getVerification(1, verifier1Addr);

      expect(verifEpoch2.snapshotEpoch).to.be.greaterThan(verifEpoch0.snapshotEpoch);
      expect(verifEpoch2.snapshotEpoch - verifEpoch0.snapshotEpoch).to.equal(2n);
    });
  });
});
