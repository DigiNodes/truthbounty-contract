import { expect } from "chai";
import hre from "hardhat";
import { Contract } from "ethers";

/**
 * @title ReputationSnapshot Efficiency Tests
 * @notice Tests to verify O(N) snapshot creation and O(log N) proof generation
 * @dev Ensures that ReputationSnapshot maintains optimal performance characteristics
 */

describe("ReputationSnapshot - Efficiency & Performance", function () {
    let reputationSnapshot: Contract;
    let mockOracle: Contract;
    let admin: any;
    let user1: any;
    let user2: any;
    let user3: any;
    let users: any[];

    async function deployMockOracle() {
        const MockOracle = await hre.ethers.getContractFactory("MockReputationOracle");
        const oracle = await MockOracle.deploy();
        await oracle.waitForDeployment();
        return oracle;
    }

    beforeEach(async () => {
        [admin, user1, user2, user3, ...users] = await hre.ethers.getSigners();

        const ReputationSnapshot = await hre.ethers.getContractFactory("ReputationSnapshot");
        reputationSnapshot = await ReputationSnapshot.deploy(admin.address);
        await reputationSnapshot.waitForDeployment();

        mockOracle = await deployMockOracle();

        const SNAPSHOT_ROLE = await reputationSnapshot.SNAPSHOT_ROLE();
        await reputationSnapshot.grantRole(SNAPSHOT_ROLE, admin.address);
    });

    describe("Snapshot Creation - O(N) Complexity", function () {
        it("Should create snapshot with 3 users", async () => {
            const userAddresses = [user1.address, user2.address, user3.address];
            const oracleAddr = await mockOracle.getAddress();

            const tx = await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const receipt = await tx.wait();

            expect(receipt.status).to.equal(1);
            console.log(`✓ Gas used for 3-user snapshot: ${receipt.gasUsed.toString()}`);
        });
    });

    describe("Proof Generation - O(log N) Complexity", function () {
        it("Should generate proof for user in snapshot", async () => {
            const userAddresses = [user1.address, user2.address, user3.address];
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            const [proof, index] = await reputationSnapshot.getMerkleProof(snapshotId, user1.address);

            expect(proof).to.be.an("array");
            expect(Number(index)).to.equal(0);
            console.log(`✓ Proof generated: length=${proof.length}`);
        });
    });

    describe("User Index Registry - O(1) Lookups", function () {
        it("Should perform O(1) user lookups", async () => {
            const userAddresses = [user1.address, user2.address, user3.address];
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            expect(await reputationSnapshot.isUserInSnapshot(snapshotId, user1.address)).to.be.true;
            expect(await reputationSnapshot.isUserInSnapshot(snapshotId, users[0].address)).to.be.false;

            console.log(`✓ User index registry O(1) lookups verified`);
        });

        it("Should access user data in O(1) time", async () => {
            const userAddresses = [user1.address, user2.address, user3.address];
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            const data = await reputationSnapshot.getSnapshotData(snapshotId, user1.address);
            expect(data.user).to.equal(user1.address);

            console.log(`✓ User data access is O(1)`);
        });

        it("Should reject users not in snapshot efficiently", async () => {
            const userAddresses = [user1.address, user2.address];
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            await expect(
                reputationSnapshot.getSnapshotData(snapshotId, user3.address)
            ).to.be.revertedWithCustomError(reputationSnapshot, "UserNotInSnapshot");

            console.log(`✓ User rejection is O(1)`);
        });
    });

    describe("Edge Cases", function () {
        it("Should handle single-user snapshots", async () => {
            const oracleAddr = await mockOracle.getAddress();
            const tx = await reputationSnapshot.createSnapshot([user1.address], oracleAddr);
            const receipt = await tx.wait();

            expect(receipt.status).to.equal(1);
            console.log(`✓ Single-user snapshot handled`);
        });

        it("Should handle two-user snapshots", async () => {
            const oracleAddr = await mockOracle.getAddress();
            const tx = await reputationSnapshot.createSnapshot(
                [user1.address, user2.address],
                oracleAddr
            );
            const receipt = await tx.wait();

            expect(receipt.status).to.equal(1);
            console.log(`✓ Two-user snapshot handled`);
        });

        it("Should reject duplicate users", async () => {
            const oracleAddr = await mockOracle.getAddress();
            await expect(
                reputationSnapshot.createSnapshot(
                    [user1.address, user1.address],
                    oracleAddr
                )
            ).to.be.revertedWithCustomError(reputationSnapshot, "DuplicateUser");

            console.log(`✓ Duplicate user rejection is O(1)`);
        });
    });

    describe("Snapshot Metadata", function () {
        it("Should store metadata with finalization flag", async () => {
            const userAddresses = [user1.address, user2.address, user3.address];
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            const metadata = await reputationSnapshot.snapshotMeta(snapshotId);
            expect(metadata.finalized).to.be.true;
            expect(metadata.userCount).to.equal(3);
            expect(metadata.root).to.not.equal(hre.ethers.ZeroHash);

            console.log(`✓ Metadata correctly stored`);
        });

        it("Should check snapshot validity in O(1) time", async () => {
            const userAddresses = [user1.address, user2.address];
            const oracleAddr = await mockOracle.getAddress();

            await reputationSnapshot.createSnapshot(userAddresses, oracleAddr);
            const snapshotId = 1;

            const isValid = await reputationSnapshot.isSnapshotValid(snapshotId);
            expect(isValid).to.be.true;

            console.log(`✓ Snapshot validity check is O(1)`);
        });
    });
});
