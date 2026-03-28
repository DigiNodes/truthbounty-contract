/**
 * Claim rewards from TruthBounty protocol.
 * 
 * This script allows verifiers to claim their rewards after a claim has been settled.
 * Rewards are distributed to verifiers who voted on the winning side of a claim.
 * 
 * @example Claim rewards for a specific claim
 *   CLAIM_ID=1 npx hardhat run scripts/claimRewards.ts --network optimism_sepolia
 * 
 * @example Claim rewards with custom contract addresses
 *   TRUTH_BOUNTY_CONTRACT_ADDRESS=0x... CLAIM_ID=1 npx hardhat run scripts/claimRewards.ts --network optimism_sepolia
 * 
 * Environment Variables:
 *   CLAIM_ID - The ID of the claim to claim rewards for (required)
 *   TRUTH_BOUNTY_CONTRACT_ADDRESS - Address of the TruthBounty contract
 */

import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("=".repeat(50));
  console.log("🎁 TruthBounty Rewards Claim");
  console.log("=".repeat(50));
  console.log("Claiming account:", deployer.address);
  
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
    console.error("Example: CLAIM_ID=1 npx hardhat run scripts/claimRewards.ts --network optimism_sepolia");
    process.exit(1);
  }
  
  const claimId = BigInt(claimIdStr);
  console.log("📋 Claim ID to claim:", claimId.toString());
  
  // Get the TruthBounty contract
  const truthBounty = await ethers.getContractAt("TruthBounty", truthBountyAddress);
  
  // Check if claim exists and is settled
  try {
    const claim = await truthBounty.claims(claimId);
    console.log("\n📊 Claim Information:");
    console.log("Submitter:", claim.submitter);
    console.log("Settled:", claim.settled);
    console.log("Total Staked For:", ethers.formatUnits(claim.totalStakedFor, 18), "BOUNTY");
    console.log("Total Staked Against:", ethers.formatUnits(claim.totalStakedAgainst, 18), "BOUNTY");
    
    if (!claim.settled) {
      console.error("\n⚠️  Warning: This claim has not been settled yet!");
      console.error("You must wait for the verification window to close and settle the claim first.");
    }
  } catch (error) {
    console.error("\n❌ Error retrieving claim information:", error);
  }
  
  // Check vote information
  try {
    const vote = await truthBounty.votes(claimId, deployer.address);
    console.log("\n🗳️  Your Vote Information:");
    console.log("Voted:", vote.voted);
    console.log("Support (true=pass, false=fail):", vote.support);
    console.log("Stake Amount:", ethers.formatUnits(vote.stakeAmount, 18), "BOUNTY");
    console.log("Reward Claimed:", vote.rewardClaimed);
    console.log("Stake Returned:", vote.stakeReturned);
    
    if (!vote.voted) {
      console.error("\n❌ Error: You did not vote on this claim");
      process.exit(1);
    }
    
    if (vote.rewardClaimed) {
      console.log("\n⚠️  Note: Rewards have already been claimed for this vote");
    }
  } catch (error) {
    console.error("\n❌ Error retrieving vote information:", error);
    process.exit(1);
  }
  
  // Check settlement result
  try {
    const result = await truthBounty.settlementResults(claimId);
    console.log("\n🏆 Settlement Result:");
    console.log("Passed:", result.passed);
    console.log("Total Rewards:", ethers.formatUnits(result.totalRewards, 18), "BOUNTY");
    console.log("Total Slashed:", ethers.formatUnits(result.totalSlashed, 18), "BOUNTY");
    console.log("Winner Stake:", ethers.formatUnits(result.winnerStake, 18), "BOUNTY");
  } catch (error) {
    console.error("\n⚠️  Could not retrieve settlement result (may not be settled yet)");
  }
  
  // Claim the rewards
  console.log("\n⏳ Claiming rewards...");
  try {
    const tx = await truthBounty.claimSettlementRewards(claimId);
    await tx.wait();
    
    console.log("✅ Rewards claimed successfully!");
    console.log("Transaction hash:", tx.hash);
    
    // Display updated vote information
    const updatedVote = await truthBounty.votes(claimId, deployer.address);
    console.log("\n📊 Updated Vote Status:");
    console.log("Reward Claimed:", updatedVote.rewardClaimed);
    console.log("Stake Returned:", updatedVote.stakeReturned);
    
  } catch (error: any) {
    console.error("\n❌ Error claiming rewards:", error.message || error);
    if (error.message?.includes("Claim not settled")) {
      console.error("\n💡 Hint: The claim must be settled before rewards can be claimed.");
      console.error("Use: npx hardhat run scripts/resolveClaim.ts --network <network>");
    } else if (error.message?.includes("Not a winner")) {
      console.error("\n💡 Hint: You voted on the losing side and are not eligible for rewards.");
    } else if (error.message?.includes("Rewards already claimed")) {
      console.error("\n💡 Hint: You have already claimed rewards for this claim.");
    }
    process.exit(1);
  }
  
  console.log("\n" + "=".repeat(50));
  console.log("✨ Rewards claim complete!");
  console.log("=".repeat(50));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Error:", error.message);
    process.exit(1);
  });
