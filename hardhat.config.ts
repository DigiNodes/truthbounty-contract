import { HardhatUserConfig } from "hardhat/config";
import hardhatToolboxMochaEthers from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import hardhatIgnitionEthers from "@nomicfoundation/hardhat-ignition-ethers";
import hardhatUpgrades from "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";

import {
  NETWORKS,
  RESOLVE_NETWORK_ALIAS,
} from "./config/networks";

export const COMPILER_SETTINGS = {
  version: "0.8.28",
  settings: {
    evmVersion: "cancun",
    viaIR: true,
    optimizer: {
      enabled: true,
      runs: 200,
    },
    // Required so `scripts/validateStorageLayouts.ts` (V2-SC-046) can read
    // each contract's storage layout from the build-info output.
    outputSelection: {
      "*": {
        "*": ["storageLayout"],
      },
    },
  },
};

for (const key of Object.keys(NETWORKS)) {
  const network = NETWORKS[key];
  if (network.rpcUrlEnv && !network.defaultRpcUrl) {
    throw new Error(`Network ${key} is missing a defaultRpcUrl`);
  }
}

dotenv.config();

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxMochaEthers, hardhatIgnitionEthers, hardhatUpgrades],
  solidity: {
    version: "0.8.28",
    settings: {
      evmVersion: "cancun",
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200,
      },
      outputSelection: {
        "*": {
          "*": ["storageLayout"],
        },
      },
    },
  },
  networks: {
    hardhat:{
      type: "edr-simulated",
      chainId: 31337,
      allowUnlimitedContractSize: true,
    },
    hardhatMainnet: {
      type: "edr-simulated",
      chainId: 31337,
      allowUnlimitedContractSize: true,
    },
    optimismSepolia: {
      type: "http",
      url:
        process.env.OPTIMISM_SEPOLIA_RPC_URL ||
        NETWORKS.optimismSepolia.defaultRpcUrl,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : "remote",
      chainId: NETWORKS.optimismSepolia.chainId,
      gas: "auto",
      gasPrice: process.env.OPTIMISM_SEPOLIA_GAS_PRICE
        ? parseInt(process.env.OPTIMISM_SEPOLIA_GAS_PRICE)
        : undefined,
    },
    optimismMainnet: {
      type: "http",
      url:
        process.env.OPTIMISM_MAINNET_RPC_URL ||
        NETWORKS.optimismMainnet.defaultRpcUrl,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : "remote",
      chainId: NETWORKS.optimismMainnet.chainId,
      gas: "auto",
      gasPrice: process.env.OPTIMISM_MAINNET_GAS_PRICE
        ? parseInt(process.env.OPTIMISM_MAINNET_GAS_PRICE)
        : undefined,
    },
  },
  verify: {
    etherscan: {
      apiKey: process.env.ETHERSCAN_API_KEY || "",
    },
  },
};

// Normalize legacy / aliased network names (e.g. `optimism_sepolia` -> `optimismSepolia`).
// Hardhat does not expose a public alias API, so we export the mapping for tooling and
// deployment scripts to resolve network names consistently.
export const networkAliases = RESOLVE_NETWORK_ALIAS;

export default config;
