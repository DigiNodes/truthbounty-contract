# 📜 Contract Interaction Scripts - Quick Reference

This guide provides quick examples for interacting with TruthBounty contracts.

## 🚀 Quick Start

### 1. Install Dependencies
```bash
npm install --legacy-peer-deps
```

### 2. Configure Environment
Create a `.env` file or set environment variables:

```bash
# Required: Contract addresses (replace with your deployed addresses)
TRUTH_BOUNTY_TOKEN_ADDRESS=0xYourTokenAddressHere
TRUTH_BOUNTY_CONTRACT_ADDRESS=0xYourTruthBountyAddressHere

# Optional: Custom amounts
AMOUNT=1000
CLAIM_ID=1
```

### 3. Run Scripts

```bash
# Stake tokens
npm run stake --network optimism_sepolia

# Settle a claim
npm run resolve-claim --network optimism_sepolia

# Claim rewards
npm run claim-rewards --network optimism_sepolia
```

---

## 📖 Detailed Usage

### 💰 Staking Tokens

**Purpose:** Stake BOUNTY tokens to participate in verification and governance.

```bash
# Default stake (100 BOUNTY)
npx hardhat run scripts/stake.ts --network optimism_sepolia

# Custom amount
AMOUNT=500 npx hardhat run scripts/stake.ts --network optimism_sepolia

# Using .env file
npx hardhat run scripts/stake.ts --network optimism_sepolia
```

**What happens:**
1. ✅ Checks your BOUNTY token balance
2. ✅ Approves token transfer to contract
3. ✅ Stakes tokens into TruthBounty protocol
4. ✅ Displays your current stake information

**Expected output:**
```
==================================================
🏦 TruthBounty Token Staking
==================================================
Staking account: 0xYourAddress...
Account ETH balance: 0.5 ETH

📍 TruthBountyToken address: 0xTokenAddress...
BOUNTY token balance: 10000.0

💰 Amount to stake: 100 BOUNTY

⏳ Approving token transfer...
✅ Token approval successful

⏳ Staking tokens...
✅ Staking successful!
Transaction hash: 0xTxHash...

📊 Current Stake Information:
Total staked: 100.0 BOUNTY

==================================================
✨ Staking complete!
==================================================
```

---

### ⚖️ Settling Claims

**Purpose:** Resolve a claim after the 7-day verification window closes.

```bash
# Settle claim with ID 1
CLAIM_ID=1 npx hardhat run scripts/resolveClaim.ts --network optimism_sepolia

# With custom contract address
TRUTH_BOUNTY_CONTRACT_ADDRESS=0x... CLAIM_ID=1 npx hardhat run scripts/resolveClaim.ts
```

**Preconditions:**
- ✅ Verification window must be closed (7 days from claim creation)
- ✅ At least one vote must have been cast
- ✅ Claim must not already be settled

**What happens:**
1. ✅ Checks if verification window has closed
2. ✅ Verifies votes have been cast
3. ✅ Predicts outcome (60% threshold to pass)
4. ✅ Settles the claim and calculates rewards/slashes
5. ✅ Displays settlement results

**Expected output:**
```
==================================================
⚖️  TruthBounty Claim Settlement
==================================================
Settling account: 0xYourAddress...

📍 TruthBounty contract address: 0xContractAddress...
📋 Claim ID to settle: 1

📊 Current Claim Information:
Submitter: 0xSubmitterAddress...
Created At: [date]
Verification Window Ends: [date]
Already Settled: false
Total Staked For: 500.0 BOUNTY
Total Staked Against: 200.0 BOUNTY

⏰ Timing Information:
Current Time: [current date]
Verification End Time: [end date]

📈 Voting Results:
Votes For (Pass): 500.0 BOUNTY (71%)
Votes Against (Fail): 200.0 BOUNTY (29%)

🎯 Predicted Outcome: ✅ PASSED
Threshold: 60% required to pass

⏳ Settling claim...
✅ Claim settled successfully!
Transaction hash: 0xTxHash...

🏆 Settlement Result:
Passed: true
Total Rewards: 16.0 BOUNTY
Total Slashed: 20.0 BOUNTY
Winner Stake: 500.0 BOUNTY
Loser Stake: 200.0 BOUNTY

💡 Next Steps:
- Winners can now claim rewards using: npx hardhat run scripts/claimRewards.ts
- Set CLAIM_ID=1 to claim rewards

==================================================
✨ Claim settlement complete!
==================================================
```

---

### 🎁 Claiming Rewards

**Purpose:** Claim rewards and staked tokens after a claim is settled.

```bash
# Claim rewards for claim ID 1
CLAIM_ID=1 npx hardhat run scripts/claimRewards.ts --network optimism_sepolia

# With custom contract address
TRUTH_BOUNTY_CONTRACT_ADDRESS=0x... CLAIM_ID=1 npx hardhat run scripts/claimRewards.ts
```

**Preconditions:**
- ✅ You voted on the claim
- ✅ The claim is settled
- ✅ You voted on the winning side
- ✅ Rewards haven't been claimed yet

**What happens:**
1. ✅ Verifies your vote on the claim
2. ✅ Checks if you're on the winning side
3. ✅ Claims both rewards and staked tokens
4. ✅ Displays updated vote status

**Expected output:**
```
==================================================
🎁 TruthBounty Rewards Claim
==================================================
Claiming account: 0xYourAddress...

📍 TruthBounty contract address: 0xContractAddress...
📋 Claim ID to claim: 1

📊 Claim Information:
Submitter: 0xSubmitterAddress...
Settled: true
Total Staked For: 500.0 BOUNTY
Total Staked Against: 200.0 BOUNTY

🗳️  Your Vote Information:
Voted: true
Support (true=pass, false=fail): true
Stake Amount: 100.0 BOUNTY
Reward Claimed: false
Stake Returned: false

🏆 Settlement Result:
Passed: true
Total Rewards: 16.0 BOUNTY
Total Slashed: 20.0 BOUNTY
Winner Stake: 500.0 BOUNTY

⏳ Claiming rewards...
✅ Rewards claimed successfully!
Transaction hash: 0xTxHash...

📊 Updated Vote Status:
Reward Claimed: true
Stake Returned: true

==================================================
✨ Rewards claim complete!
==================================================
```

---

## 🔍 Troubleshooting

### Common Errors

#### ❌ "Insufficient token balance"
**Solution:** Make sure you have enough BOUNTY tokens in your wallet.
```bash
# Check your balance first
# You need at least the stake amount + gas fees
```

#### ❌ "Verification window not closed"
**Solution:** Wait for the 7-day verification period to end.
```bash
# Use resolveClaim.ts to check timing
CLAIM_ID=1 npx hardhat run scripts/resolveClaim.ts
```

#### ❌ "Not a winner"
**Solution:** You voted on the losing side. Unfortunately, you're not eligible for rewards and will be slashed.

#### ❌ "Rewards already claimed"
**Solution:** You can only claim rewards once per claim. Check your vote status in the script output.

#### ❌ "Claim already settled"
**Solution:** The claim has already been resolved. Proceed to claim rewards using `claimRewards.ts`.

#### ❌ "No votes cast"
**Solution:** No one has voted on this claim yet. Votes are required before settlement.

---

## 📝 Script Reference Table

| Script | Command | Required Env Vars | Optional Env Vars | Purpose |
|--------|---------|-------------------|-------------------|---------|
| **Stake** | `npm run stake` | `TRUTH_BOUNTY_TOKEN_ADDRESS` | `AMOUNT` | Stake BOUNTY tokens |
| **Resolve Claim** | `npm run resolve-claim` | `TRUTH_BOUNTY_CONTRACT_ADDRESS`, `CLAIM_ID` | - | Settle a claim |
| **Claim Rewards** | `npm run claim-rewards` | `TRUTH_BOUNTY_CONTRACT_ADDRESS`, `CLAIM_ID` | - | Claim rewards |
| **Verify** | `npm run verify` | `--address` flag | `--constructor-args` | Verify on explorer |

---

## 🔧 Advanced Usage

### Using Different Networks

```bash
# Optimism Sepolia (testnet)
npx hardhat run scripts/stake.ts --network optimism_sepolia

# Optimism Mainnet
npx hardhat run scripts/stake.ts --network optimism

# Local Hardhat node
npx hardhat run scripts/stake.ts --network localhost
```

### Setting Environment Variables

**Option 1: Inline (Linux/Mac)**
```bash
AMOUNT=500 TRUTH_BOUNTY_TOKEN_ADDRESS=0x... npx hardhat run scripts/stake.ts
```

**Option 2: Inline (Windows PowerShell)**
```powershell
$env:AMOUNT="500"; $env:TRUTH_BOUNTY_TOKEN_ADDRESS="0x..."; npx hardhat run scripts/stake.ts
```

**Option 3: .env file**
```bash
TRUTH_BOUNTY_TOKEN_ADDRESS=0x...
TRUTH_BOUNTY_CONTRACT_ADDRESS=0x...
AMOUNT=500
CLAIM_ID=1
```

Then just run:
```bash
npx hardhat run scripts/stake.ts --network optimism_sepolia
```

---

## 📚 Next Steps

After running these scripts:

1. **Monitor transactions** on Optimism Etherscan
2. **Track your stakes** using the contract view functions
3. **Participate in governance** by voting on claims
4. **Claim rewards** when claims are settled

For more advanced interactions, refer to the contract ABIs and use ethers.js directly.

---

## 🤝 Support

- Check the main [README.md](../README.md) for setup instructions
- Review contract specs in [docs/](../docs/)
- Report issues on GitHub
