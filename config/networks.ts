export const COMPILER_SETTINGS = {
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
};

export interface NetworkConfig {
  chainId: number;
  defaultRpcUrl: string;
  rpcUrlEnv?: string;
}

export const NETWORKS: Record<string, NetworkConfig> = {
  hardhat: {
    chainId: 31337,
    defaultRpcUrl: "",
  },
  hardhatMainnet: {
    chainId: 31337,
    defaultRpcUrl: "",
  },
  optimismSepolia: {
    chainId: 11155420,
    defaultRpcUrl: "https://sepolia.optimism.io",
    rpcUrlEnv: "OPTIMISM_SEPOLIA_RPC_URL",
  },
  optimismMainnet: {
    chainId: 10,
    defaultRpcUrl: "https://mainnet.optimism.io",
    rpcUrlEnv: "OPTIMISM_MAINNET_RPC_URL",
  },
};

export const RESOLVE_NETWORK_ALIAS: Record<string, string> = {
  optimism_sepolia: "optimismSepolia",
  optimism_mainnet: "optimismMainnet",
};
