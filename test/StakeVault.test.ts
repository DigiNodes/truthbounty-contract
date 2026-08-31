import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";
import type { StakeVault, MockERC20, MockFailingBondERC20 } from "../typechain-types";

describe("StakeVault", function () {
    const AMOUNT = ethers.parseEther("100");

    async function deployFixture() {
        const [admin, operator, depositor, recipient] = await ethers.getSigners();

        const MockERC20Factory = await ethers.getContractFactory("MockERC20");
        const token = (await MockERC20Factory.deploy("Bounty", "BOUNTY")) as MockERC20;
        await token.waitForDeployment();

        const StakeVaultFactory = await ethers.getContractFactory("StakeVault");
        const vault = (await StakeVaultFactory.deploy(admin.address, await token.getAddress())) as StakeVault;
        await vault.waitForDeployment();

        const OPERATOR_ROLE = await vault.OPERATOR_ROLE();
        await vault.connect(admin).grantRole(OPERATOR_ROLE, operator.address);

        // Fund the depositor so it can post the bond.
        await token.mint(depositor.address, ethers.parseEther("1000"));
        await token.connect(depositor).approve(await vault.getAddress(), ethers.MaxUint256);

        return { vault, token, admin, operator, depositor, recipient };
    }

    describe("Deployment", function () {
        it("sets the initial bond token", async function () {
            const { vault, token } = await loadFixture(deployFixture);
            expect(await vault.bondToken()).to.equal(await token.getAddress());
        });

        it("starts with zero locked total", async function () {
            const { vault } = await loadFixture(deployFixture);
            expect(await vault.totalLocked()).to.equal(0n);
        });
    });

    describe("lockBond", function () {
        it("vaults the token and records the lock", async function () {
            const { vault, token, operator, depositor } = await loadFixture(deployFixture);
            const vaultBefore = await token.balanceOf(await vault.getAddress());

            await expect(vault.connect(operator).lockBond(1, await token.getAddress(), depositor.address, AMOUNT))
                .to.emit(vault, "BondLocked")
                .withArgs(1, await token.getAddress(), depositor.address, AMOUNT, operator.address);

            expect(await token.balanceOf(await vault.getAddress())).to.equal(vaultBefore + AMOUNT);
            expect(await vault.totalLocked()).to.equal(AMOUNT);

            const lock = await vault.getLock(1);
            expect(lock.lockId).to.equal(1n);
            expect(lock.token).to.equal(await token.getAddress());
            expect(lock.depositor).to.equal(depositor.address);
            expect(lock.amount).to.equal(AMOUNT);
            expect(lock.released).to.equal(false);
        });

        it("reverts for a non-operator", async function () {
            const { vault, token, depositor } = await loadFixture(deployFixture);
            const [caller] = await ethers.getSigners();
            await expect(vault.connect(caller).lockBond(1, await token.getAddress(), depositor.address, AMOUNT))
                .to.be.revertedWithCustomError(vault, "AccessControlUnauthorizedAccount");
        });

        it("reverts on a duplicate lock id", async function () {
            const { vault, token, operator, depositor } = await loadFixture(deployFixture);
            await vault.connect(operator).lockBond(1, await token.getAddress(), depositor.address, AMOUNT);
            await expect(vault.connect(operator).lockBond(1, await token.getAddress(), depositor.address, AMOUNT))
                .to.be.revertedWithCustomError(vault, "LockAlreadyExists");
        });

        it("with a failing transfer token reverts and records nothing", async function () {
            const { vault, admin, operator, depositor } = await loadFixture(deployFixture);
            const FailingFactory = await ethers.getContractFactory("MockFailingBondERC20");
            const failing = (await FailingFactory.deploy()) as MockFailingBondERC20;
            await failing.waitForDeployment();

            await vault.connect(admin).setBondToken(await failing.getAddress());
            await failing.mint(depositor.address, AMOUNT);
            await failing.connect(depositor).approve(await vault.getAddress(), ethers.MaxUint256);

            await expect(vault.connect(operator).lockBond(2, await failing.getAddress(), depositor.address, ethers.parseEther("1")))
                .to.be.reverted;

            // No partial ledger entry.
            const lock = await vault.getLock(2);
            expect(lock.lockId).to.equal(0n);
            expect(await vault.totalLocked()).to.equal(0n);
        });
    });

    describe("releaseBond", function () {
        it("releases to the recipient and removes the lock from the ledger", async function () {
            const { vault, token, operator, depositor, recipient } = await loadFixture(deployFixture);
            const recipientBefore = await token.balanceOf(recipient.address);

            await vault.connect(operator).lockBond(1, await token.getAddress(), depositor.address, AMOUNT);

            await expect(vault.connect(operator).releaseBond(1, recipient.address))
                .to.emit(vault, "BondReleased")
                .withArgs(1, recipient.address, AMOUNT, operator.address);

            expect(await token.balanceOf(recipient.address)).to.equal(recipientBefore + AMOUNT);
            expect(await vault.totalLocked()).to.equal(0n);

            const lock = await vault.getLock(1);
            expect(lock.released).to.equal(true);
            expect(lock.releasedTo).to.equal(recipient.address);
        });

        it("reverts when releasing a non-existent lock", async function () {
            const { vault, operator, recipient } = await loadFixture(deployFixture);
            await expect(vault.connect(operator).releaseBond(99, recipient.address))
                .to.be.revertedWithCustomError(vault, "LockNotFound");
        });

        it("reverts when releasing an already-released lock", async function () {
            const { vault, token, operator, depositor, recipient } = await loadFixture(deployFixture);
            await vault.connect(operator).lockBond(1, await token.getAddress(), depositor.address, AMOUNT);
            await vault.connect(operator).releaseBond(1, recipient.address);
            await expect(vault.connect(operator).releaseBond(1, recipient.address))
                .to.be.revertedWithCustomError(vault, "LockAlreadyReleased");
        });

        it("reverts for a non-operator", async function () {
            const { vault, token, operator, depositor, recipient } = await loadFixture(deployFixture);
            await vault.connect(operator).lockBond(1, await token.getAddress(), depositor.address, AMOUNT);
            await expect(vault.connect(depositor).releaseBond(1, recipient.address))
                .to.be.revertedWithCustomError(vault, "AccessControlUnauthorizedAccount");
        });
    });

    describe("ledger reconciliation", function () {
        it("totalLocked reconciles across multiple locks and releases", async function () {
            const { vault, token, operator, depositor, recipient } = await loadFixture(deployFixture);
            await token.mint(depositor.address, ethers.parseEther("5000"));

            for (let i = 1; i <= 5; i++) {
                await vault.connect(operator).lockBond(i, await token.getAddress(), depositor.address, ethers.parseEther("10"));
            }
            expect(await vault.totalLocked()).to.equal(ethers.parseEther("50"));

            await vault.connect(operator).releaseBond(2, recipient.address);
            await vault.connect(operator).releaseBond(5, recipient.address);
            expect(await vault.totalLocked()).to.equal(ethers.parseEther("30"));
        });
    });
});
