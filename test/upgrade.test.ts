import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

describe("Upgradeable", function () {
  it.skip("preserves storage after upgrade", async () => {
    const [owner] = await ethers.getSigners();
    const TB = await ethers.getContractFactory("TruthBountyToken");

    const proxy = await upgrades.deployProxy(TB, [], {
      initializer: false,
      kind: "uups",
      constructorArgs: [owner.address],
      unsafeAllow: ["constructor", "state-variable-immutable", "state-variable-assignment"],
    });

    await proxy.transfer(
      "0x000000000000000000000000000000000000dEaD",
      100
    );

    const TBv2 = await ethers.getContractFactory("TruthBountyToken");

    const upgraded = await upgrades.upgradeProxy(proxy.target, TBv2, {
      constructorArgs: [owner.address],
      unsafeAllow: ["constructor", "state-variable-immutable", "state-variable-assignment"],
    });

    expect(await upgraded.totalSupply()).to.not.equal(0);
  });
});
