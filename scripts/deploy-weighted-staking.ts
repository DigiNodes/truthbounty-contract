import { ethers } from "hardhat";

async function main() {
  console.log("=".repeat(60));
  console.log("Deploying Weighted Staking System for TruthBounty");
  console.log("=".repeat(60));
  console.log();

  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");
  console.log();

  // 1. Deploy Token
  console.log("📝 Step 1/4: Deploying TruthBountyToken...");
  const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
  const token = await TruthBountyToken.deploy();
  await token.waitForDeployment();
  const tokenAddress = await token.getAddress();
  console.log("   ✅ Token deployed to:", tokenAddress);
  console.log();

  // 2. Deploy Oracle
  console.log("📝 Step 2/4: Deploying MockReputationOracle...");
  const MockReputationOracle = await ethers.getContractFactory("MockReputationOracle");
  const oracle = await MockReputationOracle.deploy();
  await oracle.waitForDeployment();
  const oracleAddress = await oracle.getAddress();
  console.log("   ✅ Oracle deployed to:", oracleAddress);
  console.log();

  // 3. Deploy WeightedStaking Library (Optional)
  console.log("📝 Step 3/4: Deploying WeightedStaking library...");
  const WeightedStaking = await ethers.getContractFactory("WeightedStaking");
  const weightedStaking = await WeightedStaking.deploy(oracleAddress);
  await weightedStaking.waitForDeployment();
  const weightedStakingAddress = await weightedStaking.getAddress();
  console.log("   ✅ WeightedStaking deployed to:", weightedStakingAddress);
  console.log();

  // 4. Deploy TruthBountyWeighted
  console.log("📝 Step 4/4: Deploying TruthBountyWeighted...");
  const TruthBountyWeighted = await ethers.getContractFactory("TruthBountyWeighted");
  const truthBounty = await TruthBountyWeighted.deploy(tokenAddress, oracleAddress, deployer.address, deployer.address);
  await truthBounty.waitForDeployment();
  const truthBountyAddress = await truthBounty.getAddress();
  console.log("   ✅ TruthBountyWeighted deployed to:", truthBountyAddress);
  console.log();

  // 5. Configure System
  console.log("⚙️  Configuring system...");
  console.log();

  // Set reputation bounds (10% to 1000%)
  console.log("   Setting reputation bounds...");
  await truthBounty.setReputationBounds(
    ethers.parseEther("0.1"),   // Min: 10%
    ethers.parseEther("10")     // Max: 1000%
  );
  console.log("   ✅ Reputation bounds: 0.1 - 10.0");

  // Set default reputation (100%)
  console.log("   Setting default reputation...");
  await truthBounty.setDefaultReputationScore(ethers.parseEther("1"));
  console.log("   ✅ Default reputation: 1.0");

  // Fund contract with tokens for rewards
  const fundAmount = ethers.parseEther("100000");
  console.log("   Funding contract with tokens...");
  await token.transfer(truthBountyAddress, fundAmount);
  console.log("   ✅ Contract funded with", ethers.formatEther(fundAmount), "BOUNTY tokens");
  console.log();

  // 6. Verify Configuration
  console.log("🔍 Verifying configuration...");
  const config = await truthBounty.getConfiguration();
  console.log("   Oracle address:      ", config[0]);
  console.log("   Min reputation:      ", ethers.formatEther(config[1]));
  console.log("   Max reputation:      ", ethers.formatEther(config[2]));
  console.log("   Default reputation:  ", ethers.formatEther(config[3]));
  console.log("   Weighted enabled:    ", config[4]);
  console.log();

  // 7. Summary
  console.log("=".repeat(60));
  console.log("✨ Deployment Complete!");
  console.log("=".repeat(60));
  console.log();
  console.log("📋 Contract Addresses:");
  console.log("   Token:                ", tokenAddress);
  console.log("   Oracle:               ", oracleAddress);
  console.log("   WeightedStaking:      ", weightedStakingAddress);
  console.log("   TruthBountyWeighted:  ", truthBountyAddress);
  console.log();
  console.log("💡 Next Steps:");
  console.log("   1. Save these addresses for frontend integration");
  console.log("   2. Verify contracts on block explorer:");
  console.log(`      npx hardhat verify --network <network> ${tokenAddress}`);
  console.log(`      npx hardhat verify --network <network> ${oracleAddress}`);
  console.log(`      npx hardhat verify --network <network> ${weightedStakingAddress} ${oracleAddress}`);
  console.log(`      npx hardhat verify --network <network> ${truthBountyAddress} ${tokenAddress} ${oracleAddress}`);
  console.log("   3. Set initial reputation scores (if using mock oracle)");
  console.log("   4. Transfer ownership to multisig (production)");
  console.log();
  console.log("📖 Documentation:");
  console.log("   - WEIGHTED_STAKING.md for technical details");
  console.log("   - DEPLOYMENT_GUIDE.md for integration guide");
  console.log();

  // Export addresses to JSON file
  const deployment = {
    network: (await ethers.provider.getNetwork()).name,
    timestamp: new Date().toISOString(),
    deployer: deployer.address,
    contracts: {
      token: tokenAddress,
      oracle: oracleAddress,
      weightedStaking: weightedStakingAddress,
      truthBountyWeighted: truthBountyAddress
    },
    configuration: {
      minReputation: "0.1",
      maxReputation: "10.0",
      defaultReputation: "1.0",
      weightedEnabled: true
    }
  };

  const fs = require("fs");
  fs.writeFileSync(
    "deployment-addresses.json",
    JSON.stringify(deployment, null, 2)
  );
  console.log("💾 Deployment info saved to deployment-addresses.json");
  console.log();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:");
    console.error(error);
    process.exit(1);
  });
