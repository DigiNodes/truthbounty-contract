import { expect } from "chai";
import { ethers } from "hardhat";
import { TruthBounty } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("TruthBounty", function () {
    let truthBounty: TruthBounty;
    let owner: SignerWithAddress;
    let addr1: SignerWithAddress;
    let addr2: SignerWithAddress;

    const INITIAL_SUPPLY = ethers.parseEther("10000000");

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        const TruthBountyFactory = await ethers.getContractFactory("TruthBounty");
        truthBounty = await TruthBountyFactory.deploy();
    });

    describe("Deployment", function () {
        it("Should set the right owner", async function () {
            expect(await truthBounty.owner()).to.equal(owner.address);
        });

        it("Should assign the total supply of tokens to the owner", async function () {
            const ownerBalance = await truthBounty.balanceOf(owner.address);
            expect(await truthBounty.totalSupply()).to.equal(ownerBalance);
        });
    });

    describe("Staking", function () {
        it("Should allow users to stake tokens", async function () {
            const stakeAmount = ethers.parseEther("100");
            await truthBounty.transfer(addr1.address, stakeAmount);
            await truthBounty.connect(addr1).stake(stakeAmount);

            expect(await truthBounty.stakes(addr1.address)).to.equal(stakeAmount);
            expect(await truthBounty.balanceOf(addr1.address)).to.equal(0);
        });

        it("Should allow users to unstake tokens", async function () {
            const stakeAmount = ethers.parseEther("100");
            await truthBounty.transfer(addr1.address, stakeAmount);
            await truthBounty.connect(addr1).stake(stakeAmount);
            await truthBounty.connect(addr1).unstake(stakeAmount);

            expect(await truthBounty.stakes(addr1.address)).to.equal(0);
            expect(await truthBounty.balanceOf(addr1.address)).to.equal(stakeAmount);
        });

        it("Should fail if unstaking more than staked", async function () {
            const stakeAmount = ethers.parseEther("100");
            await expect(truthBounty.connect(addr1).unstake(stakeAmount)).to.be.revertedWith("Insufficient stake");
        });
    });

    describe("Bounty Management", function () {
        it("Should allow users to create a bounty", async function () {
            const rewardAmount = ethers.parseEther("100");
            const ipfsHash = "QmTest";

            await truthBounty.transfer(addr1.address, rewardAmount);
            await truthBounty.connect(addr1).createBounty(ipfsHash, rewardAmount);

            const bounty = await truthBounty.bounties(0);
            expect(bounty.creator).to.equal(addr1.address);
            expect(bounty.rewardAmount).to.equal(rewardAmount);
            expect(bounty.ipfsHash).to.equal(ipfsHash);
            expect(bounty.resolved).to.be.false;
        });

        it("Should allow the owner to resolve a bounty", async function () {
            const rewardAmount = ethers.parseEther("100");
            const ipfsHash = "QmTest";

            await truthBounty.transfer(addr1.address, rewardAmount);
            await truthBounty.connect(addr1).createBounty(ipfsHash, rewardAmount);

            await truthBounty.resolveBounty(0, addr2.address);

            const bounty = await truthBounty.bounties(0);
            expect(bounty.resolved).to.be.true;
            expect(bounty.verifier).to.equal(addr2.address);
            expect(await truthBounty.balanceOf(addr2.address)).to.equal(rewardAmount);
        });

        it("Should fail if non-owner tries to resolve a bounty", async function () {
            const rewardAmount = ethers.parseEther("100");
            await truthBounty.transfer(addr1.address, rewardAmount);
            await truthBounty.connect(addr1).createBounty("QmTest", rewardAmount);

            await expect(truthBounty.connect(addr1).resolveBounty(0, addr2.address)).to.be.revertedWithCustomError(truthBounty, "OwnableUnauthorizedAccount");
        });
    });
});
