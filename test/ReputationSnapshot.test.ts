import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import hre from "hardhat";

function makeLeaf(user: string, score: bigint, timestamp: bigint): string {
    const inner = hre.ethers.solidityPackedKeccak256(
        ["address", "uint256", "uint256"],
        [user, score, timestamp]
    );

    return hre.ethers.keccak256(hre.ethers.solidityPacked(["bytes32"], [inner]));
}

function hashPair(left: string, right: string): string {
    return hre.ethers.keccak256(
        hre.ethers.solidityPacked(["bytes32", "bytes32"], [left, right])
    );
}

function computeRoot(leaves: string[]): string {
    if (leaves.length === 0) {
        return hre.ethers.ZeroHash;
    }

    let current = [...leaves];

    while (current.length > 1) {
        const next: string[] = [];

        for (let i = 0; i < current.length; i += 2) {
            const left = current[i];
            const right = i + 1 < current.length ? current[i + 1] : current[i];
            next.push(hashPair(left, right));
        }

        current = next;
    }

    return current[0];
}

function verifyProof(
    leaf: string,
    proof: string[],
    index: bigint
): string {
    let computed = leaf;
    let currentIndex = index;

    for (const sibling of proof) {
        computed = currentIndex % 2n === 0n
            ? hashPair(computed, sibling)
            : hashPair(sibling, computed);
        currentIndex /= 2n;
    }

    return computed;
}

describe("ReputationSnapshot - Merkle Root Computation", function () {
    async function deployFixture() {
        const [admin, user1, user2, user3, user4, user5] = await hre.ethers.getSigners();

        const ReputationSnapshot = await hre.ethers.getContractFactory("ReputationSnapshot");
        const reputationSnapshot = await ReputationSnapshot.deploy(admin.address);
        await reputationSnapshot.waitForDeployment();

        const MockOracle = await hre.ethers.getContractFactory("MockReputationOracle");
        const mockOracle = await MockOracle.deploy();
        await mockOracle.waitForDeployment();

        return { admin, user1, user2, user3, user4, user5, reputationSnapshot, mockOracle };
    }

    it("builds canonical left-right Merkle roots for odd and even snapshots", async function () {
        const { admin, user1, user2, user3, user4, reputationSnapshot, mockOracle } =
            await loadFixture(deployFixture);

        const SNAPSHOT_ROLE = await reputationSnapshot.SNAPSHOT_ROLE();
        await reputationSnapshot.grantRole(SNAPSHOT_ROLE, admin.address);

        const cases = [
            [user1.address, user2.address, user3.address],
            [user1.address, user2.address, user3.address, user4.address],
        ];

        for (const users of cases) {
            const baseScore = 1_000n;
            for (let i = 0; i < users.length; i++) {
                await mockOracle.connect(admin).setReputationScore(
                    users[i],
                    baseScore + BigInt(i) * 111n
                );
            }

            const tx = await reputationSnapshot.createSnapshot(users, await mockOracle.getAddress());
            const receipt = await tx.wait();
            const block = await hre.ethers.provider.getBlock(receipt!.blockNumber);
            const timestamp = BigInt(block!.timestamp);

            const snapshotId = await reputationSnapshot.latestSnapshotId();
            const meta = await reputationSnapshot.snapshotMeta(snapshotId);

            const leaves = users.map((user, index) =>
                makeLeaf(user, baseScore + BigInt(index) * 111n, timestamp)
            );

            expect(meta.root).to.equal(computeRoot(leaves));

            for (const user of users) {
                const [proof, proofIndex] = await reputationSnapshot.getMerkleProof(
                    snapshotId,
                    user
                );
                const data = await reputationSnapshot.getSnapshotData(snapshotId, user);
                const leaf = makeLeaf(user, data.score, data.timestamp);

                expect(verifyProof(leaf, proof, proofIndex)).to.equal(meta.root);
            }
        }
    });

    it("handles single-user snapshots without needing a proof branch", async function () {
        const { admin, user1, reputationSnapshot, mockOracle } = await loadFixture(deployFixture);

        const SNAPSHOT_ROLE = await reputationSnapshot.SNAPSHOT_ROLE();
        await reputationSnapshot.grantRole(SNAPSHOT_ROLE, admin.address);

        await mockOracle.connect(admin).setReputationScore(user1.address, 1234);

        const tx = await reputationSnapshot.createSnapshot(
            [user1.address],
            await mockOracle.getAddress()
        );
        const receipt = await tx.wait();
        const block = await hre.ethers.provider.getBlock(receipt!.blockNumber);
        const timestamp = BigInt(block!.timestamp);

        const snapshotId = await reputationSnapshot.latestSnapshotId();
        const meta = await reputationSnapshot.snapshotMeta(snapshotId);
        const data = await reputationSnapshot.getSnapshotData(snapshotId, user1.address);
        const leaf = makeLeaf(user1.address, data.score, BigInt(data.timestamp));

        expect(meta.root).to.equal(leaf);
        expect(timestamp).to.equal(BigInt(data.timestamp));

        const [proof, index] = await reputationSnapshot.getMerkleProof(snapshotId, user1.address);
        expect(proof).to.deep.equal([]);
        expect(index).to.equal(0n);
    });
});
