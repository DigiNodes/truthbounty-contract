import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("TruthBountyToken Legacy & Role Tests", function () {
    let token: Contract;
    let owner: Signer;
    let addr1: Signer;
    let addr2: Signer;

    const INITIAL_SUPPLY = ethers.parseEther("10000000");

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        const TruthBountyTokenFactory = await ethers.getContractFactory("TruthBountyToken");
        token = await TruthBountyTokenFactory.deploy(await owner.getAddress());
        await token.waitForDeployment();
    });

    describe("Deployment", function () {
        it("Should assign the total supply of tokens to the owner", async function () {
            const ownerBalance = await token.balanceOf(await owner.getAddress());
            expect(await token.totalSupply()).to.equal(ownerBalance);
            expect(ownerBalance).to.equal(INITIAL_SUPPLY);
        });

        it("Should set correct name and symbol", async function () {
            expect(await token.name()).to.equal("TruthBounty");
            expect(await token.symbol()).to.equal("BOUNTY");
        });

        it("Should set correct roles for the admin", async function () {
            const DEFAULT_ADMIN_ROLE = await token.DEFAULT_ADMIN_ROLE();
            const ADMIN_ROLE = await token.ADMIN_ROLE();
            expect(await token.hasRole(DEFAULT_ADMIN_ROLE, await owner.getAddress())).to.be.true;
            expect(await token.hasRole(ADMIN_ROLE, await owner.getAddress())).to.be.true;
        });
    });

    describe("Legacy Staking Mechanism (Deprecated)", function () {
        it("Should allow users to stake tokens legacy way", async function () {
            const stakeAmount = ethers.parseEther("100");
            await token.transfer(await addr1.getAddress(), stakeAmount);
            await token.connect(addr1).approve(await token.getAddress(), stakeAmount);
            
            await expect(token.connect(addr1).stake(stakeAmount))
                .to.emit(token, "StakeDeposited")
                .withArgs(await addr1.getAddress(), stakeAmount);

            expect(await token.verifierStake(await addr1.getAddress())).to.equal(stakeAmount);
            expect(await token.balanceOf(await addr1.getAddress())).to.equal(0);
        });

        it("Should allow users to unstake tokens legacy way", async function () {
            const stakeAmount = ethers.parseEther("100");
            await token.transfer(await addr1.getAddress(), stakeAmount);
            await token.connect(addr1).approve(await token.getAddress(), stakeAmount);
            await token.connect(addr1).stake(stakeAmount);

            await expect(token.connect(addr1).withdrawStake(stakeAmount))
                .to.emit(token, "StakeWithdrawn")
                .withArgs(await addr1.getAddress(), stakeAmount);

            expect(await token.verifierStake(await addr1.getAddress())).to.equal(0);
            expect(await token.balanceOf(await addr1.getAddress())).to.equal(stakeAmount);
        });

        it("Should fail if unstaking more than staked legacy way", async function () {
            const stakeAmount = ethers.parseEther("100");
            await expect(token.connect(addr1).withdrawStake(stakeAmount)).to.be.revertedWith("Insufficient stake");
        });
    });
});
