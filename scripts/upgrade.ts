import { ethers, upgrades } from "hardhat";

async function main() {
  const proxyAddress = "PROXY_ADDRESS_HERE";

  const TBv2 = await ethers.getContractFactory("TruthBountyToken");

  const upgraded = await upgrades.upgradeProxy(proxyAddress, TBv2);

  console.log("Upgraded at:", await upgraded.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
