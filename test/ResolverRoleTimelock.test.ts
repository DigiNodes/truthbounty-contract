import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

const TWO_DAYS = 2 * 24 * 60 * 60;

async function deployFixture() {
  const [admin, resolver, other] = await ethers.getSigners();

  const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
  const token = await TruthBountyToken.deploy(admin.address);

  const Staking = await ethers.getContractFactory("Staking");
  const staking = await Staking.deploy(await token.getAddress(), 86400, admin.address);

  const VerifierSlashing = await ethers.getContractFactory("VerifierSlashing");
  const slashing = await VerifierSlashing.deploy(await staking.getAddress(), admin.address, admin.address);

  const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
  const oracle = await MockReputationOracle.deploy();

  const TruthBountyWeighted = await ethers.getContractFactory("TruthBountyWeighted");
  const weighted = await TruthBountyWeighted.deploy(
    await token.getAddress(),
    await oracle.getAddress(),
    admin.address,
    admin.address,
  );

  return { admin, resolver, other, token, staking, slashing, weighted };
}

async function executeGrant(contract: any, admin: any, account: string) {
  await contract.connect(admin).scheduleResolverRoleGrant(account);
  await time.increase(TWO_DAYS);
  await contract.executeResolverRoleGrant(account);
}

describe("RESOLVER_ROLE timelock", function () {
  it("blocks direct RESOLVER_ROLE grants and requires delayed execution", async function () {
    const { admin, resolver, slashing } = await loadFixture(deployFixture);
    const role = await slashing.RESOLVER_ROLE();

    await expect(slashing.connect(admin).grantRole(role, resolver.address))
      .to.be.revertedWithCustomError(slashing, "ResolverRoleChangeRequiresTimelock");

    const tx = await slashing.connect(admin).scheduleResolverRoleGrant(resolver.address);
    await expect(tx)
      .to.emit(slashing, "ResolverRoleChangeScheduled")
      .withArgs(await slashing.resolverRoleChangeId(resolver.address, true), resolver.address, true, anyValue);

    expect(await slashing.hasRole(role, resolver.address)).to.equal(false);
    await expect(slashing.executeResolverRoleGrant(resolver.address))
      .to.be.revertedWithCustomError(slashing, "ResolverRoleChangeNotReady");

    await time.increase(TWO_DAYS);
    await expect(slashing.executeResolverRoleGrant(resolver.address))
      .to.emit(slashing, "ResolverRoleChangeExecuted");
    expect(await slashing.hasRole(role, resolver.address)).to.equal(true);
  });

  it("blocks direct RESOLVER_ROLE revokes and requires delayed execution", async function () {
    const { admin, resolver, slashing } = await loadFixture(deployFixture);
    const role = await slashing.RESOLVER_ROLE();
    await executeGrant(slashing, admin, resolver.address);

    await expect(slashing.connect(admin).revokeRole(role, resolver.address))
      .to.be.revertedWithCustomError(slashing, "ResolverRoleChangeRequiresTimelock");

    await slashing.connect(admin).scheduleResolverRoleRevoke(resolver.address);
    expect(await slashing.hasRole(role, resolver.address)).to.equal(true);

    await time.increase(TWO_DAYS);
    await slashing.executeResolverRoleRevoke(resolver.address);
    expect(await slashing.hasRole(role, resolver.address)).to.equal(false);
  });

  it("keeps non-resolver role changes immediate", async function () {
    const { admin, resolver, slashing } = await loadFixture(deployFixture);
    const pauserRole = await slashing.PAUSER_ROLE();

    await slashing.connect(admin).grantRole(pauserRole, resolver.address);
    expect(await slashing.hasRole(pauserRole, resolver.address)).to.equal(true);

    await slashing.connect(admin).revokeRole(pauserRole, resolver.address);
    expect(await slashing.hasRole(pauserRole, resolver.address)).to.equal(false);
  });

  it("applies the same timelock invariant to resolver-bearing protocol modules", async function () {
    const { admin, resolver, token, staking, weighted } = await loadFixture(deployFixture);

    for (const contract of [token, staking, weighted]) {
      const role = await contract.RESOLVER_ROLE();
      await expect(contract.connect(admin).grantRole(role, resolver.address))
        .to.be.revertedWithCustomError(contract, "ResolverRoleChangeRequiresTimelock");

      await executeGrant(contract, admin, resolver.address);
      expect(await contract.hasRole(role, resolver.address)).to.equal(true);
    }
  });

  it("setSettlementContract and setSlashingContract schedule resolver changes instead of granting instantly", async function () {
    const { admin, resolver, token, staking } = await loadFixture(deployFixture);
    const resolverRole = await token.RESOLVER_ROLE();

    await token.connect(admin).setSettlementContract(resolver.address);
    expect(await token.hasRole(resolverRole, resolver.address)).to.equal(false);

    await time.increase(TWO_DAYS);
    await token.executeResolverRoleGrant(resolver.address);
    expect(await token.hasRole(resolverRole, resolver.address)).to.equal(true);

    const stakingResolverRole = await staking.RESOLVER_ROLE();
    await staking.connect(admin).setSlashingContract(resolver.address);
    expect(await staking.hasRole(stakingResolverRole, resolver.address)).to.equal(false);

    await time.increase(TWO_DAYS);
    await staking.executeResolverRoleGrant(resolver.address);
    expect(await staking.hasRole(stakingResolverRole, resolver.address)).to.equal(true);
  });

  it("allows admin cancellation before a resolver role change becomes executable", async function () {
    const { admin, resolver, slashing } = await loadFixture(deployFixture);
    await slashing.connect(admin).scheduleResolverRoleGrant(resolver.address);
    await slashing.connect(admin).cancelResolverRoleChange(resolver.address, true);

    await time.increase(TWO_DAYS);
    await expect(slashing.executeResolverRoleGrant(resolver.address))
      .to.be.revertedWithCustomError(slashing, "ResolverRoleChangeNotPending");
  });
});
