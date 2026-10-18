import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

/**
 * PREWAVE-SC-074 (#749) — Bound Emergency Pause Gas and Blast Radius
 *
 * Acceptance Criteria & Test Boundaries:
 * 1. Every operation scope: All canonical scopes pause cleanly and independently.
 * 2. Gas Budget Bound: Pause gas is strictly bounded below approved budget (EMERGENCY_PAUSE = 180,000 gas).
 * 3. Blast Radius Containment: Pausing one scope never pauses or restricts unrelated operations.
 * 4. Deterministic Repeat Pause: Calling pause on an already-paused scope reverts deterministically.
 * 5. Event Auditability: Emitted events identify scope, authorized actor (msg.sender), and incident reference/reason.
 * 6. O(1) Scalability: Pause gas does not iterate unbounded collections or scale with registry size.
 */
describe("PREWAVE-SC-074: Bound Emergency Pause Gas and Blast Radius", function () {
  const EMERGENCY_PAUSE_GAS_BUDGET = 180_000n;

  // Canonical scope identifiers
  const SCOPE_ALL = ethers.ZeroHash;
  const SCOPE_CLAIMS = ethers.id("truthbounty.v2.scope.claims");
  const SCOPE_EVIDENCE = ethers.id("truthbounty.v2.scope.evidence");
  const SCOPE_STAKING = ethers.id("truthbounty.v2.scope.staking");
  const SCOPE_VERIFICATION = ethers.id("truthbounty.v2.scope.verification");
  const SCOPE_SETTLEMENT = ethers.id("truthbounty.v2.scope.settlement");
  const SCOPE_TREASURY = ethers.id("truthbounty.v2.scope.treasury");
  const SCOPE_DISPUTES = ethers.id("truthbounty.v2.scope.disputes");

  const ALL_SCOPES = [
    SCOPE_CLAIMS,
    SCOPE_EVIDENCE,
    SCOPE_STAKING,
    SCOPE_VERIFICATION,
    SCOPE_SETTLEMENT,
    SCOPE_TREASURY,
    SCOPE_DISPUTES,
  ];

  async function deployEmergencyFixture() {
    const [admin, emergencyCouncil, governance, unauthorizedUser] = await ethers.getSigners();

    // 1. Deploy Canonical EmergencyControls
    const EmergencyControlsFactory = await ethers.getContractFactory("EmergencyControls");
    const emergencyControls = await EmergencyControlsFactory.deploy(
      admin.address,
      emergencyCouncil.address,
      governance.address
    );
    await emergencyControls.waitForDeployment();

    // 2. Deploy Canonical EmergencyGatekeeper
    const EmergencyGatekeeperFactory = await ethers.getContractFactory("EmergencyGatekeeper");
    const emergencyGatekeeper = await EmergencyGatekeeperFactory.deploy(
      admin.address,
      emergencyCouncil.address, // PAUSE_INITIATOR
      governance.address,       // PAUSE_RESOLVER
      3600                      // 1 hour rewire delay
    );
    await emergencyGatekeeper.waitForDeployment();

    // 3. Deploy Canonical EmergencyController
    const EmergencyControllerFactory = await ethers.getContractFactory("EmergencyController");
    const emergencyController = await EmergencyControllerFactory.deploy(
      emergencyCouncil.address,
      governance.address,
      governance.address
    );
    await emergencyController.waitForDeployment();

    // 4. Deploy GasBudgetRegistry
    const GasBudgetRegistryFactory = await ethers.getContractFactory("GasBudgetRegistry");
    const gasBudgets = await GasBudgetRegistryFactory.deploy(admin.address);
    await gasBudgets.waitForDeployment();

    return {
      emergencyControls,
      emergencyGatekeeper,
      emergencyController,
      gasBudgets,
      admin,
      emergencyCouncil,
      governance,
      unauthorizedUser,
    };
  }

  describe("1. Gas Budget Bounds (< 180,000 gas)", function () {
    it("EmergencyControls: pause cost is strictly bounded below 180,000 gas across all canonical scopes", async function () {
      const { emergencyControls, emergencyCouncil, gasBudgets } = await loadFixture(deployEmergencyFixture);

      const [configuredBudget] = await gasBudgets.getBudget(11); // Operation.EMERGENCY_PAUSE = 11
      expect(configuredBudget).to.equal(EMERGENCY_PAUSE_GAS_BUDGET);

      for (const scope of ALL_SCOPES) {
        const tx = await emergencyControls.connect(emergencyCouncil).pause(scope);
        const receipt = await tx.wait();
        expect(receipt).to.not.be.null;

        expect(receipt!.gasUsed).to.be.lessThan(
          EMERGENCY_PAUSE_GAS_BUDGET,
          `Pause for scope ${scope} exceeded approved budget`
        );
        // Realistic O(1) SLOAD/SSTORE pause cost should be between 25,000 and 65,000 gas
        expect(receipt!.gasUsed).to.be.lessThan(70_000n);
      }
    });

    it("EmergencyGatekeeper: pause cost is strictly bounded below 180,000 gas", async function () {
      const { emergencyGatekeeper, emergencyCouncil } = await loadFixture(deployEmergencyFixture);

      for (const scope of ALL_SCOPES) {
        const tx = await emergencyGatekeeper.connect(emergencyCouncil).pause(scope);
        const receipt = await tx.wait();
        expect(receipt).to.not.be.null;

        expect(receipt!.gasUsed).to.be.lessThan(
          EMERGENCY_PAUSE_GAS_BUDGET,
          `Gatekeeper pause for scope ${scope} exceeded budget`
        );
        expect(receipt!.gasUsed).to.be.lessThan(75_000n);
      }
    });

    it("EmergencyController: activatePause cost is strictly bounded below 180,000 gas", async function () {
      const { emergencyController, emergencyCouncil } = await loadFixture(deployEmergencyFixture);

      const tx = await emergencyController
        .connect(emergencyCouncil)
        .activatePause(1, "Rapid incident containment", ethers.id("INCIDENT_001"));
      const receipt = await tx.wait();
      expect(receipt).to.not.be.null;

      expect(receipt!.gasUsed).to.be.lessThan(EMERGENCY_PAUSE_GAS_BUDGET);
      expect(receipt!.gasUsed).to.be.lessThan(70_000n);
    });
  });

  describe("2. Blast Radius Containment", function () {
    it("Pausing SCOPE_CLAIMS does not affect any other canonical scope", async function () {
      const { emergencyControls, emergencyCouncil } = await loadFixture(deployEmergencyFixture);

      await emergencyControls.connect(emergencyCouncil).pause(SCOPE_CLAIMS);

      expect(await emergencyControls.paused(SCOPE_CLAIMS)).to.be.true;

      // Every other scope remains unpaused
      for (const otherScope of ALL_SCOPES) {
        if (otherScope !== SCOPE_CLAIMS) {
          expect(await emergencyControls.paused(otherScope)).to.be.false;
          expect(await emergencyControls.isScopeSpecificallyPaused(otherScope)).to.be.false;
        }
      }
    });

    it("EmergencyGatekeeper: pausing one scope leaves other scopes unpaused and gates operable", async function () {
      const { emergencyGatekeeper, emergencyCouncil } = await loadFixture(deployEmergencyFixture);

      await emergencyGatekeeper.connect(emergencyCouncil).pause(SCOPE_EVIDENCE);

      expect(await emergencyGatekeeper.paused(SCOPE_EVIDENCE)).to.be.true;
      expect(await emergencyGatekeeper.locallyPaused(SCOPE_EVIDENCE)).to.be.true;

      expect(await emergencyGatekeeper.paused(SCOPE_STAKING)).to.be.false;
      expect(await emergencyGatekeeper.locallyPaused(SCOPE_STAKING)).to.be.false;
      await expect(emergencyGatekeeper.requireNotPaused(SCOPE_STAKING)).to.not.be.reverted;
    });

    it("Global composition: SCOPE_ALL halts every scope; individual unpause does not bypass global halt", async function () {
      const { emergencyControls, emergencyCouncil, governance } = await loadFixture(deployEmergencyFixture);

      // Pause specific scope first
      await emergencyControls.connect(emergencyCouncil).pause(SCOPE_CLAIMS);

      // Now pause global scope
      await emergencyControls.connect(emergencyCouncil).pause(SCOPE_ALL);

      // Global pause causes all scopes to report paused
      for (const scope of ALL_SCOPES) {
        expect(await emergencyControls.paused(scope)).to.be.true;
      }

      // Unpausing SCOPE_CLAIMS while SCOPE_ALL remains paused still keeps it paused via global hierarchy
      await emergencyControls.connect(governance).unpause(SCOPE_CLAIMS);
      expect(await emergencyControls.isScopeSpecificallyPaused(SCOPE_CLAIMS)).to.be.false;
      expect(await emergencyControls.paused(SCOPE_CLAIMS)).to.be.true; // Still blocked by SCOPE_ALL
    });
  });

  describe("3. Deterministic Repeat Pause Revert", function () {
    it("EmergencyControls: repeat pause on already paused scope reverts deterministically with AlreadyPaused", async function () {
      const { emergencyControls, emergencyCouncil } = await loadFixture(deployEmergencyFixture);

      await emergencyControls.connect(emergencyCouncil).pause(SCOPE_TREASURY);

      await expect(
        emergencyControls.connect(emergencyCouncil).pause(SCOPE_TREASURY)
      ).to.be.revertedWithCustomError(emergencyControls, "AlreadyPaused").withArgs(SCOPE_TREASURY);
    });

    it("EmergencyGatekeeper: repeat pause reverts deterministically with ScopeAlreadyPaused", async function () {
      const { emergencyGatekeeper, emergencyCouncil } = await loadFixture(deployEmergencyFixture);

      await emergencyGatekeeper.connect(emergencyCouncil).pause(SCOPE_SETTLEMENT);

      await expect(
        emergencyGatekeeper.connect(emergencyCouncil).pause(SCOPE_SETTLEMENT)
      ).to.be.revertedWithCustomError(emergencyGatekeeper, "ScopeAlreadyPaused").withArgs(SCOPE_SETTLEMENT, true);
    });

    it("EmergencyController: repeat pause or non-escalating pause reverts deterministically with AlreadyAtLevel", async function () {
      const { emergencyController, emergencyCouncil } = await loadFixture(deployEmergencyFixture);

      await emergencyController
        .connect(emergencyCouncil)
        .activatePause(2, "Financial pause", ethers.id("INCIDENT_002"));

      await expect(
        emergencyController
          .connect(emergencyCouncil)
          .activatePause(2, "Repeat financial pause", ethers.id("INCIDENT_002_REPEAT"))
      ).to.be.revertedWithCustomError(emergencyController, "AlreadyAtLevel").withArgs(2);

      await expect(
        emergencyController
          .connect(emergencyCouncil)
          .activatePause(1, "Lower level pause", ethers.id("INCIDENT_LOWER"))
      ).to.be.revertedWithCustomError(emergencyController, "AlreadyAtLevel").withArgs(2);
    });
  });

  describe("4. Audit Event Completeness", function () {
    it("EmergencyControls emits EmergencyPaused with accurate scope and authorized actor", async function () {
      const { emergencyControls, emergencyCouncil } = await loadFixture(deployEmergencyFixture);

      await expect(emergencyControls.connect(emergencyCouncil).pause(SCOPE_DISPUTES))
        .to.emit(emergencyControls, "EmergencyPaused")
        .withArgs(SCOPE_DISPUTES, emergencyCouncil.address);
    });

    it("EmergencyGatekeeper emits ScopePauseUpdated and EmergencyPaused with actor and state", async function () {
      const { emergencyGatekeeper, emergencyCouncil } = await loadFixture(deployEmergencyFixture);

      await expect(emergencyGatekeeper.connect(emergencyCouncil).pause(SCOPE_VERIFICATION))
        .to.emit(emergencyGatekeeper, "EmergencyPaused")
        .withArgs(SCOPE_VERIFICATION, emergencyCouncil.address)
        .and.to.emit(emergencyGatekeeper, "ScopePauseUpdated")
        .withArgs(SCOPE_VERIFICATION, emergencyCouncil.address, true);
    });

    it("EmergencyController emits EmergencyPauseActivated with level, actor, reason, and incident reference", async function () {
      const { emergencyController, emergencyCouncil } = await loadFixture(deployEmergencyFixture);
      const reason = "Congestion circuit breaker activated";
      const incidentRef = ethers.id("INCIDENT_REF_749");

      await expect(emergencyController.connect(emergencyCouncil).activatePause(3, reason, incidentRef))
        .to.emit(emergencyController, "EmergencyPauseActivated")
        .withArgs(3, emergencyCouncil.address, reason, incidentRef);
    });
  });

  describe("5. O(1) Constant Complexity (No Unbounded Iterations)", function () {
    it("Pause gas execution is constant regardless of sequential pause operations", async function () {
      const { emergencyControls, emergencyCouncil } = await loadFixture(deployEmergencyFixture);

      // Cold pause on first scope
      const tx1 = await emergencyControls.connect(emergencyCouncil).pause(SCOPE_CLAIMS);
      const receipt1 = await tx1.wait();

      // Pause on subsequent scopes (warm storage context)
      const tx2 = await emergencyControls.connect(emergencyCouncil).pause(SCOPE_EVIDENCE);
      const receipt2 = await tx2.wait();

      const tx3 = await emergencyControls.connect(emergencyCouncil).pause(SCOPE_STAKING);
      const receipt3 = await tx3.wait();

      // All pause executions should be strictly bounded and exhibit near-identical O(1) gas usage
      expect(Math.abs(Number(receipt2!.gasUsed - receipt3!.gasUsed))).to.be.lessThan(500);
      expect(receipt1!.gasUsed).to.be.lessThan(EMERGENCY_PAUSE_GAS_BUDGET);
      expect(receipt2!.gasUsed).to.be.lessThan(EMERGENCY_PAUSE_GAS_BUDGET);
      expect(receipt3!.gasUsed).to.be.lessThan(EMERGENCY_PAUSE_GAS_BUDGET);
    });
  });
});
