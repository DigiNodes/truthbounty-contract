import { expect } from "chai";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import hre from "hardhat";

describe("ReputationSnapshotEngine", function () {
    async function deployFixture() {
        const [admin, verifier1, verifier2, verifier3] = await hre.ethers.getSigners();

        const ReputationSnapshotEngine = await hre.ethers.getContractFactory("ReputationSnapshotEngine");
        const engine = await ReputationSnapshotEngine.deploy(admin.address);
        await engine.waitForDeployment();

        const MockOracle = await hre.ethers.getContractFactory("MockReputationOracle");
        const mockOracle = await MockOracle.deploy();
        await mockOracle.waitForDeployment();

        return { admin, verifier1, verifier2, verifier3, engine, mockOracle };
    }

    describe("Deployment", function () {
        it("should set up roles correctly", async function () {
            const { admin, engine } = await loadFixture(deployFixture);
            const DEFAULT_ADMIN_ROLE = await engine.DEFAULT_ADMIN_ROLE();
            const SNAPSHOT_ROLE = await engine.SNAPSHOT_ROLE();
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            const PAUSER_ROLE = await engine.PAUSER_ROLE();

            expect(await engine.hasRole(DEFAULT_ADMIN_ROLE, admin.address)).to.be.true;
            expect(await engine.hasRole(SNAPSHOT_ROLE, admin.address)).to.be.true;
            expect(await engine.hasRole(ENGINE_ROLE, admin.address)).to.be.true;
            expect(await engine.hasRole(PAUSER_ROLE, admin.address)).to.be.true;
        });

        it("should reject zero address admin", async function () {
            const ReputationSnapshotEngine = await hre.ethers.getContractFactory("ReputationSnapshotEngine");
            await expect(
                ReputationSnapshotEngine.deploy(hre.ethers.ZeroAddress)
            ).to.be.revertedWithCustomError;
        });

        it("should start with latestSnapshotId = 0", async function () {
            const { engine } = await loadFixture(deployFixture);
            expect(await engine.latestSnapshotId()).to.equal(0n);
        });
    });

    describe("checkpointReputation", function () {
        it("should record reputation checkpoints per verifier", async function () {
            const { admin, verifier1, engine, mockOracle } = await loadFixture(deployFixture);

            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.checkpointReputation(verifier1.address, 1000n);
            expect(await engine.getVerifierCheckpointCount(verifier1.address)).to.equal(1n);

            await engine.checkpointReputation(verifier1.address, 2000n);
            expect(await engine.getVerifierCheckpointCount(verifier1.address)).to.equal(2n);
        });

        it("should reject zero address checkpoint", async function () {
            const { admin, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await expect(
                engine.checkpointReputation(hre.ethers.ZeroAddress, 1000n)
            ).to.be.revertedWithCustomError(engine, "ZeroAddress");
        });

        it("should reject non-engine role callers", async function () {
            const { verifier1, engine } = await loadFixture(deployFixture);
            await expect(
                engine.connect(verifier1).checkpointReputation(verifier1.address, 1000n)
            ).to.be.reverted;
        });
    });

    describe("recordProtocolSnapshot", function () {
        it("should create a sequential snapshot ID", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            const sid1 = await engine.recordProtocolSnapshot.staticCall(verifier1.address, 1000n);
            await engine.recordProtocolSnapshot(verifier1.address, 1000n);
            expect(await engine.latestSnapshotId()).to.equal(1n);

            const sid2 = await engine.recordProtocolSnapshot.staticCall(verifier1.address, 2000n);
            await engine.recordProtocolSnapshot(verifier1.address, 2000n);
            expect(await engine.latestSnapshotId()).to.equal(2n);
        });

        it("should store immutable snapshot metadata", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            const tx = await engine.recordProtocolSnapshot(verifier1.address, 5000n);
            const receipt = await tx.wait();
            const block = await hre.ethers.provider.getBlock(receipt!.blockNumber);
            const snapshotId = await engine.latestSnapshotId();

            const meta = await engine.snapshotMeta(snapshotId);
            expect(meta.id).to.equal(1n);
            expect(meta.entryCount).to.equal(1n);
            expect(meta.createdBlock).to.equal(block!.number);
            expect(meta.finalized).to.be.true;
        });

        it("should store snapshot entries accessible via getSnapshot", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.recordProtocolSnapshot(verifier1.address, 3000n);
            const snapshotId = await engine.latestSnapshotId();

            const [meta, entries] = await engine.getSnapshot(snapshotId);
            expect(meta.id).to.equal(snapshotId);
            expect(entries.length).to.equal(1);
            expect(entries[0].verifier).to.equal(verifier1.address);
            expect(entries[0].reputationScore).to.equal(3000n);
        });

        it("should emit events on snapshot creation", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            const tx = await engine.recordProtocolSnapshot(verifier1.address, 1000n);
            await expect(tx).to.emit(engine, "VerifierSnapshotRecorded");
            await expect(tx).to.emit(engine, "GlobalSnapshotCreated");
        });

        it("should reject zero address verifier", async function () {
            const { admin, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await expect(
                engine.recordProtocolSnapshot(hre.ethers.ZeroAddress, 1000n)
            ).to.be.revertedWithCustomError(engine, "ZeroAddress");
        });

        it("should reject non-engine role callers", async function () {
            const { verifier1, engine } = await loadFixture(deployFixture);
            await expect(
                engine.connect(verifier1).recordProtocolSnapshot(verifier1.address, 1000n)
            ).to.be.reverted;
        });
    });

    describe("createGlobalSnapshot", function () {
        it("should create a snapshot with oracle scores", async function () {
            const { admin, verifier1, verifier2, engine, mockOracle } = await loadFixture(deployFixture);
            const SNAPSHOT_ROLE = await engine.SNAPSHOT_ROLE();
            await engine.grantRole(SNAPSHOT_ROLE, admin.address);

            await mockOracle.connect(admin).setReputationScore(verifier1.address, 1000n);
            await mockOracle.connect(admin).setReputationScore(verifier2.address, 2000n);

            const sid = await engine.createGlobalSnapshot.staticCall(
                [verifier1.address, verifier2.address],
                await mockOracle.getAddress()
            );
            await engine.createGlobalSnapshot(
                [verifier1.address, verifier2.address],
                await mockOracle.getAddress()
            );

            const [meta, entries] = await engine.getSnapshot(sid);
            expect(meta.id).to.equal(sid);
            expect(meta.entryCount).to.equal(2n);
            expect(entries[0].verifier).to.equal(verifier1.address);
            expect(entries[0].reputationScore).to.equal(1000n);
            expect(entries[1].verifier).to.equal(verifier2.address);
            expect(entries[1].reputationScore).to.equal(2000n);
        });

        it("should reject duplicate verifiers in same snapshot", async function () {
            const { admin, verifier1, engine, mockOracle } = await loadFixture(deployFixture);
            const SNAPSHOT_ROLE = await engine.SNAPSHOT_ROLE();
            await engine.grantRole(SNAPSHOT_ROLE, admin.address);

            await expect(
                engine.createGlobalSnapshot(
                    [verifier1.address, verifier1.address],
                    await mockOracle.getAddress()
                )
            ).to.be.revertedWithCustomError(engine, "DuplicateEntry");
        });

        it("should reject empty verifier array", async function () {
            const { admin, engine, mockOracle } = await loadFixture(deployFixture);
            const SNAPSHOT_ROLE = await engine.SNAPSHOT_ROLE();
            await engine.grantRole(SNAPSHOT_ROLE, admin.address);

            await expect(
                engine.createGlobalSnapshot([], await mockOracle.getAddress())
            ).to.be.revertedWithCustomError(engine, "EmptySnapshot");
        });

        it("should reject zero address in verifier array", async function () {
            const { admin, verifier1, engine, mockOracle } = await loadFixture(deployFixture);
            const SNAPSHOT_ROLE = await engine.SNAPSHOT_ROLE();
            await engine.grantRole(SNAPSHOT_ROLE, admin.address);

            await expect(
                engine.createGlobalSnapshot(
                    [verifier1.address, hre.ethers.ZeroAddress],
                    await mockOracle.getAddress()
                )
            ).to.be.revertedWithCustomError(engine, "ZeroAddress");
        });

        it("should emit GlobalSnapshotCreated event", async function () {
            const { admin, verifier1, engine, mockOracle } = await loadFixture(deployFixture);
            const SNAPSHOT_ROLE = await engine.SNAPSHOT_ROLE();
            await engine.grantRole(SNAPSHOT_ROLE, admin.address);

            await mockOracle.connect(admin).setReputationScore(verifier1.address, 500n);

            await expect(
                engine.createGlobalSnapshot([verifier1.address], await mockOracle.getAddress())
            ).to.emit(engine, "GlobalSnapshotCreated");
        });
    });

    describe("getSnapshot", function () {
        it("should revert for non-existent snapshot", async function () {
            const { engine } = await loadFixture(deployFixture);
            await expect(
                engine.getSnapshot(999n)
            ).to.be.revertedWithCustomError(engine, "InvalidSnapshot");
        });
    });

    describe("getLatestSnapshot", function () {
        it("should return 0 for verifier with no checkpoints", async function () {
            const { engine, verifier1 } = await loadFixture(deployFixture);
            const [score, blockNum] = await engine.getLatestSnapshot(verifier1.address);
            expect(score).to.equal(0n);
            expect(blockNum).to.equal(0n);
        });

        it("should return latest checkpoint value", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.checkpointReputation(verifier1.address, 100n);
            await time.advanceBlock();
            await engine.checkpointReputation(verifier1.address, 200n);

            const [score, blockNum] = await engine.getLatestSnapshot(verifier1.address);
            expect(score).to.equal(200n);
            expect(blockNum).to.be.gt(0);
        });
    });

    describe("getSnapshotAtBlock", function () {
        it("should return not found for verifier with no checkpoints", async function () {
            const { engine, verifier1 } = await loadFixture(deployFixture);
            const [score, found] = await engine.getSnapshotAtBlock(verifier1.address, 1n);
            expect(found).to.be.false;
            expect(score).to.equal(0n);
        });

        it("should return appropriate checkpoint for historical block", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.checkpointReputation(verifier1.address, 100n);
            const block1 = await hre.ethers.provider.getBlock("latest");

            await time.advanceBlock();
            await engine.checkpointReputation(verifier1.address, 200n);
            const block2 = await hre.ethers.provider.getBlock("latest");

            const [scoreAtBlock1] = await engine.getSnapshotAtBlock(verifier1.address, block1!.number);
            expect(scoreAtBlock1).to.equal(100n);

            const [scoreAtBlock2] = await engine.getSnapshotAtBlock(verifier1.address, block2!.number);
            expect(scoreAtBlock2).to.equal(200n);

            const [latestScore] = await engine.getSnapshotAtBlock(verifier1.address, 999999999n);
            expect(latestScore).to.equal(200n);
        });
    });

    describe("getVerifierSnapshots", function () {
        it("should return checkpoints within block range", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.checkpointReputation(verifier1.address, 100n);
            await time.advanceBlock();
            await engine.checkpointReputation(verifier1.address, 200n);
            await time.advanceBlock();
            await engine.checkpointReputation(verifier1.address, 300n);

            const [blocks, scores] = await engine.getVerifierSnapshots(verifier1.address, 0n, 1_000_000_000n);
            expect(blocks.length).to.equal(3);
            expect(scores[0]).to.equal(100n);
            expect(scores[1]).to.equal(200n);
            expect(scores[2]).to.equal(300n);
        });

        it("should filter by block range", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.checkpointReputation(verifier1.address, 100n);
            const firstBlock = await hre.ethers.provider.getBlock("latest");
            const firstBlockNum = firstBlock!.number;
            await time.advanceBlock();
            await engine.checkpointReputation(verifier1.address, 200n);

            const [blocks, scores] = await engine.getVerifierSnapshots(
                verifier1.address,
                firstBlockNum + 1,
                1_000_000_000n
            );
            expect(blocks.length).to.equal(1);
            expect(scores[0]).to.equal(200n);
        });
    });

    describe("getSnapshotEntry", function () {
        it("should return entry for verifier in snapshot", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.recordProtocolSnapshot(verifier1.address, 777n);
            const snapshotId = await engine.latestSnapshotId();

            const entry = await engine.getSnapshotEntry(snapshotId, verifier1.address);
            expect(entry.verifier).to.equal(verifier1.address);
            expect(entry.reputationScore).to.equal(777n);
        });

        it("should revert for verifier not in snapshot", async function () {
            const { admin, verifier1, verifier2, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.recordProtocolSnapshot(verifier1.address, 777n);
            const snapshotId = await engine.latestSnapshotId();

            await expect(
                engine.getSnapshotEntry(snapshotId, verifier2.address)
            ).to.be.revertedWithCustomError(engine, "VerifierNotInSnapshot");
        });
    });

    describe("Pause", function () {
        it("should pause and unpause", async function () {
            const { admin, engine } = await loadFixture(deployFixture);
            const PAUSER_ROLE = await engine.PAUSER_ROLE();
            await engine.grantRole(PAUSER_ROLE, admin.address);

            await engine.pause();
            expect(await engine.paused()).to.be.true;

            await engine.unpause();
            expect(await engine.paused()).to.be.false;
        });

        it("should prevent actions when paused", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const [PAUSER_ROLE, ENGINE_ROLE] = await Promise.all([
                engine.PAUSER_ROLE(),
                engine.ENGINE_ROLE(),
            ]);
            await engine.grantRole(PAUSER_ROLE, admin.address);
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.pause();

            await expect(
                engine.checkpointReputation(verifier1.address, 100n)
            ).to.be.reverted;
        });
    });

    describe("getSnapshotVerifierAt", function () {
        it("should return verifier details by index", async function () {
            const { admin, verifier1, verifier2, engine, mockOracle } = await loadFixture(deployFixture);
            const SNAPSHOT_ROLE = await engine.SNAPSHOT_ROLE();
            await engine.grantRole(SNAPSHOT_ROLE, admin.address);

            await mockOracle.connect(admin).setReputationScore(verifier1.address, 100n);
            await mockOracle.connect(admin).setReputationScore(verifier2.address, 200n);

            await engine.createGlobalSnapshot(
                [verifier1.address, verifier2.address],
                await mockOracle.getAddress()
            );
            const snapshotId = await engine.latestSnapshotId();

            expect(await engine.getSnapshotVerifierCount(snapshotId)).to.equal(2n);

            const [v1, s1] = await engine.getSnapshotVerifierAt(snapshotId, 0n);
            expect(v1).to.equal(verifier1.address);
            expect(s1).to.equal(100n);

            const [v2, s2] = await engine.getSnapshotVerifierAt(snapshotId, 1n);
            expect(v2).to.equal(verifier2.address);
            expect(s2).to.equal(200n);
        });

        it("should revert for out of bounds index", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.recordProtocolSnapshot(verifier1.address, 100n);
            const snapshotId = await engine.latestSnapshotId();

            await expect(
                engine.getSnapshotVerifierAt(snapshotId, 5n)
            ).to.be.revertedWithCustomError(engine, "InvalidSnapshot");
        });
    });

    describe("getVerifierCheckpointAt", function () {
        it("should return checkpoint data by position", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.checkpointReputation(verifier1.address, 100n);
            await time.advanceBlock();
            await engine.checkpointReputation(verifier1.address, 200n);

            const [block0, score0] = await engine.getVerifierCheckpointAt(verifier1.address, 0n);
            expect(score0).to.equal(100n);

            const [block1, score1] = await engine.getVerifierCheckpointAt(verifier1.address, 1n);
            expect(score1).to.equal(200n);
            expect(block1).to.be.gt(block0);
        });
    });

    describe("isVerifierInSnapshot", function () {
        it("should return true for included verifier", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.recordProtocolSnapshot(verifier1.address, 100n);
            const snapshotId = await engine.latestSnapshotId();

            expect(await engine.isVerifierInSnapshot(snapshotId, verifier1.address)).to.be.true;
        });

        it("should return false for excluded verifier", async function () {
            const { admin, verifier1, verifier2, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.recordProtocolSnapshot(verifier1.address, 100n);
            const snapshotId = await engine.latestSnapshotId();

            expect(await engine.isVerifierInSnapshot(snapshotId, verifier2.address)).to.be.false;
        });
    });

    describe("Immutable Snapshots", function () {
        it("should never allow snapshot metadata to change after creation", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.recordProtocolSnapshot(verifier1.address, 1000n);
            const snapshotId = await engine.latestSnapshotId();

            const metaBefore = await engine.snapshotMeta(snapshotId);
            await time.advanceBlock();

            const metaAfter = await engine.snapshotMeta(snapshotId);
            expect(metaBefore.id).to.equal(metaAfter.id);
            expect(metaBefore.entryCount).to.equal(metaAfter.entryCount);
            expect(metaBefore.createdAt).to.equal(metaAfter.createdAt);
            expect(metaBefore.createdBlock).to.equal(metaAfter.createdBlock);
            expect(metaBefore.finalized).to.equal(metaAfter.finalized);
        });

        it("should never allow entry modification after snapshot creation", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            await engine.recordProtocolSnapshot(verifier1.address, 1000n);
            const snapshotId = await engine.latestSnapshotId();

            const [, entriesBefore] = await engine.getSnapshot(snapshotId);
            expect(entriesBefore[0].reputationScore).to.equal(1000n);

            await engine.recordProtocolSnapshot(verifier1.address, 9999n);
            const snapshotId2 = await engine.latestSnapshotId();

            const [, entriesAfter] = await engine.getSnapshot(snapshotId);
            expect(entriesAfter[0].reputationScore).to.equal(1000n);
        });
    });

    describe("Sequential IDs", function () {
        it("should produce strictly increasing snapshot IDs", async function () {
            const { admin, verifier1, engine } = await loadFixture(deployFixture);
            const ENGINE_ROLE = await engine.ENGINE_ROLE();
            await engine.grantRole(ENGINE_ROLE, admin.address);

            const ids: bigint[] = [];
            for (let i = 0; i < 5; i++) {
                await engine.recordProtocolSnapshot(verifier1.address, BigInt(i * 100));
                ids.push(await engine.latestSnapshotId());
            }

            for (let i = 1; i < ids.length; i++) {
                expect(ids[i]).to.equal(ids[i - 1] + 1n);
            }
        });
    });

    describe("Duplicate Prevention", function () {
        it("should prevent duplicate entries in global snapshots", async function () {
            const { admin, verifier1, engine, mockOracle } = await loadFixture(deployFixture);
            const SNAPSHOT_ROLE = await engine.SNAPSHOT_ROLE();
            await engine.grantRole(SNAPSHOT_ROLE, admin.address);

            await mockOracle.connect(admin).setReputationScore(verifier1.address, 100n);

            await expect(
                engine.createGlobalSnapshot(
                    [verifier1.address, verifier1.address],
                    await mockOracle.getAddress()
                )
            ).to.be.revertedWithCustomError(engine, "DuplicateEntry");
        });
    });

    describe("getSnapshotPage", function () {
        it("should return paginated entries", async function () {
            const { admin, verifier1, verifier2, verifier3, engine, mockOracle } = await loadFixture(deployFixture);
            const SNAPSHOT_ROLE = await engine.SNAPSHOT_ROLE();
            await engine.grantRole(SNAPSHOT_ROLE, admin.address);

            await mockOracle.connect(admin).setReputationScore(verifier1.address, 100n);
            await mockOracle.connect(admin).setReputationScore(verifier2.address, 200n);
            await mockOracle.connect(admin).setReputationScore(verifier3.address, 300n);

            await engine.createGlobalSnapshot(
                [verifier1.address, verifier2.address, verifier3.address],
                await mockOracle.getAddress()
            );
            const snapshotId = await engine.latestSnapshotId();

            const page1 = await engine.getSnapshotPage(snapshotId, 0n, 2n);
            expect(page1.length).to.equal(2);
            expect(page1[0].verifier).to.equal(verifier1.address);
            expect(page1[1].verifier).to.equal(verifier2.address);

            const page2 = await engine.getSnapshotPage(snapshotId, 2n, 2n);
            expect(page2.length).to.equal(1);
            expect(page2[0].verifier).to.equal(verifier3.address);

            const empty = await engine.getSnapshotPage(snapshotId, 10n, 5n);
            expect(empty.length).to.equal(0);
        });
    });
});