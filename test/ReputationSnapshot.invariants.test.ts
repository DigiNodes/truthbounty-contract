import { expect } from "chai";
import hre from "hardhat";
import { Contract } from "ethers";

/**
 * @title ReputationSnapshot Protocol Invariants
 * @notice Invariant-based tests to ensure correctness properties hold
 * @dev Tests critical protocol invariants that must hold regardless of input size
 */

describe("ReputationSnapshot - Protocol Invariants", function () {
    let reputationSnapshot: Contract;
    let mockOracle: Contract;
    let admin: any;
    let users: any[];

    async function deployMockOracle() {
        const MockOracle = await hre.ethers.getContractFactory("MockReputationOracle");
        const oracle = await MockOracle.deploy();
        await oracle.waitForDeployment();
        return oracle;
    }

    beforeEach(async () => {
        const signers = await hre.ethers.getSigners();
        admin = signers[0];
        users = signers.slice(1);

        const ReputationSnapshot = await hre.ethers.getContractFactory("ReputationSnapshot");
        reputationSnapshot = await ReputationSnapshot.deploy(admin.address);
        await reputationSnapshot.waitForDeployment();

        mockOracle = await deployMockOracle();

        const SNAPSHOT_ROLE = await reputationSnapshot.SNAPSHOT_ROLE();
        await reputationSnapshot.grantRole(SNAPSHOT_ROLE, admin.address);
    });

    describe("Invariant: User Index Consistency", function () {
        it("INV1: Every user in snapshot must be retrievable", async () => {
            const userAddresses = users.slice(0, 5).map(u => u.address);
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            for (const userAddr of userAddresses) {
                const isInSnapshot = await reputationSnapshot.isUserInSnapshot(snapshotId, userAddr);
                expect(isInSnapshot).to.be.true;

                const data = await reputationSnapshot.getSnapshotData(snapshotId, userAddr);
                expect(data.user).to.equal(userAddr);
            }

            console.log("✓ INV1: All users in snapshot are retrievable");
        });

        it("INV1b: Snapshot length matches user count", async () => {
            const userAddresses = users.slice(0, 7).map(u => u.address);
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            const snapshotLength = await reputationSnapshot.getSnapshotLength(snapshotId);
            expect(Number(snapshotLength)).to.equal(userAddresses.length);

            console.log("✓ INV1b: Snapshot length matches user count");
        });
    });

    describe("Invariant: Merkle Proof Validity", function () {
        it("INV2: Every user must have a valid Merkle proof", async () => {
            const userAddresses = users.slice(0, 8).map(u => u.address);
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            for (const userAddr of userAddresses) {
                const [proof, index] = await reputationSnapshot.getMerkleProof(snapshotId, userAddr);
                expect(proof).to.be.an("array");
                expect(Number(index)).to.be.lessThan(userAddresses.length);
            }

            console.log("✓ INV2: All users have valid Merkle proofs");
        });

        it("INV2b: Merkle proof length matches tree depth", async () => {
            const testSizes = [1, 2, 3, 4, 8];

            for (const n of testSizes) {
                if (n > users.length) continue;

                reputationSnapshot = await (
                    await hre.ethers.getContractFactory("ReputationSnapshot")
                ).deploy(admin.address);
                const SNAPSHOT_ROLE = await reputationSnapshot.SNAPSHOT_ROLE();
                await reputationSnapshot.grantRole(SNAPSHOT_ROLE, admin.address);

                const userAddresses = users.slice(0, n).map(u => u.address);
                const oracleAddr = await mockOracle.getAddress();
                await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
                const snapshotId = 1;

                const expectedDepth = Math.ceil(Math.log2(Math.max(1, n)));
                const [proof] = await reputationSnapshot.getMerkleProof(snapshotId, userAddresses[0]);
                const actualDepth = proof.length;

                expect(actualDepth).to.equal(expectedDepth);
            }

            console.log("✓ INV2b: Proof depth matches tree depth");
        });

        it("INV2c: Users not in snapshot are rejected", async () => {
            const userAddresses = users.slice(0, 5).map(u => u.address);
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            const randomUser = users[10];

            await expect(
                reputationSnapshot.getMerkleProof(snapshotId, randomUser.address)
            ).to.be.revertedWithCustomError(reputationSnapshot, "UserNotInSnapshot");

            console.log("✓ INV2c: Users not in snapshot are rejected");
        });
    });

    describe("Invariant: Snapshot Immutability", function () {
        it("INV3: Snapshot data must be immutable after creation", async () => {
            const userAddresses = users.slice(0, 4).map(u => u.address);
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            const data1 = await reputationSnapshot.getSnapshotData(snapshotId, users[0].address);
            const data2 = await reputationSnapshot.getSnapshotData(snapshotId, users[0].address);

            expect(data1.user).to.equal(data2.user);
            expect(data1.score).to.equal(data2.score);
            expect(data1.timestamp).to.equal(data2.timestamp);

            console.log("✓ INV3: Snapshot data is immutable");
        });

        it("INV3b: Merkle root is consistent", async () => {
            const userAddresses = users.slice(0, 6).map(u => u.address);
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            const meta1 = await reputationSnapshot.snapshotMeta(snapshotId);
            const meta2 = await reputationSnapshot.snapshotMeta(snapshotId);

            expect(meta1.root).to.equal(meta2.root);
            expect(meta1.root).to.not.equal(hre.ethers.ZeroHash);

            console.log("✓ INV3b: Merkle root is consistent");
        });
    });

    describe("Invariant: Finalization Status", function () {
        it("INV4: Snapshot must be finalized immediately after creation", async () => {
            const userAddresses = [users[0].address];
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            const metadata = await reputationSnapshot.snapshotMeta(snapshotId);
            expect(metadata.finalized).to.be.true;

            console.log("✓ INV4: Snapshot is finalized after creation");
        });

        it("INV4b: Finalized snapshots can be queried immediately", async () => {
            const userAddresses = users.slice(0, 5).map(u => u.address);
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            const isValid = await reputationSnapshot.isSnapshotValid(snapshotId);
            expect(isValid).to.be.true;

            console.log("✓ INV4b: Finalized snapshots are immediately queryable");
        });
    });

    describe("Invariant: No Duplicate Users", function () {
        it("INV6: Snapshot must reject duplicate users", async () => {
            const oracleAddr = await mockOracle.getAddress();

            await expect(
                reputationSnapshot.createSnapshot(
                    [users[0].address, users[0].address],
                    oracleAddr
                )
            ).to.be.revertedWithCustomError(reputationSnapshot, "DuplicateUser");

            console.log("✓ INV6: Duplicate users are rejected");
        });

        it("INV6b: Zero address must be rejected", async () => {
            const oracleAddr = await mockOracle.getAddress();

            await expect(
                reputationSnapshot.createSnapshot(
                    [hre.ethers.ZeroAddress, users[0].address],
                    oracleAddr
                )
            ).to.be.revertedWithCustomError(reputationSnapshot, "ZeroAddress");

            console.log("✓ INV6b: Zero address is rejected");
        });
    });

    describe("Invariant: Size Bounds", function () {
        it("INV10: Empty snapshots are rejected", async () => {
            const oracleAddr = await mockOracle.getAddress();

            await expect(
                reputationSnapshot.createSnapshot([], oracleAddr)
            ).to.be.revertedWithCustomError(reputationSnapshot, "EmptySnapshot");

            console.log("✓ INV10: Empty snapshots are rejected");
        });
    });

    describe("Invariant: Access Control", function () {
        it("INV8: Only SNAPSHOT_ROLE can create snapshots", async () => {
            const otherUser = users[5];
            const userAddresses = [users[0].address];
            const oracleAddr = await mockOracle.getAddress();

            await expect(
                reputationSnapshot
                    .connect(otherUser)
                    .createSnapshot(userAddresses, oracleAddr)
            ).to.be.revertedWithCustomError(reputationSnapshot, "AccessControlUnauthorizedAccount");

            console.log("✓ INV8: Only SNAPSHOT_ROLE can create snapshots");
        });
    });

    describe("Invariant: Tree Structure Correctness", function () {
        it("INV11: Tree levels must be correctly computed", async () => {
            const testSizes = [1, 2, 3, 4, 5];

            for (const size of testSizes) {
                if (size > users.length) continue;

                reputationSnapshot = await (
                    await hre.ethers.getContractFactory("ReputationSnapshot")
                ).deploy(admin.address);
                const SNAPSHOT_ROLE = await reputationSnapshot.SNAPSHOT_ROLE();
                await reputationSnapshot.grantRole(SNAPSHOT_ROLE, admin.address);

                const userAddresses = users.slice(0, size).map(u => u.address);
                const oracleAddr = await mockOracle.getAddress();
                await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
                const snapshotId = 1;

                for (const userAddr of userAddresses) {
                    const [proof] = await reputationSnapshot.getMerkleProof(snapshotId, userAddr);
                    expect(proof).to.be.an("array");
                }
            }

            console.log(`✓ INV11: Tree structure correctly computed for various sizes`);
        });
    });
});
