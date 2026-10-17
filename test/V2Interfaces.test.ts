import { expect } from "chai";
import { ethers, artifacts } from "hardhat";
import { Interface } from "ethers";

describe("TruthBounty V2 canonical interfaces", function () {
  it("exposes ERC-165 identifiers through a representative fixture", async function () {
    const fixture = await (await ethers.getContractFactory("V2ConformanceFixture")).deploy();
    expect(await fixture.supportsInterface("0x01ffc9a7")).to.equal(true);
    expect(await fixture.supportsInterface("0xffffffff")).to.equal(false);
  });

  it("keeps public function selectors unique within each canonical interface", async function () {
    const names = ["IConfiguration", "IModuleRegistry", "IClaims", "IEvidence", "IStakeCustody", "IVerification", "IAggregation", "ISettlement", "IDisputes", "IRewards", "ISlashing", "ITreasury", "IReputationRoots", "IGovernanceHooks", "IEmergencyControls"];
    for (const name of names) {
      const artifact = await artifacts.readArtifact(name);
      const selectors = artifact.abi.filter((item: any) => item.type === "function").map((item: any) => new Interface([item]).getFunction(item.name)!.selector);
      expect(new Set(selectors).size, `${name} has a selector collision`).to.equal(selectors.length);
    }
  });

  it("does not include deprecated authority aliases or push payout methods", async function () {
    const artifact = await artifacts.readArtifact("ICanonicalV2");
    const names = artifact.abi.filter((item: any) => item.type === "function").map((item: any) => item.name);
    for (const deprecated of ["resolveClaim", "adminResolve", "guardianSettle", "batchPayout", "emergencyWithdraw"]) {
      expect(names).not.to.include(deprecated);
    }
  });

});
