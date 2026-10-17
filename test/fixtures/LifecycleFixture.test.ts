import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { deployLifecycleFixture, LifecycleEnvironment } from "./lifecycleFixture";

describe("Deterministic Local End-to-End Lifecycle Fixture (SC-035)", () => {
  let env: LifecycleEnvironment;

  beforeEach(async () => {
    env = await deployLifecycleFixture();
  });

  describe("Journey 1: Undisputed True Claim", () => {
    it("executes complete lifecycle from creation to undisputed True provisional settlement", async () => {
      const { accounts, contracts, helpers, constants } = env;

      // 1. Create Claim
      const { claimId } = await helpers.createClaim("Decentralized claim statement 123");
      const claim = await contracts.claimRegistry.getClaim(claimId);
      expect(claim.creator).to.equal(accounts.claimCreator.address);
      expect(claim.status).to.equal(0); // Pending (initial state upon creation)

      // 2. Verifiers Vote TRUE
      await helpers.stakeAndVote(
        claimId,
        accounts.verifier1,
        true,
        constants.MIN_STAKE,
        ethers.parseEther("1.0")
      );
      await helpers.stakeAndVote(
        claimId,
        accounts.verifier2,
        true,
        constants.MIN_STAKE,
        ethers.parseEther("1.2")
      );

      // 3. Fast-forward past verification window and execute provisional settlement
      await helpers.executeProvisionalSettlement(claimId);

      const outcome = await contracts.settlementEngine.getProvisionalOutcome(claimId);
      expect(outcome.settled).to.be.true;
      expect(outcome.outcome).to.equal(1); // VERIFIED_TRUE
      expect(outcome.trueWeight).to.be.gt(0);
      expect(outcome.falseWeight).to.equal(0);
      expect(await contracts.settlementEngine.isChallengeWindowOpen(claimId)).to.be.true;

      // 4. Fast-forward past challenge window with zero disputes
      await time.increase(constants.CHALLENGE_WINDOW + 10);
      expect(await contracts.settlementEngine.isChallengeWindowOpen(claimId)).to.be.false;
    });
  });

  describe("Journey 2: Undisputed False Claim", () => {
    it("executes complete lifecycle for undisputed False consensus", async () => {
      const { accounts, contracts, helpers, constants } = env;

      const { claimId } = await helpers.createClaim("False Claim Statement 456");

      // Verifier votes FALSE
      await helpers.stakeAndVote(
        claimId,
        accounts.verifier1,
        false,
        constants.MIN_STAKE,
        ethers.parseEther("1.0")
      );

      await helpers.executeProvisionalSettlement(claimId);

      const outcome = await contracts.settlementEngine.getProvisionalOutcome(claimId);
      expect(outcome.outcome).to.equal(2); // VERIFIED_FALSE
      expect(outcome.falseWeight).to.be.gt(0);
      expect(outcome.trueWeight).to.equal(0);
    });
  });

  describe("Journey 3: Inconclusive Consensus", () => {
    it("handles zero votes / ties gracefully as INCONCLUSIVE", async () => {
      const { contracts, helpers } = env;

      const { claimId } = await helpers.createClaim("Unverified Tied Statement 789");

      // Zero votes cast, execute settlement
      await helpers.executeProvisionalSettlement(claimId);

      const outcome = await contracts.settlementEngine.getProvisionalOutcome(claimId);
      expect(outcome.outcome).to.equal(3); // INCONCLUSIVE
      expect(outcome.totalWeight).to.equal(0);
    });
  });

  describe("Journey 4: Successful Challenge & Appeal Overturn (False -> True)", () => {
    it("overturns provisional False outcome via second-round Appeal verification", async () => {
      const { accounts, contracts, helpers, constants } = env;

      // 1. Create claim
      const { claimId } = await helpers.createClaim("Disputed Claim Statement 101");

      // 2. First-round voters vote FALSE (100 stake, rep 1.0)
      await helpers.stakeAndVote(
        claimId,
        accounts.verifier1,
        false,
        constants.MIN_STAKE,
        ethers.parseEther("1.0")
      );

      // 3. Provisional settlement results in FALSE
      await helpers.executeProvisionalSettlement(claimId);
      let outcome = await contracts.settlementEngine.getProvisionalOutcome(claimId);
      expect(outcome.outcome).to.equal(2); // VERIFIED_FALSE

      // 4. Challenger opens Appeal Round during challenge window
      await helpers.openAppeal(claimId);
      const appealRoundData = await contracts.appealRound.getAppealRound(claimId);
      expect(appealRoundData.status).to.equal(1); // OPEN

      // 5. Appellants stake heavily and vote TRUE (200 stake each with 1.5x appeal multiplier)
      await helpers.voteAppeal(
        claimId,
        accounts.appellant1,
        true,
        constants.MIN_APPEAL_STAKE,
        ethers.parseEther("1.0")
      );
      await helpers.voteAppeal(
        claimId,
        accounts.appellant2,
        true,
        constants.MIN_APPEAL_STAKE,
        ethers.parseEther("1.2")
      );

      // 6. Fast-forward past appeal window and aggregate
      const finalAppealResult = await helpers.closeAndAggregateAppeal(claimId);

      // 7. Verification Aggregator confirms appeal outcome overturned to TRUE
      expect(finalAppealResult.outcome).to.equal(0); // VERIFIED_TRUE in VerificationAggregator enum
      expect(finalAppealResult.trueWeight).to.be.gt(finalAppealResult.falseWeight);
    });
  });

  describe("Journey 5: Failed Challenge & Appeal Affirmation (True -> True)", () => {
    it("affirms provisional True outcome when appeal votes also support True", async () => {
      const { accounts, helpers, constants } = env;

      const { claimId } = await helpers.createClaim("Affirmed Claim Statement 202");

      // First round: TRUE
      await helpers.stakeAndVote(claimId, accounts.verifier1, true, constants.MIN_STAKE);
      await helpers.executeProvisionalSettlement(claimId);

      // Appeal round opened
      await helpers.openAppeal(claimId);

      // Appeal voters confirm TRUE
      await helpers.voteAppeal(claimId, accounts.appellant1, true, constants.MIN_APPEAL_STAKE);

      const finalAppealResult = await helpers.closeAndAggregateAppeal(claimId);
      expect(finalAppealResult.outcome).to.equal(0); // VERIFIED_TRUE
    });
  });

  describe("Isolation & Balance Reconciliation", () => {
    it("maintains strict isolation between fixture instances", async () => {
      const env2 = await deployLifecycleFixture();
      expect(await env2.contracts.claimRegistry.getAddress()).to.not.equal(
        await env.contracts.claimRegistry.getAddress()
      );
    });

    it("accurately tracks and custodies verifier stakes in contracts", async () => {
      const { accounts, contracts, helpers, constants } = env;
      const { claimId } = await helpers.createClaim("Accounting Reconciliation Claim 303");

      const balanceBefore = await contracts.token.balanceOf(accounts.appellant1.address);
      await helpers.openAppeal(claimId);
      await helpers.voteAppeal(claimId, accounts.appellant1, true, constants.MIN_APPEAL_STAKE);

      const balanceAfter = await contracts.token.balanceOf(accounts.appellant1.address);
      expect(balanceBefore - balanceAfter).to.equal(constants.MIN_APPEAL_STAKE);

      const contractVaultBalance = await contracts.token.balanceOf(
        await contracts.appealRound.getAddress()
      );
      expect(contractVaultBalance).to.equal(constants.MIN_APPEAL_STAKE);
    });
  });
});
