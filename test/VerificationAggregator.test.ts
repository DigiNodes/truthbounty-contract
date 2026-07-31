import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Signer } from "ethers";

describe("VerificationAggregator", function () {
  let aggregator: any;
  let truthBounty: any;
  let bountyToken: any;
  let mockOracle: any;
  let owner: Signer;
  let submitter: Signer;
  let v1: Signer, v2: Signer, v3: Signer, v4: Signer, v5: Signer;

  const STAKE = ethers.parseEther("100");
  const VERIFICATION_WINDOW = 7 * 24 * 60 * 60;
  const CONFIRMATION_DELAY = 1 * 60 * 60;

  async function setup() {
    [owner, submitter, v1, v2, v3, v4, v5] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("TruthBountyToken");
    bountyToken = await Token.deploy(await owner.getAddress());
    await bountyToken.waitForDeployment();

    const Oracle = await ethers.getContractFactory("MockReputationOracle");
    mockOracle = await Oracle.deploy();
    await mockOracle.waitForDeployment();

    const TBW = await ethers.getContractFactory("TruthBountyWeighted");
    truthBounty = await TBW.deploy(
      await bountyToken.getAddress(),
      await mockOracle.getAddress(),
      await owner.getAddress(),
      await owner.getAddress()
    );
    await truthBounty.waitForDeployment();

    const Aggregator = await ethers.getContractFactory(
      "contracts/VerificationAggregator.sol:VerificationAggregator"
    );
    aggregator = await Aggregator.deploy(
      await truthBounty.getAddress(),
      await owner.getAddress(),
      0, // no minimum count
      0, // no minimum weight
      0  // no minimum confidence
    );
    await aggregator.waitForDeployment();

    // Fund contract and verifiers
    await bountyToken.transfer(await truthBounty.getAddress(), ethers.parseEther("100000"));
    for (const verifier of [v1, v2, v3, v4, v5]) {
      await bountyToken.transfer(await verifier.getAddress(), ethers.parseEther("5000"));
      await bountyToken
        .connect(verifier)
        .approve(await truthBounty.getAddress(), ethers.MaxUint256);
      await truthBounty.connect(verifier).stake(ethers.parseEther("1000"));
    }
  }

  async function createClaimAndVote(
    votes: { verifier: Signer; support: boolean; stake?: bigint }[]
  ): Promise<bigint> {
    const tx = await truthBounty.connect(submitter).createClaim("QmHash");
    const receipt = await tx.wait();
    const claimId = (await truthBounty.claimCounter()) - 1n;

    for (const { verifier, support, stake } of votes) {
      await truthBounty.connect(verifier).vote(claimId, support, stake ?? STAKE);
    }

    return claimId;
  }

  // Creates a fresh EOA via account impersonation, funds it with tokens, and
  // stakes so it can vote. Returns the ready-to-vote signer.
  async function fundAndStakeVerifier(index: number): Promise<Signer> {
    const addr = ethers.getAddress("0x" + (10000 + index).toString(16).padStart(40, "0"));
    await network.provider.send("hardhat_setBalance", [
      addr,
      ethers.toBeHex(ethers.parseEther("1000")),
    ]);
    await network.provider.send("hardhat_impersonateAccount", [addr]);

    const verifier = await ethers.getSigner(addr);
    await bountyToken.transfer(addr, ethers.parseEther("5000"));
    await bountyToken.connect(verifier).approve(await truthBounty.getAddress(), ethers.MaxUint256);
    await truthBounty.connect(verifier).stake(ethers.parseEther("1000"));
    return verifier;
  }

  beforeEach(setup);

  // ============ Deployment ============

  describe("Deployment", function () {
    it("stores the verification source", async function () {
      expect(await aggregator.verificationSource()).to.equal(
        await truthBounty.getAddress()
      );
    });

    it("initialises thresholds correctly", async function () {
      expect(await aggregator.minVerificationCount()).to.equal(0);
      expect(await aggregator.minTotalWeight()).to.equal(0);
      expect(await aggregator.minConfidenceBps()).to.equal(0);
    });

    it("reverts on zero-address source", async function () {
      const Aggregator = await ethers.getContractFactory(
        "contracts/VerificationAggregator.sol:VerificationAggregator"
      );
      await expect(
        Aggregator.deploy(
          ethers.ZeroAddress,
          await owner.getAddress(),
          0, 0, 0
        )
      ).to.be.revertedWithCustomError(aggregator, "ZeroAddress");
    });

    it("reverts when confidence threshold exceeds 100%", async function () {
      const Aggregator = await ethers.getContractFactory(
        "contracts/VerificationAggregator.sol:VerificationAggregator"
      );
      await expect(
        Aggregator.deploy(
          await truthBounty.getAddress(),
          await owner.getAddress(),
          0, 0, 10_001
        )
      ).to.be.revertedWith("Confidence threshold exceeds 100%");
    });
  });

  // ============ Weight calculation ============

  describe("calculateWeights", function () {
    it("returns zeros for a claim with no votes", async function () {
      const tx = await truthBounty.connect(submitter).createClaim("QmEmpty");
      await tx.wait();
      const claimId = (await truthBounty.claimCounter()) - 1n;

      const [tw, fw, count] = await aggregator.calculateWeights(claimId);
      expect(tw).to.equal(0);
      expect(fw).to.equal(0);
      expect(count).to.equal(0);
    });

    it("correctly accumulates true and false weights", async function () {
      // v1 (1x rep) votes TRUE  → effectiveStake = 100
      // v2 (2x rep) votes FALSE → effectiveStake = 200
      await mockOracle.setReputationScore(
        await v2.getAddress(),
        ethers.parseEther("2")
      );

      const claimId = await createClaimAndVote([
        { verifier: v1, support: true },
        { verifier: v2, support: false },
      ]);

      const [tw, fw, count] = await aggregator.calculateWeights(claimId);
      expect(tw).to.equal(STAKE);            // 100e18
      expect(fw).to.equal(STAKE * 2n);       // 200e18
      expect(count).to.equal(2);
    });
  });

  // ============ Confidence calculation ============

  describe("calculateConfidence", function () {
    it("returns 10 000 for unanimous vote", async function () {
      expect(await aggregator.calculateConfidence(100, 100)).to.equal(10_000);
    });

    it("returns ~7 500 for 75/25 split", async function () {
      expect(await aggregator.calculateConfidence(75, 100)).to.equal(7_500);
    });

    it("returns ~5 100 for 51/49 split", async function () {
      expect(await aggregator.calculateConfidence(51, 100)).to.equal(5_100);
    });

    it("returns 0 when total is zero", async function () {
      expect(await aggregator.calculateConfidence(0, 0)).to.equal(0);
    });
  });

  // ============ aggregateClaim – successful cases ============

  describe("aggregateClaim – outcomes", function () {
    it("returns VERIFIED_TRUE on unanimous TRUE", async function () {
      const claimId = await createClaimAndVote([
        { verifier: v1, support: true },
        { verifier: v2, support: true },
        { verifier: v3, support: true },
      ]);

      await expect(aggregator.aggregateClaim(claimId))
        .to.emit(aggregator, "ClaimAggregated")
        .withArgs(claimId, 0 /* VERIFIED_TRUE */, 10_000);

      const result = await aggregator.getAggregation(claimId);
      expect(result.outcome).to.equal(0); // VERIFIED_TRUE
      expect(result.confidence).to.equal(10_000);
      expect(result.trueWeight).to.equal(STAKE * 3n);
      expect(result.falseWeight).to.equal(0);
      expect(result.totalWeight).to.equal(STAKE * 3n);
    });

    it("returns VERIFIED_FALSE on unanimous FALSE", async function () {
      const claimId = await createClaimAndVote([
        { verifier: v1, support: false },
        { verifier: v2, support: false },
      ]);

      await aggregator.aggregateClaim(claimId);
      const result = await aggregator.getAggregation(claimId);
      expect(result.outcome).to.equal(1); // VERIFIED_FALSE
      expect(result.confidence).to.equal(10_000);
    });

    it("returns VERIFIED_TRUE on weighted TRUE majority", async function () {
      // v1: 3x rep → effectiveStake = 300e18 TRUE
      // v2: 1x rep → effectiveStake = 100e18 FALSE
      await mockOracle.setReputationScore(
        await v1.getAddress(),
        ethers.parseEther("3")
      );

      const claimId = await createClaimAndVote([
        { verifier: v1, support: true },
        { verifier: v2, support: false },
      ]);

      await aggregator.aggregateClaim(claimId);
      const result = await aggregator.getAggregation(claimId);
      expect(result.outcome).to.equal(0); // VERIFIED_TRUE
      // confidence = 300 / 400 * 10 000 = 7 500
      expect(result.confidence).to.equal(7_500);
    });

    it("returns VERIFIED_FALSE on weighted FALSE majority", async function () {
      // v1: 1x TRUE = 100e18; v2: 3x FALSE = 300e18
      await mockOracle.setReputationScore(
        await v2.getAddress(),
        ethers.parseEther("3")
      );

      const claimId = await createClaimAndVote([
        { verifier: v1, support: true },
        { verifier: v2, support: false },
      ]);

      await aggregator.aggregateClaim(claimId);
      const result = await aggregator.getAggregation(claimId);
      expect(result.outcome).to.equal(1); // VERIFIED_FALSE
      expect(result.confidence).to.equal(7_500);
    });

    it("handles mixed verifications with correct totals", async function () {
      // v1 1x TRUE=100, v2 2x TRUE=200, v3 1x FALSE=100, v4 0.5x FALSE=50
      await mockOracle.setReputationScore(
        await v2.getAddress(),
        ethers.parseEther("2")
      );
      await mockOracle.setReputationScore(
        await v4.getAddress(),
        ethers.parseEther("0.5")
      );

      const claimId = await createClaimAndVote([
        { verifier: v1, support: true },
        { verifier: v2, support: true },
        { verifier: v3, support: false },
        { verifier: v4, support: false },
      ]);

      await aggregator.aggregateClaim(claimId);
      const result = await aggregator.getAggregation(claimId);
      // trueWeight = 300e18, falseWeight = 150e18, total = 450e18
      expect(result.trueWeight).to.equal(ethers.parseEther("300"));
      expect(result.falseWeight).to.equal(ethers.parseEther("150"));
      expect(result.totalWeight).to.equal(ethers.parseEther("450"));
      expect(result.outcome).to.equal(0); // VERIFIED_TRUE
      // confidence = 300/450 * 10 000 ≈ 6 666
      expect(result.confidence).to.equal(6_666);
    });
  });

  // ============ Tie handling ============

  describe("aggregateClaim – tie / INCONCLUSIVE", function () {
    it("returns INCONCLUSIVE on equal TRUE/FALSE weight", async function () {
      const claimId = await createClaimAndVote([
        { verifier: v1, support: true },
        { verifier: v2, support: false },
      ]);

      await aggregator.aggregateClaim(claimId);
      const result = await aggregator.getAggregation(claimId);
      expect(result.outcome).to.equal(2); // INCONCLUSIVE
      expect(result.confidence).to.equal(0);
    });

    it("returns INCONCLUSIVE when trueWeight equals falseWeight with higher stakes", async function () {
      await mockOracle.setReputationScore(
        await v1.getAddress(),
        ethers.parseEther("2")
      );
      await mockOracle.setReputationScore(
        await v2.getAddress(),
        ethers.parseEther("2")
      );

      const claimId = await createClaimAndVote([
        { verifier: v1, support: true },
        { verifier: v2, support: false },
      ]);

      await aggregator.aggregateClaim(claimId);
      const result = await aggregator.getAggregation(claimId);
      expect(result.outcome).to.equal(2); // INCONCLUSIVE
    });

    it("returns INCONCLUSIVE when no verifications are recorded", async function () {
      const tx = await truthBounty.connect(submitter).createClaim("QmNoVotes");
      await tx.wait();
      const claimId = (await truthBounty.claimCounter()) - 1n;

      await aggregator.aggregateClaim(claimId);
      const result = await aggregator.getAggregation(claimId);
      expect(result.outcome).to.equal(2); // INCONCLUSIVE
    });
  });

  // ============ Minimum participation thresholds ============

  describe("minimum participation thresholds", function () {
    beforeEach(async function () {
      await aggregator
        .connect(owner)
        .setThresholds(3, ethers.parseEther("250"), 5_000);
    });

    it("reverts when verification count is below minimum", async function () {
      const claimId = await createClaimAndVote([
        { verifier: v1, support: true },
        { verifier: v2, support: true },
      ]);

      await expect(aggregator.aggregateClaim(claimId))
        .to.be.revertedWithCustomError(aggregator, "ThresholdNotMet")
        .withArgs("Insufficient verification count");
    });

    it("reverts when total weight is below minimum", async function () {
      // 3 verifiers but tiny stakes won't accumulate 250e18
      await truthBounty.connect(owner).setMinStakeAmount(ethers.parseEther("1"));
      const tinyStake = ethers.parseEther("10");

      const claimId = await createClaimAndVote([
        { verifier: v1, support: true, stake: tinyStake },
        { verifier: v2, support: true, stake: tinyStake },
        { verifier: v3, support: true, stake: tinyStake },
      ]);

      await expect(aggregator.aggregateClaim(claimId))
        .to.be.revertedWithCustomError(aggregator, "ThresholdNotMet")
        .withArgs("Insufficient total weight");
    });

    it("reverts when confidence is below minimum", async function () {
      // v1 TRUE=100, v2 FALSE=60, v3 FALSE=60 → false_confidence = 120/220 ≈ 5 454 < 7 000
      await aggregator.connect(owner).setThresholds(3, ethers.parseEther("100"), 7_000);
      await truthBounty.connect(owner).setMinStakeAmount(ethers.parseEther("1"));

      const claimId = await createClaimAndVote([
        { verifier: v1, support: true, stake: ethers.parseEther("100") },
        { verifier: v2, support: false, stake: ethers.parseEther("60") },
        { verifier: v3, support: false, stake: ethers.parseEther("60") },
      ]);

      await expect(aggregator.aggregateClaim(claimId))
        .to.be.revertedWithCustomError(aggregator, "ThresholdNotMet")
        .withArgs("Insufficient confidence");
    });

    it("succeeds when all thresholds are met", async function () {
      // 3 votes × 100e18 = 300e18 ≥ 250e18, unanimous → confidence 10 000 ≥ 5 000
      const claimId = await createClaimAndVote([
        { verifier: v1, support: true },
        { verifier: v2, support: true },
        { verifier: v3, support: true },
      ]);

      await expect(aggregator.aggregateClaim(claimId)).to.emit(
        aggregator,
        "ClaimAggregated"
      );

      const result = await aggregator.getAggregation(claimId);
      expect(result.outcome).to.equal(0); // VERIFIED_TRUE
    });
  });

  // ============ Idempotency ============

  describe("idempotency", function () {
    it("reverts if aggregateClaim is called twice for the same claim", async function () {
      const claimId = await createClaimAndVote([
        { verifier: v1, support: true },
      ]);

      await aggregator.aggregateClaim(claimId);

      await expect(aggregator.aggregateClaim(claimId))
        .to.be.revertedWithCustomError(aggregator, "AlreadyAggregated")
        .withArgs(claimId);
    });

    it("getAggregation reverts for non-aggregated claim", async function () {
      await expect(aggregator.getAggregation(999))
        .to.be.revertedWithCustomError(aggregator, "NotAggregated")
        .withArgs(999);
    });

    it("isAggregated returns false before and true after", async function () {
      const claimId = await createClaimAndVote([
        { verifier: v1, support: true },
      ]);

      expect(await aggregator.isAggregated(claimId)).to.equal(false);
      await aggregator.aggregateClaim(claimId);
      expect(await aggregator.isAggregated(claimId)).to.equal(true);
    });
  });

  // ============ Determinism ============

  describe("determinism", function () {
    it("repeated calls to calculateWeights return identical results", async function () {
      await mockOracle.setReputationScore(
        await v1.getAddress(),
        ethers.parseEther("2")
      );

      const claimId = await createClaimAndVote([
        { verifier: v1, support: true },
        { verifier: v2, support: false },
        { verifier: v3, support: true },
      ]);

      const [tw1, fw1, c1] = await aggregator.calculateWeights(claimId);
      const [tw2, fw2, c2] = await aggregator.calculateWeights(claimId);
      expect(tw1).to.equal(tw2);
      expect(fw1).to.equal(fw2);
      expect(c1).to.equal(c2);
    });

    it("identical vote sets cast in different orders produce the same result", async function () {
      // Same multiset {TRUE, TRUE, FALSE}, all 1x reputation, but the votes
      // are cast in a different order on each claim. The aggregation must be
      // order-independent.
      const claimA = await createClaimAndVote([
        { verifier: v1, support: true },
        { verifier: v2, support: true },
        { verifier: v3, support: false },
      ]);

      const claimB = await createClaimAndVote([
        { verifier: v4, support: false },
        { verifier: v5, support: true },
        { verifier: v1, support: true },
      ]);

      const [twA, fwA, countA] = await aggregator.calculateWeights(claimA);
      const [twB, fwB, countB] = await aggregator.calculateWeights(claimB);

      expect(countA).to.equal(3);
      expect(countB).to.equal(3);
      expect(twA).to.equal(STAKE * 2n);
      expect(fwA).to.equal(STAKE);
      expect(twB).to.equal(twA);
      expect(fwB).to.equal(fwA);

      await aggregator.aggregateClaim(claimA);
      await aggregator.aggregateClaim(claimB);

      const a = await aggregator.getAggregation(claimA);
      const b = await aggregator.getAggregation(claimB);
      expect(a.outcome).to.equal(b.outcome).and.to.equal(0); // VERIFIED_TRUE
      expect(a.confidence).to.equal(b.confidence).and.to.equal(6_666); // 200/300
      expect(a.trueWeight).to.equal(b.trueWeight);
      expect(a.falseWeight).to.equal(b.falseWeight);
      expect(a.totalWeight).to.equal(b.totalWeight);
    });

    it("two claims with identical weighted votes produce identical aggregations", async function () {
      await mockOracle.setReputationScore(
        await v1.getAddress(),
        ethers.parseEther("2")
      );
      await mockOracle.setReputationScore(
        await v3.getAddress(),
        ethers.parseEther("2")
      );

      // Claim A: v1(2x TRUE) + v2(1x FALSE)
      const claimA = await createClaimAndVote([
        { verifier: v1, support: true },
        { verifier: v2, support: false },
      ]);

      // Claim B: same stake/rep config, different verifiers
      const claimB = await createClaimAndVote([
        { verifier: v3, support: true },
        { verifier: v4, support: false },
      ]);

      await aggregator.aggregateClaim(claimA);
      await aggregator.aggregateClaim(claimB);

      const a = await aggregator.getAggregation(claimA);
      const b = await aggregator.getAggregation(claimB);
      expect(a.outcome).to.equal(b.outcome);
      expect(a.confidence).to.equal(b.confidence);
    });
  });

  // ============ Stress test ============

  describe("stress test", function () {
    it("aggregates 100 verifications deterministically", async function () {
      // 60 TRUE / 40 FALSE at 1x reputation → expected confidence 6 000
      const verifiers: Signer[] = [];
      for (let i = 0; i < 100; i++) {
        verifiers.push(await fundAndStakeVerifier(i));
      }

      const tx = await truthBounty.connect(submitter).createClaim("QmStress");
      await tx.wait();
      const claimId = (await truthBounty.claimCounter()) - 1n;

      for (let i = 0; i < verifiers.length; i++) {
        await truthBounty
          .connect(verifiers[i])
          .vote(claimId, i < 60, STAKE);
      }

      const [tw, fw, count] = await aggregator.calculateWeights(claimId);
      expect(count).to.equal(100);
      expect(tw).to.equal(STAKE * 60n);
      expect(fw).to.equal(STAKE * 40n);

      await aggregator.aggregateClaim(claimId);
      const result = await aggregator.getAggregation(claimId);
      expect(result.outcome).to.equal(0); // VERIFIED_TRUE
      expect(result.confidence).to.equal(6_000);
      expect(result.totalWeight).to.equal(STAKE * 100n);

      // Repeated view on the same stored result is stable.
      const again = await aggregator.getAggregation(claimId);
      expect(again.confidence).to.equal(result.confidence);
      expect(again.outcome).to.equal(result.outcome);
    });

    it("resolves a 100-verification tie to INCONCLUSIVE", async function () {
      const verifiers: Signer[] = [];
      for (let i = 0; i < 100; i++) {
        verifiers.push(await fundAndStakeVerifier(100 + i));
      }

      const tx = await truthBounty.connect(submitter).createClaim("QmTie");
      await tx.wait();
      const claimId = (await truthBounty.claimCounter()) - 1n;

      for (let i = 0; i < verifiers.length; i++) {
        await truthBounty
          .connect(verifiers[i])
          .vote(claimId, i % 2 === 0, STAKE);
      }

      await aggregator.aggregateClaim(claimId);
      const result = await aggregator.getAggregation(claimId);
      expect(result.outcome).to.equal(2); // INCONCLUSIVE
      expect(result.confidence).to.equal(0);
      expect(result.trueWeight).to.equal(STAKE * 50n);
      expect(result.falseWeight).to.equal(STAKE * 50n);
    });
  });

  // ============ Gas benchmarks ============
  //
  // Measured on hardhat network (solc 0.8.28, optimizer runs 200):
  //   10 verifications:
  //     calculateWeights   ≈ 122 000 gas
  //     aggregateClaim     ≈ 225 000 gas
  //   100 verifications:
  //     calculateWeights   ≈ 961 000 gas
  //     aggregateClaim     ≈ 1 063 000 gas
  //   getAggregation       ≈ 35 000 gas (view, constant regardless of size)
  //   calculateConfidence  ≈ sub-1 000 gas (pure)
  // Cost scales linearly with the number of verifications (~9.3k gas/vote).
  // Re-run with: npx hardhat test test/VerificationAggregator.test.ts --grep "gas benchmark"

  describe("gas benchmarks", function () {
    it("records gas usage for 10 and 100 verifications", async function () {
      async function benchmark(count: number, offset: number) {
        const verifiers: Signer[] = [];
        for (let i = 0; i < count; i++) {
          verifiers.push(await fundAndStakeVerifier(offset + i));
        }

        const tx = await truthBounty.connect(submitter).createClaim("QmGas");
        await tx.wait();
        const claimId = (await truthBounty.claimCounter()) - 1n;

        for (const verifier of verifiers) {
          await truthBounty.connect(verifier).vote(claimId, true, STAKE);
        }

        const weightsGas = await aggregator.calculateWeights.estimateGas(claimId);
        const aggregateGas = await aggregator.aggregateClaim.estimateGas(claimId);
        const receipt = await (await aggregator.aggregateClaim(claimId)).wait();
        const getGas = await aggregator.getAggregation.estimateGas(claimId);

        console.log(`  [${count} verifications]`);
        console.log(`    calculateWeights: ${weightsGas} gas`);
        console.log(`    aggregateClaim:   ${receipt!.gasUsed} gas (est. ${aggregateGas})`);
        console.log(`    getAggregation:   ${getGas} gas`);
      }

      await benchmark(10, 1000);
      await benchmark(100, 2000);

      const confGas = await aggregator.calculateConfidence.estimateGas(7500, 10000);
      console.log(`  [pure view]`);
      console.log(`    calculateConfidence: ${confGas} gas`);
    });
  });

  // ============ Admin ============

  describe("admin", function () {
    it("setThresholds emits ThresholdsUpdated", async function () {
      await expect(aggregator.connect(owner).setThresholds(5, 1000, 6000))
        .to.emit(aggregator, "ThresholdsUpdated")
        .withArgs(5, 1000, 6000);
    });

    it("setThresholds reverts if confidence exceeds 10 000", async function () {
      await expect(
        aggregator.connect(owner).setThresholds(0, 0, 10_001)
      ).to.be.revertedWith("Confidence threshold exceeds 100%");
    });

    it("setVerificationSource updates the address and emits event", async function () {
      const newAddr = await v1.getAddress();
      await expect(aggregator.connect(owner).setVerificationSource(newAddr))
        .to.emit(aggregator, "VerificationSourceUpdated")
        .withArgs(await truthBounty.getAddress(), newAddr);

      expect(await aggregator.verificationSource()).to.equal(newAddr);
    });

    it("setVerificationSource reverts on zero address", async function () {
      await expect(
        aggregator.connect(owner).setVerificationSource(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(aggregator, "ZeroAddress");
    });

    it("non-admin cannot call setThresholds", async function () {
      await expect(
        aggregator.connect(v1).setThresholds(0, 0, 0)
      ).to.be.reverted;
    });
  });
});
