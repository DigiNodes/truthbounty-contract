/**
 * Settle/resolve a TruthBounty claim.
 * 
 * This script settles a claim after the verification window has closed.
 * It determines the outcome based on votes and calculates rewards/slashes.
 * 
 * @example Settle a claim
 *   CLAIM_ID=1 npx hardhat run scripts/resolveClaim.ts --network optimism_sepolia
 * 
 * @example Settle claim with custom contract address
 *   TRUTH_BOUNTY_CONTRACT_ADDRESS=0x... CLAIM_ID=1 npx hardhat run scripts/resolveClaim.ts --network optimism_sepolia
 * 
 * Environment Variables:
 *   CLAIM_ID - The ID of the claim to settle (required)
 *   TRUTH_BOUNTY_CONTRACT_ADDRESS - Address of the TruthBounty contract
 */

import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("=".repeat(50));
  console.log("⚖️  TruthBounty Claim Settlement");
  console.log("=".repeat(50));
  console.log("Settling account:", deployer.address);
  
  const balance = await deployer.provider.getBalance(deployer.address);
  console.log("Account ETH balance:", ethers.formatEther(balance), "ETH");
  
  // Get TruthBounty contract address
  const truthBountyAddress = process.env.TRUTH_BOUNTY_CONTRACT_ADDRESS;
  if (!truthBountyAddress) {
    console.error("\n❌ Error: TRUTH_BOUNTY_CONTRACT_ADDRESS environment variable is required");
    console.error("Example: export TRUTH_BOUNTY_CONTRACT_ADDRESS=0x...");
    process.exit(1);
  }
  
  console.log("\n📍 TruthBounty contract address:", truthBountyAddress);
  
  // Get claim ID from environment
  const claimIdStr = process.env.CLAIM_ID;
  if (!claimIdStr) {
    console.error("\n❌ Error: CLAIM_ID environment variable is required");
    console.error("Example: CLAIM_ID=1 npx hardhat run scripts/resolveClaim.ts --network optimism_sepolia");
    process.exit(1);
  }
  
  const claimId = BigInt(claimIdStr);
  console.log("📋 Claim ID to settle:", claimId.toString());
  
  // Get the TruthBounty contract
  const truthBounty = await ethers.getContractAt("TruthBounty", truthBountyAddress);
  
  // Retrieve claim information
  let claim;
  try {
    claim = await truthBounty.claims(claimId);
    console.log("\n📊 Current Claim Information:");
    console.log("Submitter:", claim.submitter);
    console.log("Created At:", new Date(Number(claim.createdAt) * 1000).toLocaleString());
    console.log("Verification Window Ends:", new Date(Number(claim.verificationWindowEnd) * 1000).toLocaleString());
    console.log("Already Settled:", claim.settled);
    console.log("Total Staked For:", ethers.formatUnits(claim.totalStakedFor, 18), "BOUNTY");
    console.log("Total Staked Against:", ethers.formatUnits(claim.totalStakedAgainst, 18), "BOUNTY");
    console.log("Total Stake Amount:", ethers.formatUnits(claim.totalStakeAmount, 18), "BOUNTY");
  } catch (error) {
    console.error("\n❌ Error retrieving claim information:", error);
    process.exit(1);
  }
  
  // Check if already settled
  if (claim.settled) {
    console.log("\n⚠️  Warning: This claim has already been settled!");
    console.log("You can now claim rewards using: npx hardhat run scripts/claimRewards.ts");
    process.exit(1);
  }
  
  // Check if verification window has closed
  const currentTime = Math.floor(Date.now() / 1000);
  const verificationEndTime = Number(claim.verificationWindowEnd);
  
  console.log("\n⏰ Timing Information:");
  console.log("Current Time:", new Date(currentTime * 1000).toLocaleString());
  console.log("Verification End Time:", new Date(verificationEndTime * 1000).toLocaleString());
  
  if (currentTime < verificationEndTime) {
    const timeRemaining = verificationEndTime - currentTime;
    const hoursRemaining = Math.floor(timeRemaining / 3600);
    const minutesRemaining = Math.floor((timeRemaining % 3600) / 60);
    
    console.error("\n❌ Error: Verification window has not closed yet!");
    console.error(`Time remaining: ${hoursRemaining}h ${minutesRemaining}m`);
    console.error("Please wait until the verification window closes before settling.");
    process.exit(1);
  }
  
  // Check if there are any votes
  if (claim.totalStakeAmount === BigInt(0)) {
    console.error("\n❌ Error: No votes have been cast on this claim");
    console.error("Cannot settle a claim without votes");
    process.exit(1);
  }
  
  // Predict outcome
  const totalStake = claim.totalStakedFor + claim.totalStakedAgainst;
  const forPercent = (claim.totalStakedFor * BigInt(100)) / totalStake;
  const passed = forPercent >= BigInt(60); // SETTLEMENT_THRESHOLD_PERCENT
  
  console.log("\n📈 Voting Results:");
  console.log("Votes For (Pass):", ethers.formatUnits(claim.totalStakedFor, 18), `BOUNTY (${forPercent.toString()}%)`);
  console.log("Votes Against (Fail):", ethers.formatUnits(claim.totalStakedAgainst, 18), `BOUNTY (${100 - Number(forPercent)}%)`);
  console.log("\n🎯 Predicted Outcome:", passed ? "✅ PASSED" : "❌ FAILED");
  console.log("Threshold: 60% required to pass");
  
  // Settle the claim
  console.log("\n⏳ Settling claim...");
  try {
    const tx = await truthBounty.settleClaim(claimId);
    await tx.wait();
    
    console.log("✅ Claim settled successfully!");
    console.log("Transaction hash:", tx.hash);
    
    // Retrieve updated claim information
    const updatedClaim = await truthBounty.claims(claimId);
    console.log("\n📊 Updated Claim Status:");
    console.log("Settled:", updatedClaim.settled);
    
    // Retrieve settlement result
    const result = await truthBounty.settlementResults(claimId);
    console.log("\n🏆 Settlement Result:");
    console.log("Passed:", result.passed);
    console.log("Total Rewards:", ethers.formatUnits(result.totalRewards, 18), "BOUNTY");
    console.log("Total Slashed:", ethers.formatUnits(result.totalSlashed, 18), "BOUNTY");
    console.log("Winner Stake:", ethers.formatUnits(result.winnerStake, 18), "BOUNTY");
    console.log("Loser Stake:", ethers.formatUnits(result.loserStake, 18), "BOUNTY");
    
    console.log("\n💡 Next Steps:");
    console.log("- Winners can now claim rewards using: npx hardhat run scripts/claimRewards.ts --network <network>");
    console.log(`- Set CLAIM_ID=${claimId.toString()} to claim rewards`);
    
  } catch (error: any) {
    console.error("\n❌ Error settling claim:", error.message || error);
    if (error.message?.includes("Verification window not closed")) {
      console.error("\n💡 Hint: Wait for the verification window to close.");
    } else if (error.message?.includes("Claim already settled")) {
      console.error("\n💡 Hint: This claim has already been settled.");
    } else if (error.message?.includes("No votes cast")) {
      console.error("\n💡 Hint: No one voted on this claim yet.");
    }
    process.exit(1);
  }
  
  console.log("\n" + "=".repeat(50));
  console.log("✨ Claim settlement complete!");
  console.log("=".repeat(50));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Error:", error.message);
    process.exit(1);
  });
