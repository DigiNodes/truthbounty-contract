import {
    time,
    loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre from "hardhat";

describe("ReputationDecay", function () {
    // Constants matching contract defaults
    const ONE_DAY = 24 * 60 * 60;
    const ONE_WEEK = 7 * ONE_DAY;
    const FOUR_WEEKS = 4 * ONE_WEEK;
    const BASIS_POINTS = 10000;

    async function deployReputationDecayFixture() {
        const [owner, user1, user2, otherAccount] = await hre.ethers.getSigners();

        const ReputationDecay = await hre.ethers.getContractFactory("ReputationDecay");
        const reputationDecay = await ReputationDecay.deploy();

        return { reputationDecay, owner, user1, user2, otherAccount };
    }

    describe("Deployment", function () {
        it("Should set the correct owner", async function () {
            const { reputationDecay, owner } = await loadFixture(deployReputationDecayFixture);
            expect(await reputationDecay.owner()).to.equal(owner.address);
        });

        it("Should initialize with default decay parameters", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            expect(await reputationDecay.decayRatePerEpoch()).to.equal(100); // 1%
            expect(await reputationDecay.epochDuration()).to.equal(ONE_WEEK);
            expect(await reputationDecay.inactivityThreshold()).to.equal(4);
            expect(await reputationDecay.maxDecayPercent()).to.equal(5000); // 50%
        });

        it("Should return correct decay parameters via getter", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            const [rate, duration, threshold, maxDecay] = await reputationDecay.getDecayParameters();
            expect(rate).to.equal(100);
            expect(duration).to.equal(ONE_WEEK);
            expect(threshold).to.equal(4);
            expect(maxDecay).to.equal(5000);
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

        it("Should record activity and emit event", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.recordActivity(user1.address))
                .to.emit(reputationDecay, "ActivityRecorded");
        });
    });

    describe("Decay Calculation", function () {
        it("Should return full reputation within grace period", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            // Move 3 weeks forward (still within 4-week grace period)
            await time.increase(3 * ONE_WEEK);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(1000);
        });

        it("Should return full reputation exactly at grace period boundary", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            // Move exactly 4 weeks forward
            await time.increase(FOUR_WEEKS);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(1000);
        });

        it("Should apply 1% decay after 5 epochs of inactivity", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            // Move 5 weeks forward (1 week past grace period = 1% decay)
            await time.increase(5 * ONE_WEEK);

            // 1000 * 99% = 990
            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(990);
        });

        it("Should apply 5% decay after 9 epochs of inactivity", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            // Move 9 weeks forward (5 weeks past grace period = 5% decay)
            await time.increase(9 * ONE_WEEK);

            // 1000 * 95% = 950
            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(950);
        });

        it("Should cap decay at maximum (50%)", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            // Move 100 weeks forward (way past max decay)
            await time.increase(100 * ONE_WEEK);

            // Should be capped at 50% decay = 500
            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(500);
        });

        it("Should reset decay when activity is recorded", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            // Move 6 weeks forward (2% decay)
            await time.increase(6 * ONE_WEEK);
            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(980);

            // Record activity to reset timer
            await reputationDecay.recordActivity(user1.address);

            // Decay should be reset
            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(1000);
        });

        it("Should return zero for user with no reputation", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(0);
        });

        it("Should correctly report decay amount", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            // Move 5 weeks forward (1% decay)
            await time.increase(5 * ONE_WEEK);

            expect(await reputationDecay.getDecayAmount(user1.address)).to.equal(10);
        });

        it("Should correctly report if user is decaying", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setReputation(user1.address, 1000);

            // Initially not decaying
            expect(await reputationDecay.isUserDecaying(user1.address)).to.equal(false);

            // Move past grace period
            await time.increase(5 * ONE_WEEK);

            expect(await reputationDecay.isUserDecaying(user1.address)).to.equal(true);
        });
    });

    describe("Independent User Decay", function () {
        it("Should track decay independently for different users", async function () {
            const { reputationDecay, user1, user2 } = await loadFixture(deployReputationDecayFixture);

            // Set reputation for user1
            await reputationDecay.setReputation(user1.address, 1000);

            // Wait 3 weeks
            await time.increase(3 * ONE_WEEK);

            // Set reputation for user2
            await reputationDecay.setReputation(user2.address, 1000);

            // Wait 2 more weeks (user1: 5 weeks total, user2: 2 weeks)
            await time.increase(2 * ONE_WEEK);

            // user1 should have 1% decay, user2 should have none
            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(990);
            expect(await reputationDecay.getEffectiveReputation(user2.address)).to.equal(1000);
        });
    });

    describe("Admin Functions", function () {
        it("Should allow owner to update decay rate", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setDecayRatePerEpoch(200); // 2%
            expect(await reputationDecay.decayRatePerEpoch()).to.equal(200);
        });

        it("Should reject decay rate above 100%", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.setDecayRatePerEpoch(10001))
                .to.be.revertedWithCustomError(reputationDecay, "InvalidDecayRate");
        });

        it("Should allow owner to update epoch duration", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setEpochDuration(ONE_DAY); // 1 day
            expect(await reputationDecay.epochDuration()).to.equal(ONE_DAY);
        });

        it("Should reject zero epoch duration", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.setEpochDuration(0))
                .to.be.revertedWithCustomError(reputationDecay, "InvalidEpochDuration");
        });

        it("Should allow owner to update inactivity threshold", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setInactivityThreshold(2);
            expect(await reputationDecay.inactivityThreshold()).to.equal(2);
        });

        it("Should allow owner to update max decay percent", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            await reputationDecay.setMaxDecayPercent(7500); // 75%
            expect(await reputationDecay.maxDecayPercent()).to.equal(7500);
        });

        it("Should reject max decay above 100%", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.setMaxDecayPercent(10001))
                .to.be.revertedWithCustomError(reputationDecay, "InvalidMaxDecayPercent");
        });

        it("Should emit DecayParametersUpdated on parameter changes", async function () {
            const { reputationDecay } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.setDecayRatePerEpoch(200))
                .to.emit(reputationDecay, "DecayParametersUpdated")
                .withArgs(200, ONE_WEEK, 4, 5000);
        });
    });

    describe("Access Control", function () {
        it("Should reject non-owner from setting reputation", async function () {
            const { reputationDecay, user1, otherAccount } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.connect(otherAccount).setReputation(user1.address, 1000))
                .to.be.revertedWithCustomError(reputationDecay, "OwnableUnauthorizedAccount");
        });

        it("Should reject non-owner from recording activity", async function () {
            const { reputationDecay, user1, otherAccount } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.connect(otherAccount).recordActivity(user1.address))
                .to.be.revertedWithCustomError(reputationDecay, "OwnableUnauthorizedAccount");
        });

        it("Should reject non-owner from updating parameters", async function () {
            const { reputationDecay, otherAccount } = await loadFixture(deployReputationDecayFixture);

            await expect(reputationDecay.connect(otherAccount).setDecayRatePerEpoch(200))
                .to.be.revertedWithCustomError(reputationDecay, "OwnableUnauthorizedAccount");
        });
    });

    describe("Edge Cases", function () {
        it("Should handle very large reputation values", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            const largeValue = hre.ethers.parseEther("1000000000"); // 1 billion tokens
            await reputationDecay.setReputation(user1.address, largeValue);

            await time.increase(5 * ONE_WEEK);

            // 1% decay
            const expected = (largeValue * BigInt(99)) / BigInt(100);
            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(expected);
        });

        it("Should work with custom decay parameters", async function () {
            const { reputationDecay, user1 } = await loadFixture(deployReputationDecayFixture);

            // Set 5% decay per day, 2 day grace, 80% max
            await reputationDecay.setDecayRatePerEpoch(500); // 5%
            await reputationDecay.setEpochDuration(ONE_DAY);
            await reputationDecay.setInactivityThreshold(2);
            await reputationDecay.setMaxDecayPercent(8000); // 80%

            await reputationDecay.setReputation(user1.address, 1000);

            // After 4 days (2 past grace) = 10% decay
            await time.increase(4 * ONE_DAY);

            expect(await reputationDecay.getEffectiveReputation(user1.address)).to.equal(900);
        });
    });
});
