import { expect } from "chai";
import { ethers } from "hardhat";

interface ProjectedClaim {
  id: bigint;
  creator: string;
  metadataHash: string;
  status: number;
  resolved: boolean;
  outcome?: boolean;
  finalized: boolean;
}

interface ProjectedEvidence {
  claimId: bigint;
  evidenceId: bigint;
  submitter: string;
  evidenceHash: string;
  revoked: boolean;
}

interface ProjectedVerifierState {
  totalStaked: bigint;
  activeStaked: bigint;
  slashed: bigint;
  rewardsClaimed: bigint;
}

interface ProjectedTreasury {
  accounts: Record<number, bigint>;
  totalAssets: bigint;
}

class ProtocolStateProjection {
  public claims = new Map<bigint, ProjectedClaim>();
  public evidence = new Map<bigint, ProjectedEvidence[]>();
  public verifiers = new Map<string, ProjectedVerifierState>();
  public votes = new Map<string, { support: boolean; stake: bigint }>();
  public rewardsEscrowed = new Map<string, bigint>();
  public treasury: ProjectedTreasury = { accounts: {}, totalAssets: 0n };
  public parameters = new Map<string, { version: bigint; value: bigint }>();

  private getVerifier(addr: string): ProjectedVerifierState {
    const key = addr.toLowerCase();
    if (!this.verifiers.has(key)) {
      this.verifiers.set(key, {
        totalStaked: 0n,
        activeStaked: 0n,
        slashed: 0n,
        rewardsClaimed: 0n,
      });
    }
    return this.verifiers.get(key)!;
  }

  public applyLog(eventName: string, args: any) {
    switch (eventName) {
      case "ClaimCreatedV1": {
        this.claims.set(args.claimId, {
          id: args.claimId,
          creator: args.actor,
          metadataHash: args.metadataHash,
          status: 0,
          resolved: false,
          finalized: false,
        });
        break;
      }

      case "ClaimStatusTransitionedV1": {
        const claim = this.claims.get(args.claimId);
        if (claim) {
          claim.status = Number(args.newStatus);
        }
        break;
      }

      case "ClaimResolvedV1": {
        const claim = this.claims.get(args.claimId);
        if (claim) {
          claim.resolved = true;
          claim.outcome = args.outcome;
        }
        break;
      }

      case "ClaimFinalizedV1": {
        const claim = this.claims.get(args.claimId);
        if (claim) {
          claim.finalized = true;
        }
        break;
      }

      case "EvidenceSubmittedV1": {
        const list = this.evidence.get(args.claimId) || [];
        list.push({
          claimId: args.claimId,
          evidenceId: args.evidenceId,
          submitter: args.submitter,
          evidenceHash: args.evidenceHash,
          revoked: false,
        });
        this.evidence.set(args.claimId, list);
        break;
      }

      case "EvidenceRevokedV1": {
        const list = this.evidence.get(args.claimId) || [];
        const item = list.find((e) => e.evidenceId === args.evidenceId);
        if (item) {
          item.revoked = true;
        }
        break;
      }

      case "StakeDepositedV1": {
        const v = this.getVerifier(args.verifier);
        v.totalStaked = args.newBalance;
        break;
      }

      case "StakeLockedV1": {
        const v = this.getVerifier(args.verifier);
        v.activeStaked = args.resultingActiveStake;
        break;
      }

      case "StakeUnlockedV1": {
        const v = this.getVerifier(args.verifier);
        v.activeStaked = args.resultingActiveStake;
        break;
      }

      case "StakeWithdrawnV1": {
        const v = this.getVerifier(args.verifier);
        v.totalStaked = args.newBalance;
        break;
      }

      case "VerificationSubmittedV1": {
        const key = `${args.claimId}-${args.verifier.toLowerCase()}`;
        this.votes.set(key, {
          support: args.support,
          stake: args.stakeAmount,
        });
        break;
      }

      case "SlashExecutedV1": {
        const v = this.getVerifier(args.verifier);
        v.slashed += args.amount;
        break;
      }

      case "RewardEscrowedV1": {
        const key = args.recipient.toLowerCase();
        const cur = this.rewardsEscrowed.get(key) || 0n;
        this.rewardsEscrowed.set(key, cur + args.amount);
        break;
      }

      case "RewardClaimedV1": {
        const v = this.getVerifier(args.recipient);
        v.rewardsClaimed += args.amount;
        const cur = this.rewardsEscrowed.get(args.recipient.toLowerCase()) || 0n;
        this.rewardsEscrowed.set(args.recipient.toLowerCase(), cur - args.amount);
        break;
      }

      case "TreasuryDepositV1": {
        const acc = Number(args.account);
        const cur = this.treasury.accounts[acc] || 0n;
        this.treasury.accounts[acc] = cur + args.amount;
        this.treasury.totalAssets += args.amount;
        break;
      }

      case "TreasuryTransferV1": {
        // Accounting value transfer
        break;
      }

      case "ParameterUpdatedV1": {
        this.parameters.set(args.paramName, {
          version: args.parameterVersion,
          value: args.newValue,
        });
        break;
      }
    }
  }
}

describe("State Replay Projection Fixture (From Logs Only)", function () {
  it("fully reconstructs a complete claim lifecycle and financial balances from logs", async function () {
    const [admin, creator, verifier1, verifier2, challenger] = await ethers.getSigners();
    const factory = await ethers.getContractFactory("EventArchitectureHarness");
    const harness = await factory.deploy();
    await harness.waitForDeployment();

    const projection = new ProtocolStateProjection();
    const claimId = 42n;
    const metadataHash = ethers.keccak256(ethers.toUtf8Bytes("claim-42-content"));
    const evidenceHash = ethers.keccak256(ethers.toUtf8Bytes("evidence-ipfs-cid-v2"));
    const reasonSlash = ethers.keccak256(ethers.toUtf8Bytes("LOSING_VOTE"));
    const paramMinStake = ethers.keccak256(ethers.toUtf8Bytes("MIN_STAKE"));

    // 1. Governance parameter update
    let tx = await harness.emitParameterUpdatedV1(paramMinStake, 1n, 100n, 200n, 1700000000);
    let receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    // 2. Claim created
    tx = await harness.emitClaimCreatedV1(claimId, creator.address, metadataHash);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    // 3. Evidence attached
    tx = await harness.emitEvidenceSubmittedV1(claimId, 1n, creator.address, evidenceHash);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    // 4. Status -> UnderVerification
    tx = await harness.emitClaimStatusTransitionedV1(claimId, admin.address, 0, 1);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    // 5. Verifiers deposit collateral
    tx = await harness.emitStakeDepositedV1(verifier1.address, 1000n, 1000n);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    tx = await harness.emitStakeDepositedV1(verifier2.address, 1000n, 1000n);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    // 6. Verifiers lock stake and vote
    tx = await harness.emitStakeLockedV1(claimId, verifier1.address, 1n, 500n, 500n);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    tx = await harness.emitVerificationSubmittedV1(claimId, verifier1.address, true, 500n);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    tx = await harness.emitStakeLockedV1(claimId, verifier2.address, 1n, 500n, 500n);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    tx = await harness.emitVerificationSubmittedV1(claimId, verifier2.address, false, 500n);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    // 7. Round aggregation and claim resolved TRUE
    tx = await harness.emitOutcomeAggregatedV1(claimId, 1n, 1, 500n, 500n, 10000);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    tx = await harness.emitClaimResolvedV1(claimId, admin.address, true);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    // 8. Slashing losing verifier2 (100 tokens)
    tx = await harness.emitSlashExecutedV1(claimId, verifier2.address, reasonSlash, 100n);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    // 9. Reward escrowed for winner verifier1 (80 tokens)
    tx = await harness.emitRewardEscrowedV1(claimId, verifier1.address, 80n);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    // 10. Verifier1 claims reward
    tx = await harness.emitRewardClaimedV1(claimId, verifier1.address, 80n);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    // 11. Stakes unlocked
    tx = await harness.emitStakeUnlockedV1(claimId, verifier1.address, 1n, 500n, 0n);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    tx = await harness.emitStakeUnlockedV1(claimId, verifier2.address, 1n, 400n, 0n);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    // 12. Finalize claim
    tx = await harness.emitClaimFinalizedV1(claimId, admin.address);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    // 13. Treasury deposit of remaining 20 slashed tokens into Protocol Fees
    const opId = ethers.keccak256(ethers.toUtf8Bytes("SLASH_FEE_OP_42"));
    tx = await harness.emitTreasuryDepositV1(opId, 2, ethers.ZeroAddress, 20n, admin.address);
    receipt = await tx.wait();
    for (const log of receipt!.logs) {
      const parsed = harness.interface.parseLog(log);
      if (parsed) projection.applyLog(parsed.name, parsed.args);
    }

    // =========================================================================
    // INVARIANT ASSERTIONS ON RECONSTRUCTED STATE
    // =========================================================================
    // 1. Claim state reconstructed
    const projectedClaim = projection.claims.get(claimId);
    expect(projectedClaim).to.not.be.undefined;
    expect(projectedClaim!.creator).to.equal(creator.address);
    expect(projectedClaim!.metadataHash).to.equal(metadataHash);
    expect(projectedClaim!.status).to.equal(1);
    expect(projectedClaim!.resolved).to.be.true;
    expect(projectedClaim!.outcome).to.be.true;
    expect(projectedClaim!.finalized).to.be.true;

    // 2. Evidence state reconstructed
    const projectedEvidence = projection.evidence.get(claimId);
    expect(projectedEvidence).to.have.length(1);
    expect(projectedEvidence![0].evidenceHash).to.equal(evidenceHash);
    expect(projectedEvidence![0].revoked).to.be.false;

    // 3. Verifier 1 (Winner) financial accounting reconciled
    const v1State = projection.verifiers.get(verifier1.address.toLowerCase());
    expect(v1State).to.not.be.undefined;
    expect(v1State!.totalStaked).to.equal(1000n);
    expect(v1State!.activeStaked).to.equal(0n);
    expect(v1State!.rewardsClaimed).to.equal(80n);
    expect(v1State!.slashed).to.equal(0n);

    // 4. Verifier 2 (Loser) financial accounting reconciled
    const v2State = projection.verifiers.get(verifier2.address.toLowerCase());
    expect(v2State).to.not.be.undefined;
    expect(v2State!.totalStaked).to.equal(1000n);
    expect(v2State!.activeStaked).to.equal(0n);
    expect(v2State!.slashed).to.equal(100n);
    expect(v2State!.rewardsClaimed).to.equal(0n);

    // 5. Escrow and Treasury financial reconciliation
    expect(projection.rewardsEscrowed.get(verifier1.address.toLowerCase())).to.equal(0n);
    expect(projection.treasury.accounts[2]).to.equal(20n); // 20 tokens to protocol fee bucket
    expect(projection.treasury.totalAssets).to.equal(20n);

    // Financial balance invariant: Slashed Total (100) = Winner Reward (80) + Treasury Fee (20)
    expect(v2State!.slashed).to.equal(v1State!.rewardsClaimed + projection.treasury.accounts[2]);

    // 6. Parameter versioning
    const param = projection.parameters.get(paramMinStake);
    expect(param).to.not.be.undefined;
    expect(param!.version).to.equal(1n);
    expect(param!.value).to.equal(200n);
  });
});
