import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter";
import * as dotenv from "dotenv";
import "@openzeppelin/hardhat-upgrades";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: "0.8.28",
  networks: {
    optimismSepolia: {
      url: process.env.OPTIMISM_SEPOLIA_RPC_URL || "https://sepolia.optimism.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 11155420,
      gas: "auto",
      gasPrice: process.env.OPTIMISM_SEPOLIA_GAS_PRICE ? parseInt(process.env.OPTIMISM_SEPOLIA_GAS_PRICE) : undefined,
    },
    optimismMainnet: {
      url: process.env.OPTIMISM_MAINNET_RPC_URL || "https://mainnet.optimism.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 10,
      gas: "auto",
      gasPrice: process.env.OPTIMISM_MAINNET_GAS_PRICE ? parseInt(process.env.OPTIMISM_MAINNET_GAS_PRICE) : undefined,
    },
  },
  etherscan: {
    apiKey: {
      optimisticEthereum: process.env.OPTIMISM_ETHERSCAN_API_KEY || "",
    }
  },
  gasReporter: {
    enabled: true,
    outputFile: ".gas-reports.json",
    noColors: true,
    excludeContracts: [],
    snapshots: {
      outputFile: ".gas-snapshots.json"
    }
  }
};

export default config;
