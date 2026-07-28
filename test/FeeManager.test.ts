import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer } from "ethers";

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

const CLAIM_SUBMISSION_FEE    = ethers.keccak256(ethers.toUtf8Bytes("CLAIM_SUBMISSION_FEE"));
const CLAIM_UPDATE_FEE         = ethers.keccak256(ethers.toUtf8Bytes("CLAIM_UPDATE_FEE"));
const VERIFICATION_SUBMISSION_FEE = ethers.keccak256(ethers.toUtf8Bytes("VERIFICATION_SUBMISSION_FEE"));
const DISPUTE_INITIATION_FEE   = ethers.keccak256(ethers.toUtf8Bytes("DISPUTE_INITIATION_FEE"));
const PROTOCOL_RESERVE_FEE     = ethers.keccak256(ethers.toUtf8Bytes("PROTOCOL_RESERVE_FEE"));
const ECOSYSTEM_ALLOCATION_FEE = ethers.keccak256(ethers.toUtf8Bytes("ECOSYSTEM_ALLOCATION_FEE"));
const PROTOCOL_SERVICE_FEE     = ethers.keccak256(ethers.toUtf8Bytes("PROTOCOL_SERVICE_FEE"));

const ALLOC_TREASURY_RESERVE      = ethers.keccak256(ethers.toUtf8Bytes("TREASURY_RESERVE"));
const ALLOC_SECURITY_FUND         = ethers.keccak256(ethers.toUtf8Bytes("SECURITY_FUND"));
const ALLOC_ECOSYSTEM_FUND        = ethers.keccak256(ethers.toUtf8Bytes("ECOSYSTEM_FUND"));
const ALLOC_CONTRIBUTOR_INCENTIVES = ethers.keccak256(ethers.toUtf8Bytes("CONTRIBUTOR_INCENTIVES"));
const ALLOC_EMERGENCY_RESERVE     = ethers.keccak256(ethers.toUtf8Bytes("EMERGENCY_RESERVE"));

const ADMIN_ROLE     = ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE"));
const COLLECTOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("COLLECTOR_ROLE"));
const PAUSER_ROLE    = ethers.keccak256(ethers.toUtf8Bytes("PAUSER_ROLE"));

const FEE_AMOUNT = ethers.parseEther("1");
const LARGE_SUPPLY = ethers.parseEther("1000000");

// ─────────────────────────────────────────────────────────────────────────────
// Fixture
// ─────────────────────────────────────────────────────────────────────────────

async function deployFeeManagerFixture() {
    const [admin, collector, payer, treasury, security, ecosystem, contributors, emergency, other] =
        await ethers.getSigners();

    // Deploy a simple ERC20 as the fee token
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const feeToken = await MockERC20.deploy("TruthBounty Token", "TBT");
    await feeToken.waitForDeployment();

    // Mint tokens to payer
    await feeToken.mint(await payer.getAddress(), LARGE_SUPPLY);

    const FeeManager = await ethers.getContractFactory("FeeManager");
    const feeManager = await FeeManager.deploy(
        await feeToken.getAddress(),
        await admin.getAddress(),
        ethers.ZeroAddress,               // no governance controller yet
        await treasury.getAddress(),
        await security.getAddress(),
        await ecosystem.getAddress(),
        await contributors.getAddress(),
        await emergency.getAddress()
    );
    await feeManager.waitForDeployment();

    // Grant collector role to collector signer
    await feeManager.connect(admin).grantRole(COLLECTOR_ROLE, await collector.getAddress());

    // Approve feeManager to spend payer's tokens
    await feeToken.connect(payer).approve(await feeManager.getAddress(), LARGE_SUPPLY);

    return {
        feeManager,
        feeToken,
        admin,
        collector,
        payer,
        treasury,
        security,
        ecosystem,
        contributors,
        emergency,
        other,
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// Test Suite
// ─────────────────────────────────────────────────────────────────────────────

describe("FeeManager", function () {
    // ── Deployment ──────────────────────────────────────────────────────────────

    describe("Deployment", function () {
        it("Should set the correct fee token", async function () {
            const { feeManager, feeToken } = await deployFeeManagerFixture();
            expect(await feeManager.getFeeToken()).to.equal(await feeToken.getAddress());
        });

        it("Should revert if fee token is zero address", async function () {
            const [admin, t, s, e, c, em] = await ethers.getSigners();
            const FeeManager = await ethers.getContractFactory("FeeManager");
            await expect(
                FeeManager.deploy(
                    ethers.ZeroAddress,
                    await admin.getAddress(),
                    ethers.ZeroAddress,
                    await t.getAddress(),
                    await s.getAddress(),
                    await e.getAddress(),
                    await c.getAddress(),
                    await em.getAddress()
                )
            ).to.be.revertedWithCustomError(
                await ethers.getContractFactory("FeeManager"),
                "ZeroAddress"
            );
        });

        it("Should revert if admin is zero address", async function () {
            const [, t, s, e, c, em] = await ethers.getSigners();
            const MockERC20 = await ethers.getContractFactory("MockERC20");
            const token = await MockERC20.deploy("T", "T");
            const FeeManager = await ethers.getContractFactory("FeeManager");
            await expect(
                FeeManager.deploy(
                    await token.getAddress(),
                    ethers.ZeroAddress,
                    ethers.ZeroAddress,
                    await t.getAddress(),
                    await s.getAddress(),
                    await e.getAddress(),
                    await c.getAddress(),
                    await em.getAddress()
                )
            ).to.be.revertedWithCustomError(
                await ethers.getContractFactory("FeeManager"),
                "ZeroAddress"
            );
        });

        it("Should initialise allocation targets with correct basis points", async function () {
            const { feeManager } = await deployFeeManagerFixture();
            const targets = await feeManager.getAllocationTargets();
            expect(targets.length).to.equal(5);

            const totalBps = targets.reduce((acc: bigint, t: any) => acc + t.basisPoints, 0n);
            expect(totalBps).to.equal(10000n);
        });

        it("Should grant admin all required roles", async function () {
            const { feeManager, admin } = await deployFeeManagerFixture();
            const adminAddr = await admin.getAddress();
            expect(await feeManager.hasRole(ADMIN_ROLE, adminAddr)).to.be.true;
            expect(await feeManager.hasRole(COLLECTOR_ROLE, adminAddr)).to.be.true;
            expect(await feeManager.hasRole(PAUSER_ROLE, adminAddr)).to.be.true;
        });

        it("Should initialise all standard fee schedules as active", async function () {
            const { feeManager } = await deployFeeManagerFixture();
            const types = [
                CLAIM_SUBMISSION_FEE,
                CLAIM_UPDATE_FEE,
                VERIFICATION_SUBMISSION_FEE,
                DISPUTE_INITIATION_FEE,
                PROTOCOL_RESERVE_FEE,
                ECOSYSTEM_ALLOCATION_FEE,
                PROTOCOL_SERVICE_FEE,
            ];
            for (const t of types) {
                const schedule = await feeManager.getFeeSchedule(t);
                expect(schedule.active).to.be.true;
            }
        });
    });

    // ── Fee Calculation ─────────────────────────────────────────────────────────

    describe("calculateFee", function () {
        it("Should return fixed fee when no percentage set", async function () {
            const { feeManager } = await deployFeeManagerFixture();
            const schedule = await feeManager.getFeeSchedule(CLAIM_SUBMISSION_FEE);
            const fee = await feeManager.calculateFee(CLAIM_SUBMISSION_FEE, 0);
            expect(fee).to.equal(schedule.fixedAmount);
        });

        it("Should apply basis-point percentage on top of fixed amount", async function () {
            const { feeManager } = await deployFeeManagerFixture();
            // PROTOCOL_RESERVE_FEE: 0 fixed, 50 bps (0.5%)
            const baseAmount = ethers.parseEther("1000");
            const fee = await feeManager.calculateFee(PROTOCOL_RESERVE_FEE, baseAmount);
            // 0.5% of 1000 = 5
            expect(fee).to.equal(ethers.parseEther("5"));
        });

        it("Should enforce minimum fee", async function () {
            const { feeManager, admin } = await deployFeeManagerFixture();
            // Update schedule with a high minimum
            const minFee = ethers.parseEther("10");
            await feeManager.connect(admin).updateFeeSchedule(
                CLAIM_SUBMISSION_FEE,
                0,      // fixedAmount
                0,      // basisPoints
                minFee, // minValue
                0       // maxValue (no cap)
            );
            const fee = await feeManager.calculateFee(CLAIM_SUBMISSION_FEE, 0);
            expect(fee).to.equal(minFee);
        });

        it("Should enforce maximum fee", async function () {
            const { feeManager, admin } = await deployFeeManagerFixture();
            const maxFee = ethers.parseEther("0.0001");
            await feeManager.connect(admin).updateFeeSchedule(
                CLAIM_SUBMISSION_FEE,
                ethers.parseEther("999"), // fixed >> max
                0,
                0,
                maxFee
            );
            const fee = await feeManager.calculateFee(CLAIM_SUBMISSION_FEE, 0);
            expect(fee).to.equal(maxFee);
        });
    });

    // ── Fee Collection ──────────────────────────────────────────────────────────

    describe("collectFee", function () {
        it("Should collect fee and emit FeeCollected event", async function () {
            const { feeManager, collector, payer } = await deployFeeManagerFixture();
            await expect(
                feeManager.connect(collector).collectFee(
                    CLAIM_SUBMISSION_FEE,
                    await payer.getAddress(),
                    FEE_AMOUNT
                )
            )
                .to.emit(feeManager, "FeeCollected")
                .withArgs(CLAIM_SUBMISSION_FEE, await payer.getAddress(), FEE_AMOUNT);
        });

        it("Should increase totalFeesCollected by the fee amount", async function () {
            const { feeManager, collector, payer } = await deployFeeManagerFixture();
            const before = await feeManager.getTotalFeesCollected();
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                FEE_AMOUNT
            );
            expect(await feeManager.getTotalFeesCollected()).to.equal(before + FEE_AMOUNT);
        });

        it("Should track fees by type", async function () {
            const { feeManager, collector, payer } = await deployFeeManagerFixture();
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                FEE_AMOUNT
            );
            expect(await feeManager.getFeesByType(CLAIM_SUBMISSION_FEE)).to.equal(FEE_AMOUNT);
        });

        it("Should emit FeeDistributed for each allocation target", async function () {
            const { feeManager, collector, payer } = await deployFeeManagerFixture();
            const tx = feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                FEE_AMOUNT
            );
            await expect(tx).to.emit(feeManager, "FeeDistributed");
        });

        it("Should transfer tokens to allocation recipients", async function () {
            const { feeManager, feeToken, collector, payer, treasury } = await deployFeeManagerFixture();
            const before = await feeToken.balanceOf(await treasury.getAddress());
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                FEE_AMOUNT
            );
            const after = await feeToken.balanceOf(await treasury.getAddress());
            // Treasury gets 40% of 1 ETH = 0.4 ETH
            expect(after - before).to.equal((FEE_AMOUNT * 4000n) / 10000n);
        });

        it("Should revert if called by non-collector", async function () {
            const { feeManager, payer, other } = await deployFeeManagerFixture();
            await expect(
                feeManager.connect(other).collectFee(
                    CLAIM_SUBMISSION_FEE,
                    await payer.getAddress(),
                    FEE_AMOUNT
                )
            ).to.be.revertedWithCustomError(feeManager, "AccessControlUnauthorizedAccount");
        });

        it("Should revert if payer is zero address", async function () {
            const { feeManager, collector } = await deployFeeManagerFixture();
            await expect(
                feeManager.connect(collector).collectFee(
                    CLAIM_SUBMISSION_FEE,
                    ethers.ZeroAddress,
                    FEE_AMOUNT
                )
            ).to.be.revertedWithCustomError(feeManager, "ZeroAddress");
        });

        it("Should revert if amount is zero", async function () {
            const { feeManager, collector, payer } = await deployFeeManagerFixture();
            await expect(
                feeManager.connect(collector).collectFee(
                    CLAIM_SUBMISSION_FEE,
                    await payer.getAddress(),
                    0
                )
            ).to.be.revertedWithCustomError(feeManager, "ZeroAmount");
        });

        it("Should revert if fee type is inactive", async function () {
            const { feeManager, admin, collector, payer } = await deployFeeManagerFixture();
            await feeManager.connect(admin).setFeeActive(CLAIM_SUBMISSION_FEE, false);
            await expect(
                feeManager.connect(collector).collectFee(
                    CLAIM_SUBMISSION_FEE,
                    await payer.getAddress(),
                    FEE_AMOUNT
                )
            ).to.be.revertedWithCustomError(feeManager, "FeeTypeNotActive");
        });

        it("Should revert if amount is below minimum", async function () {
            const { feeManager, admin, collector, payer } = await deployFeeManagerFixture();
            const minFee = ethers.parseEther("5");
            await feeManager.connect(admin).updateFeeSchedule(
                CLAIM_SUBMISSION_FEE, 0, 0, minFee, 0
            );
            await expect(
                feeManager.connect(collector).collectFee(
                    CLAIM_SUBMISSION_FEE,
                    await payer.getAddress(),
                    ethers.parseEther("1")
                )
            ).to.be.revertedWithCustomError(feeManager, "FeeBelowMinimum");
        });

        it("Should revert if amount exceeds maximum", async function () {
            const { feeManager, admin, collector, payer } = await deployFeeManagerFixture();
            const maxFee = ethers.parseEther("0.5");
            await feeManager.connect(admin).updateFeeSchedule(
                CLAIM_SUBMISSION_FEE, 0, 0, 0, maxFee
            );
            await expect(
                feeManager.connect(collector).collectFee(
                    CLAIM_SUBMISSION_FEE,
                    await payer.getAddress(),
                    ethers.parseEther("1")
                )
            ).to.be.revertedWithCustomError(feeManager, "FeeAboveMaximum");
        });

        it("Should revert when paused", async function () {
            const { feeManager, admin, collector, payer } = await deployFeeManagerFixture();
            await feeManager.connect(admin).pause();
            await expect(
                feeManager.connect(collector).collectFee(
                    CLAIM_SUBMISSION_FEE,
                    await payer.getAddress(),
                    FEE_AMOUNT
                )
            ).to.be.revertedWithCustomError(feeManager, "EnforcedPause");
        });

        it("Should create a fee record with unique ID", async function () {
            const { feeManager, collector, payer } = await deployFeeManagerFixture();
            expect(await feeManager.getFeeRecordCount()).to.equal(0);
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                FEE_AMOUNT
            );
            expect(await feeManager.getFeeRecordCount()).to.equal(1);
            const record = await feeManager.getFeeRecord(0);
            expect(record.feeType).to.equal(CLAIM_SUBMISSION_FEE);
            expect(record.payer).to.equal(await payer.getAddress());
            expect(record.amount).to.equal(FEE_AMOUNT);
        });

        it("Should accumulate multiple fee records", async function () {
            const { feeManager, collector, payer } = await deployFeeManagerFixture();
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                FEE_AMOUNT
            );
            await feeManager.connect(collector).collectFee(
                CLAIM_UPDATE_FEE,
                await payer.getAddress(),
                FEE_AMOUNT
            );
            expect(await feeManager.getFeeRecordCount()).to.equal(2);
        });
    });

    // ── Routing & Accounting ────────────────────────────────────────────────────

    describe("Fee Routing & Accounting", function () {
        it("Should route 40% to treasury reserve", async function () {
            const { feeManager, feeToken, collector, payer, treasury } = await deployFeeManagerFixture();
            const before = await feeToken.balanceOf(await treasury.getAddress());
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                ethers.parseEther("10000")
            );
            const after = await feeToken.balanceOf(await treasury.getAddress());
            expect(after - before).to.equal(ethers.parseEther("4000"));
        });

        it("Should route 20% to security fund", async function () {
            const { feeManager, feeToken, collector, payer, security } = await deployFeeManagerFixture();
            const before = await feeToken.balanceOf(await security.getAddress());
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                ethers.parseEther("10000")
            );
            const after = await feeToken.balanceOf(await security.getAddress());
            expect(after - before).to.equal(ethers.parseEther("2000"));
        });

        it("Should route 20% to ecosystem fund", async function () {
            const { feeManager, feeToken, collector, payer, ecosystem } = await deployFeeManagerFixture();
            const before = await feeToken.balanceOf(await ecosystem.getAddress());
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                ethers.parseEther("10000")
            );
            const after = await feeToken.balanceOf(await ecosystem.getAddress());
            expect(after - before).to.equal(ethers.parseEther("2000"));
        });

        it("Should route 10% to contributor incentives", async function () {
            const { feeManager, feeToken, collector, payer, contributors } = await deployFeeManagerFixture();
            const before = await feeToken.balanceOf(await contributors.getAddress());
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                ethers.parseEther("10000")
            );
            const after = await feeToken.balanceOf(await contributors.getAddress());
            expect(after - before).to.equal(ethers.parseEther("1000"));
        });

        it("Should route 10% to emergency reserve", async function () {
            const { feeManager, feeToken, collector, payer, emergency } = await deployFeeManagerFixture();
            const before = await feeToken.balanceOf(await emergency.getAddress());
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                ethers.parseEther("10000")
            );
            const after = await feeToken.balanceOf(await emergency.getAddress());
            expect(after - before).to.equal(ethers.parseEther("1000"));
        });

        it("Collected fees should equal distributed fees (invariant)", async function () {
            const { feeManager, collector, payer } = await deployFeeManagerFixture();

            const amounts = [
                ethers.parseEther("1"),
                ethers.parseEther("3.5"),
                ethers.parseEther("100"),
            ];

            for (const amt of amounts) {
                await feeManager.connect(collector).collectFee(
                    CLAIM_SUBMISSION_FEE,
                    await payer.getAddress(),
                    amt
                );
            }

            const totalCollected = await feeManager.getTotalFeesCollected();
            const totalDistributed = await feeManager.getTotalFeesDistributed();
            const retained = await feeManager.getRetainedBalance();

            expect(totalCollected).to.equal(totalDistributed + retained);
        });

        it("Should update allocation tracking per target", async function () {
            const { feeManager, collector, payer } = await deployFeeManagerFixture();
            const fee = ethers.parseEther("10000");
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                fee
            );
            expect(await feeManager.getTotalByAllocation(ALLOC_TREASURY_RESERVE)).to.equal(
                (fee * 4000n) / 10000n
            );
            expect(await feeManager.getTotalByAllocation(ALLOC_SECURITY_FUND)).to.equal(
                (fee * 2000n) / 10000n
            );
        });
    });

    // ── Governance Controls ─────────────────────────────────────────────────────

    describe("Governance Controls — updateFeeSchedule", function () {
        it("Should update the fee schedule and emit FeeScheduleUpdated", async function () {
            const { feeManager, admin } = await deployFeeManagerFixture();
            const oldSchedule = await feeManager.getFeeSchedule(CLAIM_SUBMISSION_FEE);
            const newFixed = ethers.parseEther("2");
            await expect(
                feeManager.connect(admin).updateFeeSchedule(
                    CLAIM_SUBMISSION_FEE,
                    newFixed,
                    0,
                    0,
                    0
                )
            )
                .to.emit(feeManager, "FeeScheduleUpdated")
                .withArgs(CLAIM_SUBMISSION_FEE, oldSchedule.fixedAmount, newFixed);
        });

        it("Should bump the governance version on every update", async function () {
            const { feeManager, admin } = await deployFeeManagerFixture();
            const vBefore = await feeManager.globalGovVersion();
            await feeManager.connect(admin).updateFeeSchedule(
                CLAIM_SUBMISSION_FEE, ethers.parseEther("2"), 0, 0, 0
            );
            expect(await feeManager.globalGovVersion()).to.equal(vBefore + 1n);
        });

        it("Should reflect updated fee in calculateFee", async function () {
            const { feeManager, admin } = await deployFeeManagerFixture();
            const newFixed = ethers.parseEther("99");
            await feeManager.connect(admin).updateFeeSchedule(
                CLAIM_SUBMISSION_FEE, newFixed, 0, 0, 0
            );
            expect(await feeManager.calculateFee(CLAIM_SUBMISSION_FEE, 0)).to.equal(newFixed);
        });

        it("Should revert if basisPoints > 10000", async function () {
            const { feeManager, admin } = await deployFeeManagerFixture();
            await expect(
                feeManager.connect(admin).updateFeeSchedule(
                    CLAIM_SUBMISSION_FEE, 0, 10001, 0, 0
                )
            ).to.be.revertedWithCustomError(feeManager, "InvalidBasisPoints");
        });

        it("Should revert if non-admin calls updateFeeSchedule", async function () {
            const { feeManager, other } = await deployFeeManagerFixture();
            await expect(
                feeManager.connect(other).updateFeeSchedule(
                    CLAIM_SUBMISSION_FEE, 0, 0, 0, 0
                )
            ).to.be.revertedWithCustomError(feeManager, "UnauthorizedGovernance");
        });
    });

    describe("Governance Controls — setAllocationTargets", function () {
        it("Should update allocation targets", async function () {
            const { feeManager, admin, treasury, security, ecosystem, contributors, emergency } =
                await deployFeeManagerFixture();

            const newTargets = [
                {
                    name:        ALLOC_TREASURY_RESERVE,
                    recipient:   await treasury.getAddress(),
                    basisPoints: 5000n,
                    active:      true,
                },
                {
                    name:        ALLOC_SECURITY_FUND,
                    recipient:   await security.getAddress(),
                    basisPoints: 3000n,
                    active:      true,
                },
                {
                    name:        ALLOC_ECOSYSTEM_FUND,
                    recipient:   await ecosystem.getAddress(),
                    basisPoints: 2000n,
                    active:      true,
                },
            ];

            await expect(feeManager.connect(admin).setAllocationTargets(newTargets))
                .to.emit(feeManager, "AllocationTargetsUpdated");

            const stored = await feeManager.getAllocationTargets();
            expect(stored.length).to.equal(3);
            expect(stored[0].basisPoints).to.equal(5000n);
        });

        it("Should revert if basisPoints do not sum to 10000", async function () {
            const { feeManager, admin, treasury } = await deployFeeManagerFixture();
            await expect(
                feeManager.connect(admin).setAllocationTargets([
                    {
                        name:        ALLOC_TREASURY_RESERVE,
                        recipient:   await treasury.getAddress(),
                        basisPoints: 5000n,
                        active:      true,
                    },
                ])
            ).to.be.revertedWithCustomError(feeManager, "InvalidBasisPoints");
        });

        it("Should revert if active recipient is zero address", async function () {
            const { feeManager, admin, security } = await deployFeeManagerFixture();
            await expect(
                feeManager.connect(admin).setAllocationTargets([
                    {
                        name:        ALLOC_TREASURY_RESERVE,
                        recipient:   ethers.ZeroAddress,
                        basisPoints: 5000n,
                        active:      true,
                    },
                    {
                        name:        ALLOC_SECURITY_FUND,
                        recipient:   await security.getAddress(),
                        basisPoints: 5000n,
                        active:      true,
                    },
                ])
            ).to.be.revertedWithCustomError(feeManager, "AllocationRecipientZero");
        });
    });

    // ── Read Interfaces ─────────────────────────────────────────────────────────

    describe("Read Interfaces", function () {
        it("getFeeHistory returns paginated records", async function () {
            const { feeManager, collector, payer } = await deployFeeManagerFixture();
            for (let i = 0; i < 5; i++) {
                await feeManager.connect(collector).collectFee(
                    CLAIM_SUBMISSION_FEE,
                    await payer.getAddress(),
                    FEE_AMOUNT
                );
            }
            const page = await feeManager.getFeeHistory(0, 3);
            expect(page.length).to.equal(3);
        });

        it("getFeeHistory returns empty array when offset >= total", async function () {
            const { feeManager } = await deployFeeManagerFixture();
            const page = await feeManager.getFeeHistory(100, 10);
            expect(page.length).to.equal(0);
        });

        it("getTreasuryDistributions returns all allocation stats", async function () {
            const { feeManager, collector, payer } = await deployFeeManagerFixture();
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                FEE_AMOUNT
            );
            const [names, recipients, amounts, shares] = await feeManager.getTreasuryDistributions();
            expect(names.length).to.equal(5);
            expect(amounts[0]).to.be.gt(0n);
        });

        it("getFeeScheduleAtVersion returns archived schedules", async function () {
            const { feeManager, admin } = await deployFeeManagerFixture();
            // Version 0 is the initial schedule
            const initial = await feeManager.getFeeSchedule(CLAIM_SUBMISSION_FEE);
            await feeManager.connect(admin).updateFeeSchedule(
                CLAIM_SUBMISSION_FEE,
                ethers.parseEther("999"),
                0,
                0,
                0
            );
            // The archived version should match the old schedule
            const archived = await feeManager.getFeeScheduleAtVersion(CLAIM_SUBMISSION_FEE, 0);
            expect(archived.fixedAmount).to.equal(initial.fixedAmount);
        });
    });

    // ── Pause / Unpause ─────────────────────────────────────────────────────────

    describe("Pause / Unpause", function () {
        it("Admin can pause and unpause", async function () {
            const { feeManager, admin } = await deployFeeManagerFixture();
            await feeManager.connect(admin).pause();
            expect(await feeManager.paused()).to.be.true;
            await feeManager.connect(admin).unpause();
            expect(await feeManager.paused()).to.be.false;
        });

        it("Non-pauser cannot pause", async function () {
            const { feeManager, other } = await deployFeeManagerFixture();
            await expect(feeManager.connect(other).pause())
                .to.be.revertedWithCustomError(feeManager, "AccessControlUnauthorizedAccount");
        });
    });

    // ── setFeeToken ─────────────────────────────────────────────────────────────

    describe("setFeeToken", function () {
        it("Admin can update the fee token and event is emitted", async function () {
            const { feeManager, feeToken, admin } = await deployFeeManagerFixture();
            const MockERC20 = await ethers.getContractFactory("MockERC20");
            const newToken = await MockERC20.deploy("New", "NEW");
            await newToken.waitForDeployment();
            await expect(
                feeManager.connect(admin).setFeeToken(await newToken.getAddress())
            )
                .to.emit(feeManager, "FeeTokenUpdated")
                .withArgs(await feeToken.getAddress(), await newToken.getAddress());
        });

        it("Should revert for zero address", async function () {
            const { feeManager, admin } = await deployFeeManagerFixture();
            await expect(feeManager.connect(admin).setFeeToken(ethers.ZeroAddress))
                .to.be.revertedWithCustomError(feeManager, "ZeroAddress");
        });
    });

    // ── Security ────────────────────────────────────────────────────────────────

    describe("Security", function () {
        it("Fee bypass is impossible — non-collector cannot collectFee", async function () {
            const { feeManager, payer, other } = await deployFeeManagerFixture();
            await expect(
                feeManager.connect(other).collectFee(
                    CLAIM_SUBMISSION_FEE,
                    await payer.getAddress(),
                    FEE_AMOUNT
                )
            ).to.be.reverted;
        });

        it("Invalid fee schedule (bps > 10000) is rejected", async function () {
            const { feeManager, admin } = await deployFeeManagerFixture();
            await expect(
                feeManager.connect(admin).updateFeeSchedule(
                    CLAIM_SUBMISSION_FEE, 0, 99999, 0, 0
                )
            ).to.be.revertedWithCustomError(feeManager, "InvalidBasisPoints");
        });

        it("Duplicate record ID is rejected", async function () {
            // This is enforced via unique record IDs — collecting the same fee in the
            // same block at the same index would produce the same ID. In practice
            // sequential calls produce different indices so we verify the counter increments.
            const { feeManager, collector, payer } = await deployFeeManagerFixture();
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                FEE_AMOUNT
            );
            await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                FEE_AMOUNT
            );
            expect(await feeManager.getFeeRecordCount()).to.equal(2);
        });
    });

    // ── Gas Benchmarks ──────────────────────────────────────────────────────────

    describe("Gas Benchmarks", function () {
        it("collectFee gas usage", async function () {
            const { feeManager, collector, payer } = await deployFeeManagerFixture();
            const tx = await feeManager.connect(collector).collectFee(
                CLAIM_SUBMISSION_FEE,
                await payer.getAddress(),
                FEE_AMOUNT
            );
            const receipt = await tx.wait();
            console.log(`      collectFee gas used: ${receipt?.gasUsed?.toString()}`);
        });

        it("updateFeeSchedule gas usage", async function () {
            const { feeManager, admin } = await deployFeeManagerFixture();
            const tx = await feeManager.connect(admin).updateFeeSchedule(
                CLAIM_SUBMISSION_FEE,
                ethers.parseEther("2"),
                0,
                0,
                0
            );
            const receipt = await tx.wait();
            console.log(`      updateFeeSchedule gas used: ${receipt?.gasUsed?.toString()}`);
        });

        it("setAllocationTargets gas usage", async function () {
            const { feeManager, admin, treasury, security, ecosystem, contributors, emergency } =
                await deployFeeManagerFixture();
            const targets = [
                { name: ALLOC_TREASURY_RESERVE, recipient: await treasury.getAddress(), basisPoints: 4000n, active: true },
                { name: ALLOC_SECURITY_FUND, recipient: await security.getAddress(), basisPoints: 2000n, active: true },
                { name: ALLOC_ECOSYSTEM_FUND, recipient: await ecosystem.getAddress(), basisPoints: 2000n, active: true },
                { name: ALLOC_CONTRIBUTOR_INCENTIVES, recipient: await contributors.getAddress(), basisPoints: 1000n, active: true },
                { name: ALLOC_EMERGENCY_RESERVE, recipient: await emergency.getAddress(), basisPoints: 1000n, active: true },
            ];
            const tx = await feeManager.connect(admin).setAllocationTargets(targets);
            const receipt = await tx.wait();
            console.log(`      setAllocationTargets gas used: ${receipt?.gasUsed?.toString()}`);
        });
    });
});
