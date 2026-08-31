import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";

describe("ClaimLifecycle", function () {
    async function deployLifecycleFixture() {
        const [deployer, other] = await ethers.getSigners();
        const Wrapper = await ethers.getContractFactory("ClaimLifecycleTestWrapper");
        const lifecycle = await Wrapper.deploy();
        return { lifecycle, deployer, other };
    }

    function statusEnum() {
        return {
            Pending: 0,
            UnderVerification: 1,
            VerificationEnded: 2,
            UnderDispute: 3,
            VerifiedTrue: 4,
            VerifiedFalse: 5,
            Inconclusive: 6,
            Cancelled: 7,
        };
    }

    describe("_canTransition - Valid Transitions", function () {
        it("should allow Pending → UnderVerification", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.Pending, S.UnderVerification)).to.be.true;
        });

        it("should allow Pending → Cancelled", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.Pending, S.Cancelled)).to.be.true;
        });

        it("should allow UnderVerification → VerificationEnded", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.UnderVerification, S.VerificationEnded)).to.be.true;
        });

        it("should allow VerificationEnded → VerifiedTrue", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.VerificationEnded, S.VerifiedTrue)).to.be.true;
        });

        it("should allow VerificationEnded → VerifiedFalse", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.VerificationEnded, S.VerifiedFalse)).to.be.true;
        });

        it("should allow VerificationEnded → Inconclusive", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.VerificationEnded, S.Inconclusive)).to.be.true;
        });

        it("should allow VerificationEnded → UnderDispute", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.VerificationEnded, S.UnderDispute)).to.be.true;
        });

        it("should allow UnderDispute → VerifiedTrue", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.UnderDispute, S.VerifiedTrue)).to.be.true;
        });

        it("should allow UnderDispute → VerifiedFalse", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.UnderDispute, S.VerifiedFalse)).to.be.true;
        });

        it("should allow UnderDispute → Inconclusive", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.UnderDispute, S.Inconclusive)).to.be.true;
        });
    });

    describe("_canTransition - Invalid Transitions", function () {
        it("should reject Pending → VerifiedTrue", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.Pending, S.VerifiedTrue)).to.be.false;
        });

        it("should reject Pending → VerifiedFalse", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.Pending, S.VerifiedFalse)).to.be.false;
        });

        it("should reject Pending → UnderDispute", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.Pending, S.UnderDispute)).to.be.false;
        });

        it("should reject Pending → VerificationEnded", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.Pending, S.VerificationEnded)).to.be.false;
        });

        it("should reject Pending → Inconclusive", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.Pending, S.Inconclusive)).to.be.false;
        });

        it("should reject VerifiedTrue → any state", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.VerifiedTrue, S.Pending)).to.be.false;
            expect(await lifecycle.canTransition(S.VerifiedTrue, S.UnderVerification)).to.be.false;
            expect(await lifecycle.canTransition(S.VerifiedTrue, S.VerificationEnded)).to.be.false;
            expect(await lifecycle.canTransition(S.VerifiedTrue, S.UnderDispute)).to.be.false;
            expect(await lifecycle.canTransition(S.VerifiedTrue, S.Inconclusive)).to.be.false;
            expect(await lifecycle.canTransition(S.VerifiedTrue, S.Cancelled)).to.be.false;
        });

        it("should reject VerifiedFalse → any state", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.VerifiedFalse, S.Pending)).to.be.false;
            expect(await lifecycle.canTransition(S.VerifiedFalse, S.UnderVerification)).to.be.false;
        });

        it("should reject Inconclusive → any state", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.Inconclusive, S.Pending)).to.be.false;
            expect(await lifecycle.canTransition(S.Inconclusive, S.UnderVerification)).to.be.false;
        });

        it("should reject Cancelled → any state", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            for (let s = 0; s <= 7; s++) {
                if (s === S.Cancelled) continue;
                expect(await lifecycle.canTransition(S.Cancelled, s)).to.be.false;
            }
        });

        it("should reject UnderVerification → skip states", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.canTransition(S.UnderVerification, S.VerifiedTrue)).to.be.false;
            expect(await lifecycle.canTransition(S.UnderVerification, S.UnderDispute)).to.be.false;
            expect(await lifecycle.canTransition(S.UnderVerification, S.Pending)).to.be.false;
        });
    });

    describe("validateTransition", function () {
        it("should revert on invalid transition", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            await expect(
                lifecycle.validateTransition(S.Pending, S.VerifiedTrue)
            ).to.be.revertedWithCustomError(lifecycle, "InvalidStateTransition");
        });

        it("should not revert on valid transition", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            await expect(
                lifecycle.validateTransition(S.Pending, S.UnderVerification)
            ).to.not.be.reverted;
        });
    });

    describe("Full Lifecycle Transitions", function () {
        it("should execute Pending → UnderVerification → VerificationEnded → VerifiedTrue", async function () {
            const { lifecycle, deployer } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            const now = await time.latest();
            const deadline = now + 1000;
            const windowEnd = now + 2000;

            await lifecycle.startVerification(1, deadline, windowEnd);
            expect(await lifecycle.getClaimStatus(1)).to.equal(S.UnderVerification);

            await time.increaseTo(windowEnd + 1);
            await lifecycle.endVerification(1);
            expect(await lifecycle.getClaimStatus(1)).to.equal(S.VerificationEnded);

            await lifecycle.markVerifiedTrue(1);
            expect(await lifecycle.getClaimStatus(1)).to.equal(S.VerifiedTrue);
        });

        it("should execute Pending → UnderVerification → VerificationEnded → VerifiedFalse", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            const now = await time.latest();
            const deadline = now + 1000;
            const windowEnd = now + 2000;

            await lifecycle.startVerification(2, deadline, windowEnd);
            await time.increaseTo(windowEnd + 1);
            await lifecycle.endVerification(2);
            await lifecycle.markVerifiedFalse(2);
            expect(await lifecycle.getClaimStatus(2)).to.equal(S.VerifiedFalse);
        });

        it("should execute Pending → UnderVerification → VerificationEnded → Inconclusive", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            const now = await time.latest();
            const deadline = now + 1000;
            const windowEnd = now + 2000;

            await lifecycle.startVerification(3, deadline, windowEnd);
            await time.increaseTo(windowEnd + 1);
            await lifecycle.endVerification(3);
            await lifecycle.markInconclusive(3);
            expect(await lifecycle.getClaimStatus(3)).to.equal(S.Inconclusive);
        });

        it("should execute Pending → UnderVerification → VerificationEnded → UnderDispute → VerifiedTrue", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            const now = await time.latest();
            const deadline = now + 1000;
            const windowEnd = now + 2000;

            await lifecycle.startVerification(4, deadline, windowEnd);
            await time.increaseTo(windowEnd + 1);
            await lifecycle.endVerification(4);

            const disputeDeadline = (await time.latest()) + 1000;
            await lifecycle.openDispute(4, disputeDeadline);
            expect(await lifecycle.getClaimStatus(4)).to.equal(S.UnderDispute);

            await lifecycle.markVerifiedTrue(4);
            expect(await lifecycle.getClaimStatus(4)).to.equal(S.VerifiedTrue);
        });

        it("should execute Pending → Cancelled", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            await lifecycle.cancelClaim(5);
            expect(await lifecycle.getClaimStatus(5)).to.equal(S.Cancelled);
        });
    });

    describe("Event Emission", function () {
        it("should emit ClaimStatusChanged on startVerification", async function () {
            const { lifecycle, deployer } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            const S = statusEnum();
            await expect(lifecycle.startVerification(10, now + 1000, now + 2000))
                .to.emit(lifecycle, "ClaimStatusChanged")
                .withArgs(10, S.Pending, S.UnderVerification, deployer.address);
        });

        it("should emit ClaimStatusChanged on endVerification", async function () {
            const { lifecycle, deployer } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            const windowEnd = now + 10;
            await lifecycle.startVerification(11, now + 1000, windowEnd);

            await time.increaseTo(windowEnd + 1);
            const S = statusEnum();
            await expect(lifecycle.endVerification(11))
                .to.emit(lifecycle, "ClaimStatusChanged")
                .withArgs(11, S.UnderVerification, S.VerificationEnded, deployer.address);
        });

        it("should emit ClaimStatusChanged on markVerifiedTrue", async function () {
            const { lifecycle, deployer } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            await lifecycle.startVerification(12, now + 1000, now + 10);
            await time.increaseTo(now + 11);
            await lifecycle.endVerification(12);
            const S = statusEnum();
            await expect(lifecycle.markVerifiedTrue(12))
                .to.emit(lifecycle, "ClaimStatusChanged")
                .withArgs(12, S.VerificationEnded, S.VerifiedTrue, deployer.address);
        });

        it("should emit ClaimStatusChanged on cancelClaim", async function () {
            const { lifecycle, deployer } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            await expect(lifecycle.cancelClaim(13))
                .to.emit(lifecycle, "ClaimStatusChanged")
                .withArgs(13, S.Pending, S.Cancelled, deployer.address);
        });

        it("should emit ClaimStatusChanged on openDispute", async function () {
            const { lifecycle, deployer } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            await lifecycle.startVerification(14, now + 1000, now + 10);
            await time.increaseTo(now + 11);
            await lifecycle.endVerification(14);
            const S = statusEnum();
            await expect(lifecycle.openDispute(14, now + 2000))
                .to.emit(lifecycle, "ClaimStatusChanged")
                .withArgs(14, S.VerificationEnded, S.UnderDispute, deployer.address);
        });
    });

    describe("Time-Based Validation", function () {
        it("should reject startVerification after deadline", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            const deadline = now - 1;
            await expect(
                lifecycle.startVerification(20, deadline, now + 1000)
            ).to.be.revertedWithCustomError(lifecycle, "VerificationDeadlinePassed");
        });

        it("should reject endVerification before window ends", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            const windowEnd = now + 1000;
            await lifecycle.startVerification(21, now + 2000, windowEnd);
            await expect(
                lifecycle.endVerification(21)
            ).to.be.revertedWithCustomError(lifecycle, "VerificationWindowNotEnded");
        });

        it("should reject openDispute after deadline", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            await lifecycle.startVerification(22, now + 1000, now + 10);
            await time.increaseTo(now + 11);
            await lifecycle.endVerification(22);
            await expect(
                lifecycle.openDispute(22, now - 1)
            ).to.be.revertedWithCustomError(lifecycle, "DisputeDeadlinePassed");
        });
    });

    describe("View Helpers", function () {
        it("should return correct status from getClaimStatus", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const S = statusEnum();
            expect(await lifecycle.getClaimStatus(30)).to.equal(S.Pending);
        });

        it("isPending should return true for Pending", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            expect(await lifecycle.isPending(31)).to.be.true;
        });

        it("isUnderVerification should return true for UnderVerification", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            await lifecycle.startVerification(32, now + 1000, now + 2000);
            expect(await lifecycle.isUnderVerification(32)).to.be.true;
        });

        it("isResolved should return true for resolved states", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();

            await lifecycle.cancelClaim(33);
            expect(await lifecycle.isResolved(33)).to.be.true;
        });

        it("isDisputed should return true for UnderDispute", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            await lifecycle.startVerification(34, now + 1000, now + 10);
            await time.increaseTo(now + 11);
            await lifecycle.endVerification(34);
            await lifecycle.openDispute(34, now + 2000);
            expect(await lifecycle.isDisputed(34)).to.be.true;
        });

        it("canReceiveVotes should return true only during verification", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();

            expect(await lifecycle.canReceiveVotes(35)).to.be.false;

            await lifecycle.startVerification(35, now + 1000, now + 2000);
            expect(await lifecycle.canReceiveVotes(35)).to.be.true;

            await time.increaseTo(now + 2001);
            await lifecycle.endVerification(35);
            expect(await lifecycle.canReceiveVotes(35)).to.be.false;
        });

        it("canBeCancelled should return true only when Pending", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            expect(await lifecycle.canBeCancelled(36)).to.be.true;

            const now = await time.latest();
            await lifecycle.startVerification(36, now + 1000, now + 2000);
            expect(await lifecycle.canBeCancelled(36)).to.be.false;
        });

        it("getVerificationWindowEnd should return stored value", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            const windowEnd = now + 5000;
            await lifecycle.startVerification(37, now + 1000, windowEnd);
            expect(await lifecycle.getVerificationWindowEnd(37)).to.equal(windowEnd);
        });

        it("getDisputeDeadline should return stored value", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            await lifecycle.startVerification(38, now + 1000, now + 10);
            await time.increaseTo(now + 11);
            await lifecycle.endVerification(38);
            await lifecycle.openDispute(38, now + 3000);
            expect(await lifecycle.getDisputeDeadline(38)).to.equal(now + 3000);
        });
    });

    describe("Gas Benchmarks", function () {
        it("should measure startVerification gas", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            const tx = await lifecycle.startVerification(50, now + 1000, now + 2000);
            const receipt = await tx.wait();
            console.log(`  startVerification gas: ${receipt.gasUsed}`);
        });

        it("should measure endVerification gas", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            await lifecycle.startVerification(51, now + 1000, now + 10);
            await time.increaseTo(now + 11);
            const tx = await lifecycle.endVerification(51);
            const receipt = await tx.wait();
            console.log(`  endVerification gas: ${receipt.gasUsed}`);
        });

        it("should measure markVerifiedTrue gas", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const now = await time.latest();
            await lifecycle.startVerification(52, now + 1000, now + 10);
            await time.increaseTo(now + 11);
            await lifecycle.endVerification(52);
            const tx = await lifecycle.markVerifiedTrue(52);
            const receipt = await tx.wait();
            console.log(`  markVerifiedTrue gas: ${receipt.gasUsed}`);
        });

        it("should measure cancelClaim gas", async function () {
            const { lifecycle } = await loadFixture(deployLifecycleFixture);
            const tx = await lifecycle.cancelClaim(53);
            const receipt = await tx.wait();
            console.log(`  cancelClaim gas: ${receipt.gasUsed}`);
        });
    });
});
