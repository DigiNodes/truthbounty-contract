import { expect } from "chai";
import { ethers } from "hardhat";

const VERSION = 1n;

describe("Canonical Event Families Emission (Specification §20)", function () {
  async function deployFixture() {
    const [admin, actor, verifier, challenger, recipient, operator] = await ethers.getSigners();
    const factory = await ethers.getContractFactory("EventArchitectureHarness");
    const harness = await factory.deploy();
    await harness.waitForDeployment();
    return { harness, admin, actor, verifier, challenger, recipient, operator };
  }

  function anyUint64(value: unknown): boolean {
    return typeof value === "bigint" && value >= 0n && value <= (1n << 64n) - 1n;
  }

  describe("1. Claims Family", function () {
    it("emits ClaimCreatedV1, ClaimUpdatedV1, ClaimStatusTransitionedV1, ClaimResolvedV1, ClaimFinalizedV1", async function () {
      const { harness, actor } = await deployFixture();
      const metadataHash = ethers.keccak256(ethers.toUtf8Bytes("claim-v2-meta"));

      await expect(harness.emitClaimCreatedV1(101, actor.address, metadataHash))
        .to.emit(harness, "ClaimCreatedV1")
        .withArgs(101, actor.address, metadataHash, anyUint64, VERSION);

      await expect(harness.emitClaimUpdatedV1(101, actor.address, metadataHash))
        .to.emit(harness, "ClaimUpdatedV1")
        .withArgs(101, actor.address, metadataHash, anyUint64, VERSION);

      await expect(harness.emitClaimStatusTransitionedV1(101, actor.address, 0, 1))
        .to.emit(harness, "ClaimStatusTransitionedV1")
        .withArgs(101, actor.address, 0, 1, anyUint64, VERSION);

      await expect(harness.emitClaimResolvedV1(101, actor.address, true))
        .to.emit(harness, "ClaimResolvedV1")
        .withArgs(101, actor.address, true, anyUint64, VERSION);

      await expect(harness.emitClaimFinalizedV1(101, actor.address))
        .to.emit(harness, "ClaimFinalizedV1")
        .withArgs(101, actor.address, anyUint64, VERSION);
    });
  });

  describe("2. Evidence Family", function () {
    it("emits EvidenceSubmittedV1, EvidenceRevokedV1, ClaimClosedForEvidenceV1", async function () {
      const { harness, actor } = await deployFixture();
      const evidenceHash = ethers.keccak256(ethers.toUtf8Bytes("ipfs-cid-evidence-hash"));
      const reasonHash = ethers.keccak256(ethers.toUtf8Bytes("TAMPERED_EVIDENCE"));

      await expect(harness.emitEvidenceSubmittedV1(101, 1, actor.address, evidenceHash))
        .to.emit(harness, "EvidenceSubmittedV1")
        .withArgs(101, 1, actor.address, evidenceHash, anyUint64, VERSION);

      await expect(harness.emitEvidenceRevokedV1(101, 1, actor.address, reasonHash))
        .to.emit(harness, "EvidenceRevokedV1")
        .withArgs(101, 1, actor.address, reasonHash, anyUint64, VERSION);

      await expect(harness.emitClaimClosedForEvidenceV1(101, actor.address))
        .to.emit(harness, "ClaimClosedForEvidenceV1")
        .withArgs(101, actor.address, anyUint64, VERSION);
    });
  });

  describe("3. Staking & Collateral Family", function () {
    it("emits StakeDepositedV1, StakeLockedV1, StakeUnlockedV1, StakeWithdrawnV1", async function () {
      const { harness, verifier } = await deployFixture();

      await expect(harness.emitStakeDepositedV1(verifier.address, 1000n, 1000n))
        .to.emit(harness, "StakeDepositedV1")
        .withArgs(verifier.address, 1000n, 1000n, anyUint64, VERSION);

      await expect(harness.emitStakeLockedV1(101, verifier.address, 1, 500n, 500n))
        .to.emit(harness, "StakeLockedV1")
        .withArgs(101, verifier.address, 1, 500n, 500n, anyUint64, VERSION);

      await expect(harness.emitStakeUnlockedV1(101, verifier.address, 1, 500n, 0n))
        .to.emit(harness, "StakeUnlockedV1")
        .withArgs(101, verifier.address, 1, 500n, 0n, anyUint64, VERSION);

      await expect(harness.emitStakeWithdrawnV1(verifier.address, 1000n, 0n))
        .to.emit(harness, "StakeWithdrawnV1")
        .withArgs(verifier.address, 1000n, 0n, anyUint64, VERSION);
    });
  });

  describe("4. Verification & Voting Family", function () {
    it("emits VerificationSubmittedV1, VerificationChallengedV1", async function () {
      const { harness, verifier, challenger } = await deployFixture();
      const reasonHash = ethers.keccak256(ethers.toUtf8Bytes("BRIBE_DETECTED"));

      await expect(harness.emitVerificationSubmittedV1(101, verifier.address, true, 500n))
        .to.emit(harness, "VerificationSubmittedV1")
        .withArgs(101, verifier.address, true, 500n, anyUint64, VERSION);

      await expect(harness.emitVerificationChallengedV1(101, challenger.address, reasonHash))
        .to.emit(harness, "VerificationChallengedV1")
        .withArgs(101, challenger.address, reasonHash, anyUint64, VERSION);
    });
  });

  describe("5. Rounds Family", function () {
    it("emits RoundStartedV1, RoundEndedV1", async function () {
      const { harness } = await deployFixture();
      const now = Math.floor(Date.now() / 1000);

      await expect(harness.emitRoundStartedV1(101, 1, now, now + 86400, 100n))
        .to.emit(harness, "RoundStartedV1")
        .withArgs(101, 1, now, now + 86400, 100n, anyUint64, VERSION);

      await expect(harness.emitRoundEndedV1(101, 1, 5000n, 1000n, 12))
        .to.emit(harness, "RoundEndedV1")
        .withArgs(101, 1, 5000n, 1000n, 12, anyUint64, VERSION);
    });
  });

  describe("6. Outcomes & Aggregation Family", function () {
    it("emits OutcomeAggregatedV1", async function () {
      const { harness } = await deployFixture();

      await expect(harness.emitOutcomeAggregatedV1(101, 1, 1, 5000n, 1000n, 8333))
        .to.emit(harness, "OutcomeAggregatedV1")
        .withArgs(101, 1, 1, 5000n, 1000n, 8333, anyUint64, VERSION);
    });
  });

  describe("7. Disputes Family", function () {
    it("emits DisputeRaisedV1, DisputeResolvedV1", async function () {
      const { harness, challenger, admin } = await deployFixture();
      const reasonHash = ethers.keccak256(ethers.toUtf8Bytes("OUTCOME_CONTESTED"));

      await expect(harness.emitDisputeRaisedV1(101, 1, challenger.address, 200n, reasonHash))
        .to.emit(harness, "DisputeRaisedV1")
        .withArgs(101, 1, challenger.address, 200n, reasonHash, anyUint64, VERSION);

      await expect(harness.emitDisputeResolvedV1(101, 1, admin.address, 1, 1))
        .to.emit(harness, "DisputeResolvedV1")
        .withArgs(101, 1, admin.address, 1, 1, anyUint64, VERSION);
    });
  });

  describe("8. Rewards Family", function () {
    it("emits RewardCalculatedV1, RewardEscrowedV1, RewardClaimedV1, BatchRewardClaimedV1", async function () {
      const { harness, recipient } = await deployFixture();
      const calcId = ethers.keccak256(ethers.toUtf8Bytes("CALC-001"));

      await expect(harness.emitRewardCalculatedV1(calcId, recipient.address, 400n))
        .to.emit(harness, "RewardCalculatedV1")
        .withArgs(calcId, recipient.address, 400n, anyUint64, VERSION);

      await expect(harness.emitRewardEscrowedV1(101, recipient.address, 400n))
        .to.emit(harness, "RewardEscrowedV1")
        .withArgs(101, recipient.address, 400n, anyUint64, VERSION);

      await expect(harness.emitRewardClaimedV1(101, recipient.address, 400n))
        .to.emit(harness, "RewardClaimedV1")
        .withArgs(101, recipient.address, 400n, anyUint64, VERSION);

      await expect(harness.emitBatchRewardClaimedV1(recipient.address, 3, 1200n))
        .to.emit(harness, "BatchRewardClaimedV1")
        .withArgs(recipient.address, 3, 1200n, anyUint64, VERSION);
    });
  });

  describe("9. Slashing Family", function () {
    it("emits SlashExecutedV1, BatchSlashExecutedV1", async function () {
      const { harness, verifier } = await deployFixture();
      const reason = ethers.keccak256(ethers.toUtf8Bytes("LOSING_VOTE"));

      await expect(harness.emitSlashExecutedV1(101, verifier.address, reason, 100n))
        .to.emit(harness, "SlashExecutedV1")
        .withArgs(101, verifier.address, reason, 100n, anyUint64, VERSION);

      await expect(harness.emitBatchSlashExecutedV1(101, 1, 5, 500n))
        .to.emit(harness, "BatchSlashExecutedV1")
        .withArgs(101, 1, 5, 500n, anyUint64, VERSION);
    });
  });

  describe("10. Withdrawals Family", function () {
    it("emits WithdrawalQueuedV1, WithdrawalExecutedV1, WithdrawalCancelledV1", async function () {
      const { harness, actor, admin } = await deployFixture();
      const withdrawalId = ethers.keccak256(ethers.toUtf8Bytes("WITHDRAW-001"));
      const token = ethers.ZeroAddress;
      const reason = ethers.keccak256(ethers.toUtf8Bytes("USER_CANCELLED"));
      const now = Math.floor(Date.now() / 1000);

      await expect(harness.emitWithdrawalQueuedV1(withdrawalId, actor.address, token, 10000n, now + 172800))
        .to.emit(harness, "WithdrawalQueuedV1")
        .withArgs(withdrawalId, actor.address, token, 10000n, now + 172800, anyUint64, VERSION);

      await expect(harness.emitWithdrawalExecutedV1(withdrawalId, actor.address, token, 10000n))
        .to.emit(harness, "WithdrawalExecutedV1")
        .withArgs(withdrawalId, actor.address, token, 10000n, anyUint64, VERSION);

      await expect(harness.emitWithdrawalCancelledV1(withdrawalId, actor.address, reason))
        .to.emit(harness, "WithdrawalCancelledV1")
        .withArgs(withdrawalId, actor.address, reason, anyUint64, VERSION);
    });
  });

  describe("11. Treasury & Accounting Family", function () {
    it("emits TreasuryDepositV1, TreasuryTransferV1, TreasuryWithdrawalV1, TreasurySnapshotRecordedV1", async function () {
      const { harness, actor, recipient, operator } = await deployFixture();
      const opId = ethers.keccak256(ethers.toUtf8Bytes("OP-001"));
      const asset = ethers.ZeroAddress;

      await expect(harness.emitTreasuryDepositV1(opId, 0, asset, 50000n, actor.address))
        .to.emit(harness, "TreasuryDepositV1")
        .withArgs(opId, 0, asset, 50000n, actor.address, anyUint64, VERSION);

      await expect(harness.emitTreasuryTransferV1(opId, asset, recipient.address, 10000n))
        .to.emit(harness, "TreasuryTransferV1")
        .withArgs(opId, asset, recipient.address, 10000n, anyUint64, VERSION);

      await expect(harness.emitTreasuryWithdrawalV1(opId, 0, asset, recipient.address, 5000n, operator.address))
        .to.emit(harness, "TreasuryWithdrawalV1")
        .withArgs(opId, 0, asset, recipient.address, 5000n, operator.address, anyUint64, VERSION);

      await expect(harness.emitTreasurySnapshotRecordedV1(1, 100000n))
        .to.emit(harness, "TreasurySnapshotRecordedV1")
        .withArgs(1, 100000n, anyUint64, VERSION);
    });
  });

  describe("12. Parameters & Configuration Family", function () {
    it("emits ParameterUpdatedV1, AddressParameterUpdatedV1, FeeScheduleUpdatedV1", async function () {
      const { harness, actor, admin } = await deployFixture();
      const paramName = ethers.keccak256(ethers.toUtf8Bytes("MIN_STAKE_AMOUNT"));
      const feeType = ethers.keccak256(ethers.toUtf8Bytes("SUBMISSION_FEE"));

      await expect(harness.emitParameterUpdatedV1(paramName, 2, 100n, 200n, 1700000000))
        .to.emit(harness, "ParameterUpdatedV1")
        .withArgs(paramName, 2, 100n, 200n, 1700000000, anyUint64, VERSION);

      await expect(harness.emitAddressParameterUpdatedV1(paramName, 2, actor.address, admin.address))
        .to.emit(harness, "AddressParameterUpdatedV1")
        .withArgs(paramName, 2, actor.address, admin.address, anyUint64, VERSION);

      await expect(harness.emitFeeScheduleUpdatedV1(feeType, 1, 10n, 250n))
        .to.emit(harness, "FeeScheduleUpdatedV1")
        .withArgs(feeType, 1, 10n, 250n, anyUint64, VERSION);
    });
  });

  describe("13. Reputation Roots & Snapshots Family", function () {
    it("emits ReputationRootPublishedV1, ReputationScoreUpdatedV1, ReputationDecayedV1", async function () {
      const { harness, verifier } = await deployFixture();
      const root = ethers.keccak256(ethers.toUtf8Bytes("MERKLE_ROOT_V2"));
      const reason = ethers.keccak256(ethers.toUtf8Bytes("ROUND_WIN"));

      await expect(harness.emitReputationRootPublishedV1(1, root, 150, 1800000000))
        .to.emit(harness, "ReputationRootPublishedV1")
        .withArgs(1, root, 150, 1800000000, anyUint64, VERSION);

      await expect(harness.emitReputationScoreUpdatedV1(verifier.address, 1000n, 1100n, reason))
        .to.emit(harness, "ReputationScoreUpdatedV1")
        .withArgs(verifier.address, 1000n, 1100n, reason, anyUint64, VERSION);

      await expect(harness.emitReputationDecayedV1(verifier.address, 1100n, 1050n))
        .to.emit(harness, "ReputationDecayedV1")
        .withArgs(verifier.address, 1100n, 1050n, anyUint64, VERSION);
    });
  });

  describe("14. Roles & Access Control Family", function () {
    it("emits RoleGrantedV1, RoleRevokedV1, RoleAdminChangedV1", async function () {
      const { harness, admin, actor } = await deployFixture();
      const role = ethers.keccak256(ethers.toUtf8Bytes("RESOLVER_ROLE"));
      const adminRole = ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE"));

      await expect(harness.emitRoleGrantedV1(role, actor.address, admin.address))
        .to.emit(harness, "RoleGrantedV1")
        .withArgs(role, actor.address, admin.address, anyUint64, VERSION);

      await expect(harness.emitRoleRevokedV1(role, actor.address, admin.address))
        .to.emit(harness, "RoleRevokedV1")
        .withArgs(role, actor.address, admin.address, anyUint64, VERSION);

      await expect(harness.emitRoleAdminChangedV1(role, adminRole, ethers.ZeroHash))
        .to.emit(harness, "RoleAdminChangedV1")
        .withArgs(role, adminRole, ethers.ZeroHash, anyUint64, VERSION);
    });
  });

  describe("15. Emergency & Pauses Family", function () {
    it("emits EmergencyPauseActivatedV1, EmergencyPauseRecoveredV1", async function () {
      const { harness, admin } = await deployFixture();
      const reason = ethers.keccak256(ethers.toUtf8Bytes("SECURITY_ALERT"));

      await expect(harness.emitEmergencyPauseActivatedV1(admin.address, reason))
        .to.emit(harness, "EmergencyPauseActivatedV1")
        .withArgs(admin.address, reason, anyUint64, VERSION);

      await expect(harness.emitEmergencyPauseRecoveredV1(admin.address))
        .to.emit(harness, "EmergencyPauseRecoveredV1")
        .withArgs(admin.address, anyUint64, VERSION);
    });
  });

  describe("16. Upgrades & Governance Family", function () {
    it("emits GovernanceProposalCreatedV1, GovernanceProposalExecutedV1, ModuleRegisteredV1, UpgradeProposedV1, UpgradeApprovedV1, UpgradeExecutedV1, UpgradeRolledBackV1", async function () {
      const { harness, admin, actor, operator } = await deployFixture();
      const proposalId = ethers.keccak256(ethers.toUtf8Bytes("PROP-001"));
      const moduleId = ethers.keccak256(ethers.toUtf8Bytes("TRUTH_BOUNTY_WEIGHTED"));
      const metaHash = ethers.keccak256(ethers.toUtf8Bytes("proposal-metadata"));
      const layoutHash = ethers.keccak256(ethers.toUtf8Bytes("storage-layout-v2"));
      const migrationHash = ethers.keccak256(ethers.toUtf8Bytes("migration-hash"));

      await expect(harness.emitGovernanceProposalCreatedV1(proposalId, actor.address, metaHash))
        .to.emit(harness, "GovernanceProposalCreatedV1")
        .withArgs(proposalId, actor.address, metaHash, anyUint64, VERSION);

      await expect(harness.emitGovernanceProposalExecutedV1(proposalId, admin.address))
        .to.emit(harness, "GovernanceProposalExecutedV1")
        .withArgs(proposalId, admin.address, anyUint64, VERSION);

      await expect(harness.emitModuleRegisteredV1(moduleId, actor.address, 2, 0, 0, layoutHash))
        .to.emit(harness, "ModuleRegisteredV1")
        .withArgs(moduleId, actor.address, 2, 0, 0, layoutHash, anyUint64, VERSION);

      await expect(harness.emitUpgradeProposedV1(1, moduleId, operator.address, 2, 1, 0, migrationHash, actor.address))
        .to.emit(harness, "UpgradeProposedV1")
        .withArgs(1, moduleId, operator.address, 2, 1, 0, migrationHash, actor.address, anyUint64, VERSION);

      await expect(harness.emitUpgradeApprovedV1(1, moduleId, 1700000000, admin.address))
        .to.emit(harness, "UpgradeApprovedV1")
        .withArgs(1, moduleId, 1700000000, admin.address, anyUint64, VERSION);

      await expect(harness.emitUpgradeExecutedV1(1, moduleId, actor.address, operator.address, admin.address))
        .to.emit(harness, "UpgradeExecutedV1")
        .withArgs(1, moduleId, actor.address, operator.address, admin.address, anyUint64, VERSION);

      await expect(harness.emitUpgradeRolledBackV1(moduleId, operator.address, actor.address, metaHash, admin.address))
        .to.emit(harness, "UpgradeRolledBackV1")
        .withArgs(moduleId, operator.address, actor.address, metaHash, admin.address, anyUint64, VERSION);
    });
  });
});
