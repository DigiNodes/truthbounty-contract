import { ethers } from "hardhat";

async function main() {
  const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
  const token = await TruthBountyToken.deploy();

  console.log("Token deployed to:", await token.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});