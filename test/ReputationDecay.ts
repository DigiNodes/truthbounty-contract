import {
    time,
    loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre from "hardhat";

describe("ReputationDecay", function () {
    const ONE_DAY = 24 * 60 * 60;
    const ONE_WEEK = 7 * ONE_DAY;
    const BASIS_POINTS = 10000;

    async function deployReputationDecayFixture() {
        const [owner, user1, user2, otherAccount, oracle] = await hre.ethers.getSigners();

        const ReputationDecay = await hre.ethers.getContractFactory("ReputationDecay");
        const reputationDecay = await ReputationDecay.deploy(owner.address);

        const ORACLE_ROLE = await reputationDecay.ORACLE_ROLE();
        await reputationDecay.grantRole(ORACLE_ROLE, oracle.address);

        return { reputationDecay, owner, user1, user2, otherAccount, oracle, ORACLE_ROLE };
    }

    describe("Deployment", function () {
        it("Should set the correct admin", async function () {
            const { reputationDecay, owner } = await loadFixture(deployReputationDecayFixture);
            expect(await reputationDecay.hasRole(await reputationDecay.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;
        });

        it("Should initialize with default decay config", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            const config = await reputationDecay.decayConfig();
            expect(config.decayInterval).to.equal(ONE_WEEK);
            expect(config.decayPercentage).to.equal(100);
            expect(config.minimumReputation).to.equal(1);
            expect(config.enabled).to.equal(true);
        });

        it("Should set up ORACLE_ROLE correctly", async function () {
            const { reputationDecay, owner } = await loadFixture(deployReputationDecayFixture);
            const ORACLE_ROLE = await reputationDecay.ORACLE_ROLE();
            expect(await reputationDecay.hasRole(ORACLE_ROLE, owner.address)).to.be.true;
        });
    });

    describe("Reputation Management", function () {
        it("Should set reputation correctly", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);
            expect(await reputationDecay.baseReputation(user1.address)).to.equal(1000);
        });

        it("Should emit ReputationUpdated event when setting reputation", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.setReputation(user1.address, 1000))
                .to.emit(reputationDecay, "ReputationUpdated")
                .withArgs(user1.address, 0, 1000, await time.latest() + 1);
        });

        it("Should add reputation correctly", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);
            await reputationDecay.addReputation(user1.address, 500);

            expect(await reputationDecay.baseReputation(user1.address)).to.equal(1500);
        });

        it("Should deduct reputation correctly", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);
            await reputationDecay.deductReputation(user1.address, 300);

            expect(await reputationDecay.baseReputation(user1.address)).to.equal(700);
        });

        it("Should not go below zero when deducting more than balance", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 100);
            await reputationDecay.deductReputation(user1.address, 500);

            expect(await reputationDecay.baseReputation(user1.address)).to.equal(0);
        });

        it("Should update last activity timestamp when setting reputation", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);
            const timestamp = await time.latest();

            expect(await reputationDecay.lastActivityTimestamp(user1.address)).to.equal(timestamp);
        });

        it("Should update inactivity tracking when recording activity", async function () {
            const { reputationDecay, user1, oracle } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.connect(oracle).recordActivity(user1.address);

            const tracking = await reputationDecay.inactivityTracking(user1.address);
            expect(tracking.lastActiveBlock).to.be.gt(0);
            expect(tracking.lastVerificationTimestamp).to.equal(await time.latest());
            expect(tracking.lastSuccessfulVerification).to.equal(await time.latest());
        });

        it("Should record activity and emit event", async function () {
            const { reputationDecay, user1, oracle } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.connect(oracle).recordActivity(user1.address))
                .to.emit(reputationDecay, "ActivityRecorded");
        });

        it("Should batch record activity", async function () {
            const { reputationDecay, user1, user2, oracle } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.connect(oracle).recordActivityBatch([user1.address, user2.address]);

            expect(await reputationDecay.lastActivityTimestamp(user1.address)).to.be.gt(0);
            expect(await reputationDecay.lastActivityTimestamp(user2.address)).to.be.gt(0);
        });
    });

    describe("Decay Calculation", function () {
        it("Should return full reputation before decay interval", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(1000);
        });

        it("Should return full reputation at the moment decay interval starts", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            await time.increase(ONE_WEEK - 1);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(1000);
        });

        it("Should apply 1% decay after one interval", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            await time.increase(ONE_WEEK);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(990);
        });

        it("Should apply 5% decay after five intervals", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            await time.increase(5 * ONE_WEEK);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(950);
        });

        it("Should cap decay at minimum reputation", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            await time.increase(200 * ONE_WEEK);

            const effective = await reputationDecay.getEffectiveReputation(user1.address);
            expect(effective).to.equal(1);
        });

        it("Should reset decay when activity is recorded", async function () {
            const { reputationDecay, user1, oracle } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            await time.increase(2 * ONE_WEEK);
            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(980);

            await reputationDecay.connect(oracle).recordActivity(user1.address);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(1000);
        });

        it("Should return zero for user with no reputation", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(0);
        });

        it("Should respect minimum reputation floor", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 10);

            await time.increase(100 * ONE_WEEK);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(1);
        });

        it("Should return full reputation when decay is disabled", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            await reputationDecay.setDecayConfig({
                decayInterval: ONE_WEEK,
                decayPercentage: 100,
                minimumReputation: 1,
                enabled: false
            });

            await time.increase(10 * ONE_WEEK);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(1000);
        });
    });

    describe("applyDecay", function () {
        it("Should apply decay and emit ReputationDecayed event", async function () {
            const { reputationDecay, user1, oracle } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);
            await time.increase(5 * ONE_WEEK);

            await expect(reputationDecay.connect(oracle).applyDecay(user1.address))
                .to.emit(reputationDecay, "ReputationDecayed")
                .withArgs(user1.address, 1000, 950);
        });

        it("Should update base reputation after applyDecay", async function () {
            const { reputationDecay, user1, oracle } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);
            await time.increase(5 * ONE_WEEK);

            await reputationDecay.connect(oracle).applyDecay(user1.address);

            expect(await reputationDecay.baseReputation(user1.address)).to.equal(950);
        });

        it("Should not emit event if no decay is needed", async function () {
            const { reputationDecay, user1, oracle } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            await expect(reputationDecay.connect(oracle).applyDecay(user1.address))
                .to.not.emit(reputationDecay, "ReputationDecayed");
        });
    });

    describe("View Functions", function () {
        it("calculateDecay should return correct amount", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);
            await time.increase(5 * ONE_WEEK);

            expect(await reputationDecay.calculateDecay(user1.address)).to.equal(50);
        });

        it("calculateDecay should return 0 when no decay", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            expect(await reputationDecay.calculateDecay(user1.address)).to.equal(0);
        });

        it("isDecayRequired should return true when decay interval has passed", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);
            await time.increase(ONE_WEEK);

            expect(await reputationDecay.isDecayRequired(user1.address)).to.equal(true);
        });

        it("isDecayRequired should return false when decay is not due", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            expect(await reputationDecay.isDecayRequired(user1.address)).to.equal(false);
        });

        it("nextDecayTimestamp should return correct timestamp", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);
            const timestamp = await time.latest();

            expect(await reputationDecay.nextDecayTimestamp(user1.address)).to.equal(timestamp + ONE_WEEK);
        });

        it("nextDecayTimestamp should return max uint for unknown user", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            const max = hre.ethers.MaxUint256;
            expect(await reputationDecay.nextDecayTimestamp(user1.address)).to.equal(max);
        });
    });

    describe("IReputationOracle Interface", function () {
        it("getReputationScore should return effective reputation", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);
            await time.increase(5 * ONE_WEEK);

            expect(await reputationDecay.getReputationScore(user1.address)).to.equal(950);
        });

        it("isActive should return decay enabled state", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            expect(await reputationDecay.isActive()).to.equal(true);

            await reputationDecay.setDecayConfig({
                decayInterval: ONE_WEEK,
                decayPercentage: 100,
                minimumReputation: 1,
                enabled: false
            });

            expect(await reputationDecay.isActive()).to.equal(false);
        });

        it("getLastReputationUpdate should return lastActivityTimestamp", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);
            const timestamp = await time.latest();

            expect(await reputationDecay.getLastReputationUpdate(user1.address)).to.equal(timestamp);
        });
    });

    describe("Independent User Decay", function () {
        it("Should track decay independently for different users", async function () {
            const { reputationDecay, user1, user2 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            await time.increase(3 * ONE_WEEK);

            await reputationDecay.setReputation(user2.address, 1000);

            await time.increase(2 * ONE_WEEK);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(950);
            expect(await reputationDecay.getEffectiveReputation(user2.address)).to.equal(980);
        });
    });

    describe("Governance & Admin Functions", function () {
        it("Should allow admin to update decay config", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setDecayConfig({
                decayInterval: ONE_DAY,
                decayPercentage: 200,
                minimumReputation: 5,
                enabled: true
            });

            const config = await reputationDecay.decayConfig();
            expect(config.decayInterval).to.equal(ONE_DAY);
            expect(config.decayPercentage).to.equal(200);
            expect(config.minimumReputation).to.equal(5);
            expect(config.enabled).to.equal(true);
        });

        it("Should reject decay percentage above 100%", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.setDecayConfig({
                decayInterval: ONE_WEEK,
                decayPercentage: BASIS_POINTS + 1,
                minimumReputation: 1,
                enabled: true
            })).to.be.revertedWithCustomError(reputationDecay, "InvalidDecayPercentage");
        });

        it("Should reject zero decay interval", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.setDecayConfig({
                decayInterval: 0,
                decayPercentage: 100,
                minimumReputation: 1,
                enabled: true
            })).to.be.revertedWithCustomError(reputationDecay, "InvalidDecayInterval");
        });

        it("Should emit DecayConfigUpdated on config update", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.setDecayConfig({
                decayInterval: ONE_DAY,
                decayPercentage: 200,
                minimumReputation: 5,
                enabled: false
            }))
                .to.emit(reputationDecay, "DecayConfigUpdated")
                .withArgs(ONE_DAY, 200, 5, false);
        });

        it("Should allow disabling decay via config", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            await reputationDecay.setDecayConfig({
                decayInterval: ONE_WEEK,
                decayPercentage: 100,
                minimumReputation: 1,
                enabled: false
            });

            await time.increase(10 * ONE_WEEK);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(1000);
        });
    });

    describe("Access Control", function () {
        it("Should reject non-oracle from setting reputation", async function () {
            const { reputationDecay, user1, otherAccount } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.connect(otherAccount).setReputation(user1.address, 1000))
                .to.be.revertedWithCustomError(reputationDecay, "AccessControlUnauthorizedAccount");
        });

        it("Should reject non-oracle from recording activity", async function () {
            const { reputationDecay, user1, otherAccount } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.connect(otherAccount).recordActivity(user1.address))
                .to.be.revertedWithCustomError(reputationDecay, "AccessControlUnauthorizedAccount");
        });

        it("Should reject non-admin from updating config", async function () {
            const { reputationDecay, otherAccount } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.connect(otherAccount).setDecayConfig({
                decayInterval: ONE_DAY,
                decayPercentage: 200,
                minimumReputation: 5,
                enabled: true
            })).to.be.revertedWithCustomError(reputationDecay, "UnauthorizedGovernance");
        });

        it("Should reject non-oracle from applying decay", async function () {
            const { reputationDecay, user1, otherAccount } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.connect(otherAccount).applyDecay(user1.address))
                .to.be.revertedWithCustomError(reputationDecay, "AccessControlUnauthorizedAccount");
        });
    });

    describe("Edge Cases", function () {
        it("Should handle very large reputation values", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            const largeValue = hre.ethers.parseEther("1000000000");
            await reputationDecay.setReputation(user1.address, largeValue);

            await time.increase(5 * ONE_WEEK);

            const expected = (largeValue * BigInt(95)) / BigInt(100);
            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(expected);
        });

        it("Should work with custom decay parameters", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setDecayConfig({
                decayInterval: ONE_DAY,
                decayPercentage: 500,
                minimumReputation: 1,
                enabled: true
            });

            await reputationDecay.setReputation(user1.address, 1000);

            await time.increase(3 * ONE_DAY);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(850);
        });

        it("Should not decay below custom minimum reputation", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setDecayConfig({
                decayInterval: ONE_DAY,
                decayPercentage: 2000,
                minimumReputation: 100,
                enabled: true
            });

            await reputationDecay.setReputation(user1.address, 1000);

            await time.increase(10 * ONE_DAY);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(100);
        });

        it("Should return zero for user with zero base reputation", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(0);
            expect(await reputationDecay.calculateDecay(user1.address)).to.equal(0);
            expect(await reputationDecay.isDecayRequired(user1.address)).to.equal(false);
        });
    });
});
