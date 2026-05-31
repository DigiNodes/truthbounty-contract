import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

describe("Upgradeable", function () {
  it("preserves storage after upgrade", async () => {
    const MockUpgradeable = await ethers.getContractFactory("MockUpgradeable");

    const proxy = await upgrades.deployProxy(MockUpgradeable, [42], {
      initializer: "initialize",
      kind: "uups",
    });

    expect(await proxy.value()).to.equal(42);

    await proxy.setValue(100);
    expect(await proxy.value()).to.equal(100);

    const MockUpgradeableV2 = await ethers.getContractFactory("MockUpgradeable");

    const upgraded = await upgrades.upgradeProxy(proxy.target, MockUpgradeableV2);

    expect(await upgraded.value()).to.equal(100);
  });
});
