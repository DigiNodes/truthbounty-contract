import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

describe("BootstrapController", function () {
  async function deployFixture() {
    const [admin, deployer, user] = await ethers.getSigners();

    const BootstrapController = await ethers.getContractFactory("BootstrapController");
    const controller = await BootstrapController.deploy(admin.address, ethers.ZeroAddress);
    await controller.waitForDeployment();

    await controller.grantRole(await controller.DEPLOYER_ROLE(), deployer.address);

    return { admin, deployer, user, controller };
  }

  // Deploys real modules and registers all 11 standard modules so that
  // bootstrap() can pass _validateAllModulesRegistered() and _validateDependencies().
  async function deployAllModulesFixture() {
    const [admin, deployer] = await ethers.getSigners();

    const BootstrapController = await ethers.getContractFactory("BootstrapController");
    const controller = await BootstrapController.deploy(admin.address, ethers.ZeroAddress);
    await controller.waitForDeployment();
    await controller.grantRole(await controller.DEPLOYER_ROLE(), deployer.address);

    const GovernanceController = await ethers.getContractFactory("GovernanceController");
    const governance = await GovernanceController.deploy(admin.address);
    await governance.waitForDeployment();

    const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
    const token = await TruthBountyToken.deploy(admin.address);
    await token.waitForDeployment();

    const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
    const oracle = await MockReputationOracle.deploy();
    await oracle.waitForDeployment();

    const Staking = await ethers.getContractFactory("Staking");
    const staking = await Staking.deploy(await token.getAddress(), 86400, admin.address);
    await staking.waitForDeployment();

    const WeightedStaking = await ethers.getContractFactory("contracts/WeightedStaking.sol:WeightedStaking");
    const weightedStaking = await WeightedStaking.deploy(
      await oracle.getAddress(),
      admin.address,
      await governance.getAddress()
    );
    await weightedStaking.waitForDeployment();

    const TruthBountyWeighted = await ethers.getContractFactory("TruthBountyWeighted");
    const bounty = await TruthBountyWeighted.deploy(
      await token.getAddress(),
      await oracle.getAddress(),
      admin.address,
      await governance.getAddress()
    );
    await bounty.waitForDeployment();

    const TruthBountyClaims = await ethers.getContractFactory("TruthBountyClaims");
    const claims = await TruthBountyClaims.deploy(await token.getAddress(), admin.address);
    await claims.waitForDeployment();

    const ReputationDecay = await ethers.getContractFactory("ReputationDecay");
    const decay = await ReputationDecay.deploy(admin.address);
    await decay.waitForDeployment();

    const ReputationSnapshot = await ethers.getContractFactory("ReputationSnapshot");
    const snapshot = await ReputationSnapshot.deploy(admin.address);
    await snapshot.waitForDeployment();

    const ReputationReceiver = await ethers.getContractFactory("ReputationReceiver");
    const receiver = await ReputationReceiver.deploy(admin.address, await oracle.getAddress());
    await receiver.waitForDeployment();

    const VerifierSlashing = await ethers.getContractFactory("VerifierSlashing");
    const slashing = await VerifierSlashing.deploy(
      await staking.getAddress(),
      admin.address,
      await governance.getAddress()
    );
    await slashing.waitForDeployment();

    const InsuranceFund = await ethers.getContractFactory("InsuranceFund");
    const insurance = await InsuranceFund.deploy(
      await token.getAddress(),
      admin.address,
      await governance.getAddress()
    );
    await insurance.waitForDeployment();

    await controller.connect(deployer).registerModules(
      [
        MODULE_GOVERNANCE,
        MODULE_TOKEN,
        MODULE_ORACLE,
        MODULE_STAKING,
        MODULE_REPUTATION_DECAY,
        MODULE_REPUTATION_SNAPSHOT,
        MODULE_WEIGHTED_STAKING,
        MODULE_BOUNTY,
        MODULE_VERIFIER_SLASHING,
        MODULE_CLAIMS,
        MODULE_REPUTATION_RECEIVER,
        MODULE_INSURANCE,
      ],
      [
        await governance.getAddress(),
        await token.getAddress(),
        await oracle.getAddress(),
        await staking.getAddress(),
        await decay.getAddress(),
        await snapshot.getAddress(),
        await weightedStaking.getAddress(),
        await bounty.getAddress(),
        await slashing.getAddress(),
        await claims.getAddress(),
        await receiver.getAddress(),
        await insurance.getAddress(),
      ],
      [
        "Governance", "Token", "Oracle", "Staking", "RepDecay",
        "RepSnapshot", "WeightedStaking", "Bounty", "Slashing",
        "Claims", "RepReceiver", "Insurance"
      ]
    );

    return { controller, admin, deployer };
  }

  const MODULE_GOVERNANCE = ethers.id("GOVERNANCE");
  const MODULE_TOKEN = ethers.id("TOKEN");
  const MODULE_ORACLE = ethers.id("REPUTATION_ORACLE");
  const MODULE_BOUNTY = ethers.id("TRUTH_BOUNTY");
  const MODULE_STAKING = ethers.id("STAKING");
  const MODULE_REPUTATION_DECAY = ethers.id("REPUTATION_DECAY");
  const MODULE_REPUTATION_SNAPSHOT = ethers.id("REPUTATION_SNAPSHOT");
  const MODULE_WEIGHTED_STAKING = ethers.id("WEIGHTED_STAKING");
  const MODULE_VERIFIER_SLASHING = ethers.id("VERIFIER_SLASHING");
  const MODULE_CLAIMS = ethers.id("CLAIMS");
  const MODULE_REPUTATION_RECEIVER = ethers.id("REPUTATION_RECEIVER");
  const MODULE_INSURANCE = ethers.id("INSURANCE");

  describe("Deployment", function () {
    it("should set correct admin roles", async function () {
      const { admin, controller } = await loadFixture(deployFixture);
      expect(await controller.hasRole(await controller.DEFAULT_ADMIN_ROLE(), admin.address)).to.be.true;
      expect(await controller.hasRole(await controller.ADMIN_ROLE(), admin.address)).to.be.true;
      expect(await controller.hasRole(await controller.DEPLOYER_ROLE(), admin.address)).to.be.true;
    });

    it("should not be bootstrapped initially", async function () {
      const { controller } = await loadFixture(deployFixture);
      expect(await controller.isBootstrapped()).to.be.false;
      expect(await controller.isFullyInitialized()).to.be.false;
    });

    it("should have protocol version set", async function () {
      const { controller } = await loadFixture(deployFixture);
      expect(await controller.PROTOCOL_VERSION()).to.equal("2.0.0");
    });

    it("should return default bootstrap state", async function () {
      const { controller } = await loadFixture(deployFixture);
      const state = await controller.getBootstrapState();
      expect(state.bootstrapped).to.be.false;
      expect(state.bootstrapTimestamp).to.equal(0n);
      expect(state.blockNumber).to.equal(0n);
      expect(state.version).to.equal("");
    });
  });

  describe("Module Registration", function () {
    it("should register a single module", async function () {
      const { controller, deployer } = await loadFixture(deployFixture);
      const addr = ethers.Wallet.createRandom().address;

      await expect(controller.connect(deployer).registerModule(MODULE_GOVERNANCE, addr, "Governance"))
        .to.emit(controller, "ModuleRegistered")
        .withArgs(MODULE_GOVERNANCE, addr, "Governance");

      expect(await controller.getModuleAddress(MODULE_GOVERNANCE)).to.equal(addr);
      expect(await controller.getModuleCount()).to.equal(1n);
    });

    it("should register modules in batch", async function () {
      const { controller, deployer } = await loadFixture(deployFixture);
      const addr1 = ethers.Wallet.createRandom().address;
      const addr2 = ethers.Wallet.createRandom().address;

      const tx = controller.connect(deployer).registerModules(
        [MODULE_GOVERNANCE, MODULE_TOKEN],
        [addr1, addr2],
        ["Governance", "Token"]
      );

      await expect(tx).to.emit(controller, "ModuleRegistered").withArgs(MODULE_GOVERNANCE, addr1, "Governance");
      await expect(tx).to.emit(controller, "ModuleRegistered").withArgs(MODULE_TOKEN, addr2, "Token");

      expect(await controller.getModuleCount()).to.equal(2n);
    });

    it("should revert when registering duplicate module", async function () {
      const { controller, deployer } = await loadFixture(deployFixture);
      const addr = ethers.Wallet.createRandom().address;

      await controller.connect(deployer).registerModule(MODULE_GOVERNANCE, addr, "Governance");
      await expect(
        controller.connect(deployer).registerModule(MODULE_GOVERNANCE, addr, "Governance")
      ).to.be.revertedWithCustomError(controller, "ModuleAlreadyRegistered");
    });

    it("should revert when registering zero address", async function () {
      const { controller, deployer } = await loadFixture(deployFixture);
      await expect(
        controller.connect(deployer).registerModule(MODULE_GOVERNANCE, ethers.ZeroAddress, "Governance")
      ).to.be.revertedWithCustomError(controller, "InvalidAddress");
    });

    it("should revert when registering empty name", async function () {
      const { controller, deployer } = await loadFixture(deployFixture);
      const addr = ethers.Wallet.createRandom().address;
      await expect(
        controller.connect(deployer).registerModule(MODULE_GOVERNANCE, addr, "")
      ).to.be.revertedWithCustomError(controller, "EmptyModuleName");
    });

    it("should revert batch on array length mismatch", async function () {
      const { controller, deployer } = await loadFixture(deployFixture);
      const addr = ethers.Wallet.createRandom().address;

      await expect(
        controller.connect(deployer).registerModules(
          [MODULE_GOVERNANCE, MODULE_TOKEN],
          [addr],
          ["Governance", "Token"]
        )
      ).to.be.revertedWith("Array length mismatch");
    });

    it("should revert if caller lacks DEPLOYER_ROLE", async function () {
      const { controller, user } = await loadFixture(deployFixture);
      const addr = ethers.Wallet.createRandom().address;

      await expect(
        controller.connect(user).registerModule(MODULE_GOVERNANCE, addr, "Governance")
      ).to.be.revertedWithCustomError(controller, "AccessControlUnauthorizedAccount");
    });
  });

  describe("Module Queries", function () {
    it("should return module info", async function () {
      const { controller, deployer } = await loadFixture(deployFixture);
      const addr = ethers.Wallet.createRandom().address;

      await controller.connect(deployer).registerModule(MODULE_GOVERNANCE, addr, "Governance");
      const info = await controller.getModuleInfo(MODULE_GOVERNANCE);

      expect(info.addr).to.equal(addr);
      expect(info.registered).to.be.true;
      expect(info.initialized).to.be.false;
      expect(info.name).to.equal("Governance");
    });

    it("should return module at index", async function () {
      const { controller, deployer } = await loadFixture(deployFixture);
      const addr = ethers.Wallet.createRandom().address;

      await controller.connect(deployer).registerModule(MODULE_GOVERNANCE, addr, "Governance");
      const [id, info] = await controller.getModuleAt(0);

      expect(id).to.equal(MODULE_GOVERNANCE);
      expect(info.addr).to.equal(addr);
    });

    it("should return all modules", async function () {
      const { controller, deployer } = await loadFixture(deployFixture);
      const addr1 = ethers.Wallet.createRandom().address;
      const addr2 = ethers.Wallet.createRandom().address;

      await controller.connect(deployer).registerModules(
        [MODULE_GOVERNANCE, MODULE_TOKEN],
        [addr1, addr2],
        ["Governance", "Token"]
      );

      const [ids, infos] = await controller.getAllModules();
      expect(ids.length).to.equal(2);
      expect(infos[0].addr).to.equal(addr1);
      expect(infos[1].addr).to.equal(addr2);
    });

    it("should return standard module order", async function () {
      const { controller } = await loadFixture(deployFixture);
      const order = await controller.getStandardModuleOrder();
      expect(order.length).to.be.gt(0);
      expect(order[0]).to.equal(MODULE_GOVERNANCE);
    });

    it("should revert getModuleAddress for unregistered module", async function () {
      const { controller } = await loadFixture(deployFixture);
      await expect(
        controller.getModuleAddress(MODULE_GOVERNANCE)
      ).to.be.revertedWithCustomError(controller, "ModuleNotRegistered");
    });
  });

  describe("Configuration", function () {
    it("should set bootstrap config", async function () {
      const { controller, deployer } = await loadFixture(deployFixture);

      const config = {
        verificationWindowDuration: 7 * 86400,
        minStakeAmount: ethers.parseEther("100"),
        settlementThresholdPercent: 60,
        rewardPercent: 80,
        slashPercent: 20,
        confirmationDelay: 3600,
        minReputationScore: ethers.parseEther("0.1"),
        maxReputationScore: ethers.parseEther("10"),
        defaultReputationScore: ethers.parseEther("1"),
        stakingLockDuration: 86400,
      };

      await controller.connect(deployer).setBootstrapConfig(config);

      const stored = await controller.getBootstrapConfig();
      expect(stored.verificationWindowDuration).to.equal(config.verificationWindowDuration);
      expect(stored.minStakeAmount).to.equal(config.minStakeAmount);
    });
  });

  describe("Bootstrap Execution", function () {
    it("should fail bootstrap when modules missing", async function () {
      const { controller, deployer } = await loadFixture(deployFixture);

      await controller.connect(deployer).registerModule(MODULE_GOVERNANCE, ethers.Wallet.createRandom().address, "Governance");

      await expect(
        controller.connect(deployer).bootstrap()
      ).to.be.revertedWithCustomError(controller, "ModuleNotRegistered");
    });

    it("should fail bootstrap when not deployer", async function () {
      const { controller, user } = await loadFixture(deployFixture);
      await expect(
        controller.connect(user).bootstrap()
      ).to.be.revertedWithCustomError(controller, "AccessControlUnauthorizedAccount");
    });

    it("should complete bootstrap with all modules registered", async function () {
      const { controller, deployer } = await loadFixture(deployAllModulesFixture);

      await expect(controller.connect(deployer).bootstrap())
        .to.emit(controller, "ProtocolBootstrapStarted");

      expect(await controller.isBootstrapped()).to.be.true;
      const state = await controller.getBootstrapState();
      expect(state.bootstrapped).to.be.true;
      expect(state.version).to.equal("2.0.0");
      expect(state.bootstrapper).to.equal(deployer.address);
    });

    it("should mark modules as initialized after bootstrap", async function () {
      const { controller, deployer } = await loadFixture(deployAllModulesFixture);

      await controller.connect(deployer).bootstrap();

      expect(await controller.isModuleInitialized(MODULE_GOVERNANCE)).to.be.true;
      expect(await controller.isModuleInitialized(MODULE_TOKEN)).to.be.true;
    });

    it("should reject duplicate bootstrap", async function () {
      const { controller, deployer } = await loadFixture(deployAllModulesFixture);

      await controller.connect(deployer).bootstrap();

      await expect(
        controller.connect(deployer).bootstrap()
      ).to.be.revertedWithCustomError(controller, "AlreadyBootstrapped");
    });

    it("should be fully initialized after successful bootstrap", async function () {
      const { controller, deployer } = await loadFixture(deployAllModulesFixture);

      await controller.connect(deployer).bootstrap();

      expect(await controller.isFullyInitialized()).to.be.true;
    });
  });

  describe("Access Control", function () {
    it("should allow admin to grant DEPLOYER_ROLE", async function () {
      const { controller, admin, user } = await loadFixture(deployFixture);

      await controller.connect(admin).grantRole(await controller.DEPLOYER_ROLE(), user.address);
      expect(await controller.hasRole(await controller.DEPLOYER_ROLE(), user.address)).to.be.true;
    });

    it("should allow pause and unpause", async function () {
      const { controller, admin } = await loadFixture(deployFixture);

      await controller.connect(admin).pause();
      expect(await controller.paused()).to.be.true;

      await controller.connect(admin).unpause();
      expect(await controller.paused()).to.be.false;
    });

    it("should revert non-admin pause", async function () {
      const { controller, user } = await loadFixture(deployFixture);
      await expect(
        controller.connect(user).pause()
      ).to.be.revertedWithCustomError(controller, "AccessControlUnauthorizedAccount");
    });
  });
});