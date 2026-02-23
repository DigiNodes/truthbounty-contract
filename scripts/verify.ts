/**
 * Contract verification script for block explorers (Etherscan, Optimism explorer).
 *
 * Supports verifying after deployment, multiple networks, and optional CI use.
 *
 * @example Single contract (no constructor args)
 *   npx hardhat run scripts/verify.ts --network optimism_sepolia --address 0x...
 *
 * @example Single contract with constructor args (comma-separated)
 *   npx hardhat run scripts/verify.ts --network optimism --address 0x... --constructor-args "0x...,0x..."
 *
 * @example Single contract with explicit contract name
 *   npx hardhat run scripts/verify.ts --network optimism_sepolia --address 0x... --contract "contracts/WeightedStaking.sol:WeightedStaking"
 *
 * @example Batch verify from deployment JSON (weighted staking deployment)
 *   npx hardhat run scripts/verify.ts --network optimism_sepolia --deployment deployment-addresses.json
 *
 * Environment:
 *   OPTIMISM_ETHERSCAN_API_KEY  - API key for Optimism / Optimism Sepolia (Etherscan)
 *   ETHERSCAN_API_KEY           - API key for Ethereum mainnet (optional)
 */

import hre from "hardhat";
import * as fs from "fs";
import * as path from "path";

const SUPPORTED_NETWORKS = ["optimism", "optimism_sepolia"] as const;
type NetworkName = (typeof SUPPORTED_NETWORKS)[number];

interface VerifyOptions {
  address: string;
  contract?: string;
  constructorArguments?: unknown[];
}

interface DeploymentAddresses {
  contracts: {
    token?: string;
    oracle?: string;
    weightedStaking?: string;
    truthBountyWeighted?: string;
  };
}

function parseArgs(): {
  network: string;
  address?: string;
  contract?: string;
  constructorArgs?: string;
  deployment?: string;
  help: boolean;
} {
  const args = process.argv.slice(2);
  const out: {
    network: string;
    address?: string;
    contract?: string;
    constructorArgs?: string;
    deployment?: string;
    help: boolean;
  } = { network: "", help: false };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--network":
        out.network = args[++i] ?? "";
        break;
      case "--address":
        out.address = args[++i];
        break;
      case "--contract":
        out.contract = args[++i];
        break;
      case "--constructor-args":
        out.constructorArgs = args[++i];
        break;
      case "--deployment":
        out.deployment = args[++i];
        break;
      case "--help":
      case "-h":
        out.help = true;
        break;
    }
  }
  return out;
}

function printHelp(): void {
  console.log(`
Contract verification on Etherscan / Optimism explorer.

Usage:
  npx hardhat run scripts/verify.ts --network <network> [options]

Required:
  --network <name>    Network: optimism | optimism_sepolia

Single contract:
  --address <addr>           Contract address to verify
  --contract <name>          Optional: fully qualified contract name (e.g. "contracts/WeightedStaking.sol:WeightedStaking")
  --constructor-args <args>  Optional: comma-separated constructor arguments (no spaces), e.g. "0x...,0x..."

Batch from deployment file:
  --deployment <path>        Path to JSON with contract addresses (e.g. deployment-addresses.json from deploy-weighted-staking)

Constructor args reference (for manual --address + --constructor-args):
  TruthBountyToken          (none)
  MockReputationOracle      (none)
  WeightedStaking           <oracleAddress>
  TruthBountyWeighted       <tokenAddress>,<oracleAddress>
  VerifierSlashing          <stakingAddress>,<adminAddress>
  Staking                   <stakingToken>,<initialLockDuration>

Environment:
  OPTIMISM_ETHERSCAN_API_KEY   Required for Optimism / Optimism Sepolia
  ETHERSCAN_API_KEY            Optional, for Ethereum mainnet

Examples:
  npx hardhat run scripts/verify.ts --network optimism_sepolia --address 0x1234...
  npx hardhat run scripts/verify.ts --network optimism --address 0x... --constructor-args "0xabc...,0xdef..."
  npx hardhat run scripts/verify.ts --network optimism_sepolia --deployment deployment-addresses.json
`);
}

function parseConstructorArgs(str: string): unknown[] {
  return str.split(",").map((s) => {
    const t = s.trim();
    if (t.startsWith("0x")) return t;
    const n = Number(t);
    if (!Number.isNaN(n)) return n;
    return t;
  });
}

async function verifyOne(opts: VerifyOptions): Promise<boolean> {
  const payload: {
    address: string;
    constructorArguments?: unknown[];
    contract?: string;
  } = {
    address: opts.address,
  };
  if (opts.constructorArguments?.length) payload.constructorArguments = opts.constructorArguments;
  if (opts.contract) payload.contract = opts.contract;

  try {
    await hre.run("verify:verify", payload);
    console.log("Verified:", opts.address);
    return true;
  } catch (e: unknown) {
    const err = e as { message?: string };
    if (err.message?.includes("Already Verified")) {
      console.log("Already verified:", opts.address);
      return true;
    }
    console.error("Verification failed for", opts.address, err.message ?? e);
    return false;
  }
}

async function verifyFromDeployment(network: string, deploymentPath: string): Promise<void> {
  const fullPath = path.isAbsolute(deploymentPath) ? deploymentPath : path.resolve(process.cwd(), deploymentPath);
  if (!fs.existsSync(fullPath)) {
    throw new Error(`Deployment file not found: ${fullPath}`);
  }
  const data = JSON.parse(fs.readFileSync(fullPath, "utf-8")) as DeploymentAddresses;
  const { contracts } = data;
  if (!contracts) throw new Error("Deployment file must contain 'contracts' object");

  const tasks: VerifyOptions[] = [];

  if (contracts.token) {
    tasks.push({ address: contracts.token, contract: "contracts/TruthBounty.sol:TruthBountyToken" });
  }
  if (contracts.oracle) {
    tasks.push({ address: contracts.oracle, contract: "contracts/MockReputationOracle.sol:MockReputationOracle" });
  }
  if (contracts.weightedStaking && contracts.oracle) {
    tasks.push({
      address: contracts.weightedStaking,
      contract: "contracts/WeightedStaking.sol:WeightedStaking",
      constructorArguments: [contracts.oracle],
    });
  }
  if (contracts.truthBountyWeighted && contracts.token && contracts.oracle) {
    tasks.push({
      address: contracts.truthBountyWeighted,
      contract: "contracts/TruthBountyWeighted.sol:TruthBountyWeighted",
      constructorArguments: [contracts.token, contracts.oracle],
    });
  }

  if (tasks.length === 0) {
    console.log("No known contract addresses found in deployment file.");
    return;
  }

  console.log(`Verifying ${tasks.length} contract(s) on ${network}...`);
  let ok = 0;
  for (const t of tasks) {
    if (await verifyOne(t)) ok++;
  }
  console.log(`Done: ${ok}/${tasks.length} verified.`);
}

async function main(): Promise<void> {
  const { network, address, contract, constructorArgs, deployment, help } = parseArgs();

  if (help) {
    printHelp();
    process.exit(0);
  }

  if (!network) {
    console.error("Missing --network. Use --help for usage.");
    process.exit(1);
  }

  if (!SUPPORTED_NETWORKS.includes(network as NetworkName)) {
    console.error(`Unsupported network: ${network}. Use one of: ${SUPPORTED_NETWORKS.join(", ")}`);
    process.exit(1);
  }

  // Ensure we run against the requested network (Hardhat injects network from CLI)
  const currentNetwork = await hre.network.name;
  if (currentNetwork !== network) {
    console.error(
      `Network mismatch: script expects --network ${network} but Hardhat is using ${currentNetwork}. Run with: npx hardhat run scripts/verify.ts --network ${network} ...`
    );
    process.exit(1);
  }

  if (deployment) {
    await verifyFromDeployment(network, deployment);
    return;
  }

  if (!address) {
    console.error("Missing --address or --deployment. Use --help for usage.");
    process.exit(1);
  }

  const opts: VerifyOptions = { address };
  if (contract) opts.contract = contract;
  if (constructorArgs) opts.constructorArguments = parseConstructorArgs(constructorArgs);

  const success = await verifyOne(opts);
  process.exit(success ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
