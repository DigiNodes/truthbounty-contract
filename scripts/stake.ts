/**
 * Stake tokens into the TruthBounty protocol.
 * 
 * This script allows users to stake BOUNTY tokens to participate in verification.
 * Staked tokens determine voting weight and are subject to slashing for malicious behavior.
 * 
 * @example Stake tokens (local Hardhat node)
 *   npx hardhat run scripts/stake.ts --network localhost
 * 
 * @example Stake tokens on Optimism Sepolia
 *   npx hardhat run scripts/stake.ts --network optimism_sepolia
 * 
 * @example Stake custom amount
 *   AMOUNT=1000 npx hardhat run scripts/stake.ts --network optimism_sepolia
 * 
 * Environment Variables:
 *   AMOUNT - Amount of tokens to stake (default: 100)
 *   TRUTH_BOUNTY_TOKEN_ADDRESS - Address of the TruthBountyToken contract
 */

import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("=".repeat(50));
  console.log("🏦 TruthBounty Token Staking");
  console.log("=".repeat(50));
  console.log("Staking account:", deployer.address);
  
  const balance = await deployer.provider.getBalance(deployer.address);
  console.log("Account ETH balance:", ethers.formatEther(balance), "ETH");
  
  // Get token address from environment or use default
  const tokenAddress = process.env.TRUTH_BOUNTY_TOKEN_ADDRESS;
  if (!tokenAddress) {
    console.error("\n❌ Error: TRUTH_BOUNTY_TOKEN_ADDRESS environment variable is required");
    console.error("Example: export TRUTH_BOUNTY_TOKEN_ADDRESS=0x...");
    process.exit(1);
  }
  
  console.log("\n📍 TruthBountyToken address:", tokenAddress);
  
  // Get the token contract
  const tokenContract = await ethers.getContractAt("TruthBountyToken", tokenAddress);
  
  // Check token balance
  const tokenBalance = await tokenContract.balanceOf(deployer.address);
  console.log("BOUNTY token balance:", ethers.formatUnits(tokenBalance, 18));
  
  // Get stake amount from environment or use default
  const stakeAmount = process.env.AMOUNT ? BigInt(process.env.AMOUNT) : BigInt(100);
  const stakeAmountWei = ethers.parseUnits(stakeAmount.toString(), 18);
  
  console.log("\n💰 Amount to stake:", stakeAmount, "BOUNTY");
  
  // Check if user has enough tokens
  if (tokenBalance < stakeAmountWei) {
    console.error("\n❌ Error: Insufficient token balance");
    console.error("Required:", ethers.formatUnits(stakeAmountWei, 18), "BOUNTY");
    console.error("Available:", ethers.formatUnits(tokenBalance, 18), "BOUNTY");
    process.exit(1);
  }
  
  // Approve the token transfer
  console.log("\n⏳ Approving token transfer...");
  const approveTx = await tokenContract.approve(tokenAddress, stakeAmountWei);
  await approveTx.wait();
  console.log("✅ Token approval successful");
  
  // Stake the tokens
  console.log("\n⏳ Staking tokens...");
  const stakeTx = await tokenContract.stake(stakeAmountWei);
  await stakeTx.wait();
  
  console.log("✅ Staking successful!");
  console.log("Transaction hash:", stakeTx.hash);
  
  // Display stake information
  const stakeInfo = await tokenContract.verifierStake(deployer.address);
  console.log("\n📊 Current Stake Information:");
  console.log("Total staked:", ethers.formatUnits(stakeInfo, 18), "BOUNTY");
  
  console.log("\n" + "=".repeat(50));
  console.log("✨ Staking complete!");
  console.log("=".repeat(50));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Error:", error.message);
    process.exit(1);
  });
