# Contract verification

Contracts can be verified on block explorers (Etherscan, Optimism explorer) using the shared script `scripts/verify.ts`.

---

## ✅ PR checklist (acceptance criteria)

Use this to confirm the PR meets the issue requirements before submitting.

| Criterion | How to confirm |
|-----------|----------------|
| **Contracts verified successfully** | Run a real verification (see [Confirming it works](#confirming-it-works) below). At least one contract verified on Optimism or Optimism Sepolia, or run the script and confirm it reaches the Etherscan API (success or “Already Verified”). |
| **Parameters documented** | ✅ Parameters table in this doc, constructor-args reference, env vars, and `npm run verify -- --help` in the script. |
| **Script reusable** | ✅ Single-contract and batch modes, `--network` for multiple chains, usable from CLI and CI (exit codes 0/1). |

**Objectives**

| Objective | Evidence |
|-----------|----------|
| Verify after deployment | Script supports `--address` + `--constructor-args` and `--deployment <json>` for post-deploy runs. |
| Multi-network support | `--network optimism` and `--network optimism_sepolia`; config has `optimisticEthereum` and `optimisticSepolia` API keys. |
| CI integration optional | Can run in CI with `npm run verify -- --network <net> --deployment deployment-addresses.json`; no CI file required in this repo. |

---

## Confirming it works

**Prerequisite:** Run `npm install` so `hardhat` is available (e.g. `npm run verify` uses the local Hardhat).

### 1. Quick checks (no API key or deployment needed)

Run these locally to confirm the script and docs work:

```bash
# Help and usage (script runs, help text matches VERIFICATION.md)
npm run verify -- --help

# Must require --network
npm run verify -- --address 0x0000000000000000000000000000000000000001
# Expected: "Missing --network" and exit 1

# Must reject unknown network
npm run verify -- --network invalid_net --address 0x0000000000000000000000000000000000000001
# Expected: "Unsupported network" and exit 1

# Batch mode with missing file
npm run verify -- --network optimism_sepolia --deployment does-not-exist.json
# Expected: "Deployment file not found" and exit 1
```

If these behave as above, the script is wired correctly and parameters are enforced.

### 2. Full verification (requires API key + deployed contract)

To confirm **contracts verify successfully** on a block explorer:

1. **Get an Etherscan API key**  
   [etherscan.io/myapikey](https://etherscan.io/myapikey) (same key works for Optimism Sepolia).

2. **Set the key**
   ```bash
   export OPTIMISM_ETHERSCAN_API_KEY=your_key_here
   ```

3. **Deploy (if you don’t have addresses yet)**  
   e.g. on Optimism Sepolia:
   ```bash
   npx hardhat run scripts/deploy-weighted-staking.ts --network optimism_sepolia
   ```
   This creates `deployment-addresses.json`.

4. **Run verification**
   - **Batch (recommended):**
     ```bash
     npm run verify -- --network optimism_sepolia --deployment deployment-addresses.json
     ```
   - **Single contract:**
     ```bash
     npm run verify -- --network optimism_sepolia --address <TOKEN_ADDRESS>
     ```

5. **Check the explorer**  
   Open the contract on [sepolia-optimistic.etherscan.io](https://sepolia-optimistic.etherscan.io) and confirm the “Contract” tab shows verified source (checkmark).

Once one of these flows succeeds (or returns “Already Verified”), you’ve met **“Contracts verified successfully”** for the PR.

---

## Objectives

- **Verify after deployment** – Run the script once deployment is complete (or use batch mode with a deployment JSON).
- **Multi-network** – Supports Optimism and Optimism Sepolia (Etherscan API).
- **CI integration** – Optional: run in CI after deploy (e.g. `npm run verify -- --network optimism_sepolia --deployment deployment-addresses.json`).

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--network` | Yes | Network: `optimism` or `optimism_sepolia` |
| `--address` | Yes* | Contract address (for single-contract verification). *Not required if `--deployment` is set. |
| `--contract` | No | Fully qualified contract name, e.g. `contracts/WeightedStaking.sol:WeightedStaking`. Omit to use auto-detection. |
| `--constructor-args` | No | Comma-separated constructor arguments (no spaces), e.g. `"0x...,0x..."`. |
| `--deployment` | No | Path to a deployment JSON (e.g. `deployment-addresses.json`) to verify all known contracts in one run. |
| `--help` / `-h` | No | Print usage and exit. |

## Environment variables

| Variable | Required for | Description |
|----------|----------------|-------------|
| `OPTIMISM_ETHERSCAN_API_KEY` | Optimism / Optimism Sepolia | Etherscan API key (same key works for both). Create at [etherscan.io/myapikey](https://etherscan.io/myapikey). |
| `ETHERSCAN_API_KEY` | Ethereum mainnet | Only if you add mainnet and verify there. |

## Constructor args reference

For manual `--address` + `--constructor-args`:

| Contract | Constructor arguments |
|----------|------------------------|
| TruthBountyToken | (none) |
| MockReputationOracle | (none) |
| WeightedStaking | `oracleAddress` |
| TruthBountyWeighted | `tokenAddress`,`oracleAddress` |
| VerifierSlashing | `stakingAddress`,`adminAddress` |
| Staking | `stakingToken`,`initialLockDuration` |

## Usage examples

Single contract (no constructor args):

```bash
npm run verify -- --network optimism_sepolia --address 0x...
```

Single contract with constructor args:

```bash
npm run verify -- --network optimism --address 0x... --constructor-args "0xabc...,0xdef..."
```

Batch verify from deployment file (e.g. after `deploy-weighted-staking`):

```bash
npm run verify -- --network optimism_sepolia --deployment deployment-addresses.json
```

Help:

```bash
npm run verify -- --help
```

Or with Hardhat directly:

```bash
npx hardhat run scripts/verify.ts --network optimism_sepolia --address 0x...
```

## Targets

- **Etherscan** – Used for Ethereum mainnet when `ETHERSCAN_API_KEY` is set.
- **Optimism explorer** – Optimism and Optimism Sepolia use Etherscan’s API (optimistic.etherscan.io, sepolia-optimistic.etherscan.io) with `OPTIMISM_ETHERSCAN_API_KEY`.

## Reusability

- Use the same script for local runs, one-off verification, or CI.
- For CI: run after deployment and pass `--network` and either `--address` + `--constructor-args` or `--deployment <path>`.
- Deployment scripts (e.g. `deploy-weighted-staking.ts`) write `deployment-addresses.json`; point `--deployment` at that file for batch verification.
