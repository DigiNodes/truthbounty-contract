import { HardhatUserConfig } from "hardhat/config";
import hardhatToolboxMochaEthersPlugin from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import "@nomicfoundation/hardhat-ignition-ethers";
import * as dotenv from "dotenv";
import "@openzeppelin/hardhat-upgrades";

dotenv.config();

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxMochaEthersPlugin],
  defaultNetwork: "hardhatMainnet",
solidity: {
    version: "0.8.28",
    settings: {
      evmVersion: "cancun",
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      allowUnlimitedContractSize: true,
    },
    optimismSepolia: {
      type: "http",
      url:
        process.env.OPTIMISM_SEPOLIA_RPC_URL || "https://sepolia.optimism.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 11155420,
      gas: "auto",
      gasPrice: process.env.OPTIMISM_SEPOLIA_GAS_PRICE
        ? parseInt(process.env.OPTIMISM_SEPOLIA_GAS_PRICE)
        : undefined,
    },
    optimismMainnet: {
      type: "http",
      url:
        process.env.OPTIMISM_MAINNET_RPC_URL || "https://mainnet.optimism.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      chainId: 10,
      gas: "auto",
      gasPrice: process.env.OPTIMISM_MAINNET_GAS_PRICE
        ? parseInt(process.env.OPTIMISM_MAINNET_GAS_PRICE)
        : undefined,
    },
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      optimisticEthereum: process.env.OPTIMISM_ETHERSCAN_API_KEY || "",
      optimisticSepolia: process.env.OPTIMISM_ETHERSCAN_API_KEY || "",
    },
  },
};

export default config;
