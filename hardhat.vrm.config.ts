// hardhat.vrm.config.ts — isolated config for VerificationRoundManager tests
// Compiles only the contracts required for V2-SC-011 tests, avoiding
// pre-existing broken contracts (syntax errors, OZ v4/v5 API mismatches)
// that exist in the main contracts/ directory.
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ignition-ethers";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      evmVersion: "cancun",
      viaIR: true,
      optimizer: { enabled: true, runs: 200 },
    },
  },
  paths: {
    sources: "./contracts-vrm",
    tests: "./test",
    cache: "./cache-vrm",
    artifacts: "./artifacts-vrm",
  },
  networks: {
    hardhat: { allowUnlimitedContractSize: true },
  },
};

export default config;
