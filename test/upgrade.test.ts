import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

describe("Upgradeable", function () {
  it("preserves storage after upgrade", async () => {
    const TB = await ethers.getContractFactory("TruthBountyToken");

    const proxy = await upgrades.deployProxy(TB, [], {
      initializer: "initialize",
      kind: "uups",
    });

    await proxy.transfer(
      "0x000000000000000000000000000000000000dEaD",
      100
    );

    const TBv2 = await ethers.getContractFactory("TruthBountyToken");

    const upgraded = await upgrades.upgradeProxy(proxy.target, TBv2);

    expect(await upgraded.totalSupply()).to.not.equal(0);
  });
});
