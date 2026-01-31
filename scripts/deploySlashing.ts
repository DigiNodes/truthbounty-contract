import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying VerifierSlashing with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  // Deploy or get existing contracts
  const stakingAddress = process.env.STAKING_CONTRACT_ADDRESS;
  const adminAddress = process.env.ADMIN_ADDRESS || deployer.address;
  const settlementAddress = process.env.SETTLEMENT_CONTRACT_ADDRESS;

  if (!stakingAddress) {
    throw new Error("STAKING_CONTRACT_ADDRESS environment variable is required");
  }

  console.log("Using staking contract at:", stakingAddress);
  console.log("Using admin address:", adminAddress);

  // Deploy VerifierSlashing
  const VerifierSlashing = await ethers.getContractFactory("VerifierSlashing");
  const slashing = await VerifierSlashing.deploy(stakingAddress, adminAddress);

  await slashing.waitForDeployment();

  console.log("VerifierSlashing deployed to:", await slashing.getAddress());

  // Set up the slashing contract in the staking contract
  const Staking = await ethers.getContractFactory("Staking");
  const staking = Staking.attach(stakingAddress);

  console.log("Setting slashing contract in staking contract...");
  const tx1 = await staking.setSlashingContract(await slashing.getAddress());
  await tx1.wait();
  console.log("Slashing contract set in staking contract");

  // Grant settlement role if settlement contract address is provided
  if (settlementAddress) {
    console.log("Granting settlement role to:", settlementAddress);
    const ADMIN_ROLE = await slashing.ADMIN_ROLE();
    
    // Check if deployer has admin role
    const hasAdminRole = await slashing.hasRole(ADMIN_ROLE, deployer.address);
    
    if (hasAdminRole) {
      const tx2 = await slashing.grantSettlementRole(settlementAddress);
      await tx2.wait();
      console.log("Settlement role granted to:", settlementAddress);
    } else {
      console.log("Warning: Deployer doesn't have admin role. Settlement role must be granted by admin.");
    }
  }

  // Display configuration
  console.log("\n=== Deployment Summary ===");
  console.log("VerifierSlashing:", await slashing.getAddress());
  console.log("Staking Contract:", stakingAddress);
  console.log("Admin Address:", adminAddress);
  console.log("Max Slash Percentage:", await slashing.maxSlashPercentage(), "%");
  console.log("Slash Cooldown:", await slashing.slashCooldown(), "seconds");

  // Verification instructions
  console.log("\n=== Next Steps ===");
  console.log("1. Verify the contract on Etherscan:");
  console.log(`   npx hardhat verify --network <network> ${await slashing.getAddress()} ${stakingAddress} ${adminAddress}`);
  console.log("2. Grant settlement role to your settlement contract:");
  console.log(`   slashing.grantSettlementRole("${settlementAddress || '<SETTLEMENT_CONTRACT_ADDRESS>'}")`);
  console.log("3. Update your settlement contract to use the new slashing mechanism");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });