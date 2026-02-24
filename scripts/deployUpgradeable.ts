import { ethers, upgrades } from "hardhat";

async function main() {
  const TB = await ethers.getContractFactory("TruthBountyToken");

  const proxy = await upgrades.deployProxy(TB, [], {
    initializer: "initialize",
    kind: "uups",
  });

  await proxy.waitForDeployment();

  console.log("Proxy deployed to:", await proxy.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
