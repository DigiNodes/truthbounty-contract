import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";

// ─── CID test constants ──────────────────────────────────────────────────────
const CID_V0 = "QmZ4tDuvesekSs4qM5ZBKpXiZGun7S2CYtEZRB3DYXkjGx";
const CID_V1_B32 = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";
const CID_V1_B58 = "zdj7WWeQ43G6JJvLWQWZpyHuAMq6uYWRjkBXFad4vV7dy1Z3";
const CID_V1_B16 = "f01551220c3c4733ec8affd06cf9e9ff50ffc6bcd2ec85a6170004bb709669c31de94391a";
const CID_ALT   = "QmPK1s3pNYLi9ERiq3BDxKa4XosgWwFRQUydHUtz4YgpqB";

// ─── Fixture ─────────────────────────────────────────────────────────────────

async function deployFixture() {
  const [admin, uploader, other, registryRole] = await ethers.getSigners();

  const EvidenceManager = await ethers.getContractFactory("EvidenceManager");
  const em = await EvidenceManager.deploy(admin.address);
  await em.waitForDeployment();

  // Grant CLAIM_REGISTRY_ROLE to registryRole signer so we can call closeClaimForEvidence
  const CLAIM_REGISTRY_ROLE = await em.CLAIM_REGISTRY_ROLE();
  await em.connect(admin).grantRole(CLAIM_REGISTRY_ROLE, registryRole.address);

  return { em, admin, uploader, other, registryRole, CLAIM_REGISTRY_ROLE };
}

// =============================================================================
// 1. Deployment & roles
// =============================================================================

describe("EvidenceManager", function () {
  describe("Deployment", function () {
    it("grants DEFAULT_ADMIN_ROLE to initial admin", async function () {
      const { em, admin } = await loadFixture(deployFixture);
      expect(await em.hasRole(await em.DEFAULT_ADMIN_ROLE(), admin.address)).to.be.true;
    });

    it("grants PAUSER_ROLE to initial admin", async function () {
      const { em, admin } = await loadFixture(deployFixture);
      expect(await em.hasRole(await em.PAUSER_ROLE(), admin.address)).to.be.true;
    });

    it("grants CLAIM_REGISTRY_ROLE to initial admin", async function () {
      const { em, admin } = await loadFixture(deployFixture);
      expect(await em.hasRole(await em.CLAIM_REGISTRY_ROLE(), admin.address)).to.be.true;
    });

    it("starts with evidence counter at 0", async function () {
      const { em } = await loadFixture(deployFixture);
      expect(await em.evidenceCounter()).to.equal(0n);
    });

    it("reverts when deployed with zero admin address", async function () {
      const EvidenceManager = await ethers.getContractFactory("EvidenceManager");
      await expect(EvidenceManager.deploy(ethers.ZeroAddress))
        .to.be.revertedWith("EvidenceManager: zero admin address");
    });
  });

  // ===========================================================================
  // 2. Successful evidence upload
  // ===========================================================================

  describe("addEvidence — success cases", function () {
    it("uploads CIDv0 evidence and emits EvidenceAdded", async function () {
      const { em, uploader } = await loadFixture(deployFixture);

      await expect(em.connect(uploader).addEvidence(1, CID_V0))
        .to.emit(em, "EvidenceAdded")
        .withArgs(1n, 0n, uploader.address, CID_V0);
    });

    it("uploads CIDv1 base32 evidence", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await expect(em.connect(uploader).addEvidence(1, CID_V1_B32))
        .to.emit(em, "EvidenceAdded")
        .withArgs(1n, 0n, uploader.address, CID_V1_B32);
    });

    it("uploads CIDv1 base58btc evidence", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await expect(em.connect(uploader).addEvidence(1, CID_V1_B58))
        .to.emit(em, "EvidenceAdded")
        .withArgs(1n, 0n, uploader.address, CID_V1_B58);
    });

    it("uploads CIDv1 base16 evidence", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await expect(em.connect(uploader).addEvidence(1, CID_V1_B16))
        .to.emit(em, "EvidenceAdded")
        .withArgs(1n, 0n, uploader.address, CID_V1_B16);
    });

    it("assigns monotonically increasing IDs across claims", async function () {
      const { em, uploader, other } = await loadFixture(deployFixture);

      await em.connect(uploader).addEvidence(1, CID_V0);
      await em.connect(other).addEvidence(2, CID_ALT);

      expect(await em.evidenceCounter()).to.equal(2n);
    });

    it("records uploader address correctly", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(1, CID_V0);
      expect(await em.getEvidenceUploader(0)).to.equal(uploader.address);
    });

    it("records cidHash as keccak256 of cid", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(1, CID_V0);

      const expected = ethers.keccak256(ethers.toUtf8Bytes(CID_V0));
      expect(await em.getEvidenceCIDHash(0)).to.equal(expected);
    });

    it("records uploadedAt timestamp", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      const tx = await em.connect(uploader).addEvidence(1, CID_V0);
      const receipt = await tx.wait();
      const block = await ethers.provider.getBlock(receipt!.blockNumber);

      const ev = await em.getEvidence(0);
      expect(ev.uploadedAt).to.equal(BigInt(block!.timestamp));
    });

    it("records correct claimId in evidence struct", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(42, CID_V0);
      const ev = await em.getEvidence(0);
      expect(ev.claimId).to.equal(42n);
    });

    it("supports multiple evidence items on the same claim", async function () {
      const { em, uploader, other } = await loadFixture(deployFixture);

      await em.connect(uploader).addEvidence(1, CID_V0);
      await em.connect(other).addEvidence(1, CID_ALT);
      await em.connect(uploader).addEvidence(1, CID_V1_B32);

      expect(await em.getEvidenceCount(1)).to.equal(3n);
    });

    it("supports evidence on different claims independently", async function () {
      const { em, uploader } = await loadFixture(deployFixture);

      await em.connect(uploader).addEvidence(1, CID_V0);
      await em.connect(uploader).addEvidence(2, CID_V0); // same CID, different claim

      expect(await em.getEvidenceCount(1)).to.equal(1n);
      expect(await em.getEvidenceCount(2)).to.equal(1n);
    });

    it("emits exactly one EvidenceAdded event per submission", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      const tx = await em.connect(uploader).addEvidence(1, CID_V0);
      const receipt = await tx.wait();
      const events = receipt!.logs.filter(
        (l) => l.topics[0] === em.interface.getEvent("EvidenceAdded")!.topicHash
      );
      expect(events).to.have.length(1);
    });
  });

  // ===========================================================================
  // 3. Retrieval / view functions
  // ===========================================================================

  describe("Retrieval functions", function () {
    it("getEvidence returns full struct by global ID", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(7, CID_V0);

      const ev = await em.getEvidence(0);
      expect(ev.id).to.equal(0n);
      expect(ev.claimId).to.equal(7n);
      expect(ev.uploader).to.equal(uploader.address);
      expect(ev.cid).to.equal(CID_V0);
    });

    it("getEvidenceByClaim returns ordered array", async function () {
      const { em, uploader, other } = await loadFixture(deployFixture);

      await em.connect(uploader).addEvidence(5, CID_V0);
      await em.connect(other).addEvidence(5, CID_ALT);

      const list = await em.getEvidenceByClaim(5);
      expect(list).to.have.length(2);
      expect(list[0].cid).to.equal(CID_V0);
      expect(list[1].cid).to.equal(CID_ALT);
    });

    it("getEvidenceByClaim returns empty array for claim with no evidence", async function () {
      const { em } = await loadFixture(deployFixture);
      expect(await em.getEvidenceByClaim(999)).to.be.empty;
    });

    it("getEvidenceAtIndex returns correct item", async function () {
      const { em, uploader, other } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(3, CID_V0);
      await em.connect(other).addEvidence(3, CID_ALT);

      const second = await em.getEvidenceAtIndex(3, 1);
      expect(second.cid).to.equal(CID_ALT);
      expect(second.uploader).to.equal(other.address);
    });

    it("getEvidenceCount returns 0 for new claim", async function () {
      const { em } = await loadFixture(deployFixture);
      expect(await em.getEvidenceCount(100)).to.equal(0n);
    });

    it("getEvidenceCount increments after each upload", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(1, CID_V0);
      expect(await em.getEvidenceCount(1)).to.equal(1n);
      await em.connect(uploader).addEvidence(1, CID_ALT);
      expect(await em.getEvidenceCount(1)).to.equal(2n);
    });

    it("hasEvidence returns false before any upload", async function () {
      const { em } = await loadFixture(deployFixture);
      expect(await em.hasEvidence(55)).to.be.false;
    });

    it("hasEvidence returns true after upload", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(55, CID_V0);
      expect(await em.hasEvidence(55)).to.be.true;
    });

    it("getEvidenceUploader returns correct address", async function () {
      const { em, uploader, other } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(1, CID_V0);
      await em.connect(other).addEvidence(1, CID_ALT);

      expect(await em.getEvidenceUploader(0)).to.equal(uploader.address);
      expect(await em.getEvidenceUploader(1)).to.equal(other.address);
    });

    it("getEvidenceCIDHash matches keccak256 of cid", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(1, CID_V1_B32);

      const expected = ethers.keccak256(ethers.toUtf8Bytes(CID_V1_B32));
      expect(await em.getEvidenceCIDHash(0)).to.equal(expected);
    });

    it("isCIDRegistered returns false before upload", async function () {
      const { em } = await loadFixture(deployFixture);
      expect(await em.isCIDRegistered(1, CID_V0)).to.be.false;
    });

    it("isCIDRegistered returns true after upload", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(1, CID_V0);
      expect(await em.isCIDRegistered(1, CID_V0)).to.be.true;
    });

    it("isCIDRegistered is scoped per claim (same CID, different claim = not registered)", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(1, CID_V0);

      // Registered for claim 1 but not for claim 2
      expect(await em.isCIDRegistered(1, CID_V0)).to.be.true;
      expect(await em.isCIDRegistered(2, CID_V0)).to.be.false;
    });

    it("isClaimClosed returns false by default", async function () {
      const { em } = await loadFixture(deployFixture);
      expect(await em.isClaimClosed(1)).to.be.false;
    });
  });

  // ===========================================================================
  // 4. CID validation failures
  // ===========================================================================

  describe("addEvidence — CID validation failures", function () {
    it("reverts with InvalidCID on empty string", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await expect(em.connect(uploader).addEvidence(1, ""))
        .to.be.revertedWithCustomError(em, "InvalidCID");
    });

    it("reverts with InvalidCID on single-char string", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await expect(em.connect(uploader).addEvidence(1, "Q"))
        .to.be.revertedWithCustomError(em, "InvalidCID");
    });

    it("reverts with CIDTooLarge when CID exceeds MAX_CID_LENGTH", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      const oversized = "Qm" + "a".repeat(511); // 513 chars total
      await expect(em.connect(uploader).addEvidence(1, oversized))
        .to.be.revertedWithCustomError(em, "CIDTooLarge");
    });

    it("reverts with UnsupportedCIDVersion on unknown prefix 'x'", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await expect(em.connect(uploader).addEvidence(1, "xmfoo123"))
        .to.be.revertedWithCustomError(em, "UnsupportedCIDVersion");
    });

    it("reverts with UnsupportedCIDVersion on prefix 'Q' without 'm' second char", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await expect(em.connect(uploader).addEvidence(1, "QXabc123"))
        .to.be.revertedWithCustomError(em, "UnsupportedCIDVersion");
    });

    it("reverts with UnsupportedCIDVersion on numeric prefix '1'", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await expect(em.connect(uploader).addEvidence(1, "1234567890"))
        .to.be.revertedWithCustomError(em, "UnsupportedCIDVersion");
    });

    it("reverts with InvalidCID on CID containing a space", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      // space (0x20) is below printable range threshold 0x21
      await expect(em.connect(uploader).addEvidence(1, "Qm foo bar"))
        .to.be.revertedWithCustomError(em, "InvalidCID");
    });

    it("reverts with UnsupportedCIDVersion on 'http://' prefix", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await expect(em.connect(uploader).addEvidence(1, "http://ipfs.io/ipfs/QmFoo"))
        .to.be.revertedWithCustomError(em, "UnsupportedCIDVersion");
    });

    it("accepts exactly MAX_CID_LENGTH (512) bytes", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      // 'b' prefix (CIDv1 base32) + 511 lowercase alphanumeric chars
      const maxCid = "b" + "a".repeat(511);
      await expect(em.connect(uploader).addEvidence(1, maxCid)).to.not.be.reverted;
    });
  });

  // ===========================================================================
  // 5. Duplicate detection
  // ===========================================================================

  describe("addEvidence — duplicate detection", function () {
    it("reverts DuplicateEvidence when same CID re-submitted to same claim", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(1, CID_V0);
      await expect(em.connect(uploader).addEvidence(1, CID_V0))
        .to.be.revertedWithCustomError(em, "DuplicateEvidence");
    });

    it("allows the same CID on a different claim", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(1, CID_V0);
      await expect(em.connect(uploader).addEvidence(2, CID_V0)).to.not.be.reverted;
    });

    it("allows a different CID on the same claim", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(1, CID_V0);
      await expect(em.connect(uploader).addEvidence(1, CID_ALT)).to.not.be.reverted;
    });

    it("reverts duplicate even when submitted by a different uploader", async function () {
      const { em, uploader, other } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(1, CID_V0);
      await expect(em.connect(other).addEvidence(1, CID_V0))
        .to.be.revertedWithCustomError(em, "DuplicateEvidence");
    });

    it("duplicate check uses hash equality (normalised bytes)", async function () {
      const { em, uploader } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(1, CID_V0);

      // Same string = same hash → must be rejected
      await expect(em.connect(uploader).addEvidence(1, CID_V0))
        .to.be.revertedWithCustomError(em, "DuplicateEvidence");
    });
  });

  // ===========================================================================
  // 6. Claim lifecycle: closed claims
  // ===========================================================================

  describe("addEvidence — closed claim", function () {
    it("reverts ClaimClosed after closeClaimForEvidence is called", async function () {
      const { em, uploader, registryRole } = await loadFixture(deployFixture);

      await em.connect(registryRole).closeClaimForEvidence(1);
      await expect(em.connect(uploader).addEvidence(1, CID_V0))
        .to.be.revertedWithCustomError(em, "ClaimClosed");
    });

    it("emits ClaimClosedForEvidence event", async function () {
      const { em, registryRole } = await loadFixture(deployFixture);
      await expect(em.connect(registryRole).closeClaimForEvidence(1))
        .to.emit(em, "ClaimClosedForEvidence")
        .withArgs(1n);
    });

    it("isClaimClosed returns true after close", async function () {
      const { em, registryRole } = await loadFixture(deployFixture);
      await em.connect(registryRole).closeClaimForEvidence(1);
      expect(await em.isClaimClosed(1)).to.be.true;
    });

    it("closing twice is idempotent (no second event, no revert)", async function () {
      const { em, registryRole } = await loadFixture(deployFixture);
      await em.connect(registryRole).closeClaimForEvidence(1);

      // Second call should not emit the event
      const tx = await em.connect(registryRole).closeClaimForEvidence(1);
      const receipt = await tx.wait();
      const events = receipt!.logs.filter(
        (l) => l.topics[0] === em.interface.getEvent("ClaimClosedForEvidence")!.topicHash
      );
      expect(events).to.have.length(0);
    });

    it("evidence added before close is still retrievable after close", async function () {
      const { em, uploader, registryRole } = await loadFixture(deployFixture);
      await em.connect(uploader).addEvidence(1, CID_V0);
      await em.connect(registryRole).closeClaimForEvidence(1);

      const ev = await em.getEvidence(0);
      expect(ev.cid).to.equal(CID_V0);
    });

    it("reverts when non-registry tries to close a claim", async function () {
      const { em, other, CLAIM_REGISTRY_ROLE } = await loadFixture(deployFixture);
      await expect(em.connect(other).closeClaimForEvidence(1))
        .to.be.revertedWithCustomError(em, "AccessControlUnauthorizedAccount")
        .withArgs(other.address, CLAIM_REGISTRY_ROLE);
    });
  });
});

