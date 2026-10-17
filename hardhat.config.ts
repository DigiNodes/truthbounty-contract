import { HardhatUserConfig } from "hardhat/config";
import hardhatToolboxMochaEthers from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import hardhatIgnitionEthers from "@nomicfoundation/hardhat-ignition-ethers";
import hardhatUpgrades from "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";

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
    hardhat: {
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
        process.env.OPTIMISM_SEPOLIA_RPC_URL || "https://sepolia.optimism.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : "remote",
      chainId: 11155420,
      gas: "auto",
      gasPrice: process.env.OPTIMISM_SEPOLIA_GAS_PRICE
        ? Number(process.env.OPTIMISM_SEPOLIA_GAS_PRICE)
        : undefined,
    },
    optimismMainnet: {
      type: "http",
      url:
        process.env.OPTIMISM_MAINNET_RPC_URL || "https://mainnet.optimism.io",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : "remote",
      chainId: 10,
      gas: "auto",
      gasPrice: process.env.OPTIMISM_MAINNET_GAS_PRICE
        ? Number(process.env.OPTIMISM_MAINNET_GAS_PRICE)
        : undefined,
    },
  },
  verify: {
    etherscan: {
      apiKey: process.env.ETHERSCAN_API_KEY || "",
    },
  },
};

export default config;