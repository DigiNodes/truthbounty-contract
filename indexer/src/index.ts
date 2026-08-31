import { Indexer } from "./indexer";
import { IndexerConfig } from "./types";
import { TRUTH_BOUNTY_ABI, REPUTATION_DECAY_ABI, REPUTATION_SNAPSHOT_ABI } from "./events";

function loadConfig(): IndexerConfig {
  return {
    chainId: parseInt(process.env.CHAIN_ID || "11155420", 10),
    rpcUrl: process.env.RPC_URL || "http://localhost:8545",
    wsUrl: process.env.WS_URL,
    contracts: [
      {
        name: "TruthBountyWeighted",
        address: process.env.TRUTH_BOUNTY_ADDRESS || "",
        abi: TRUTH_BOUNTY_ABI,
        fromBlock: parseInt(process.env.TRUTH_BOUNTY_FROM_BLOCK || "0", 10),
      },
      {
        name: "ReputationDecay",
        address: process.env.REPUTATION_DECAY_ADDRESS || "",
        abi: REPUTATION_DECAY_ABI,
        fromBlock: parseInt(process.env.REPUTATION_DECAY_FROM_BLOCK || "0", 10),
      },
      {
        name: "ReputationSnapshot",
        address: process.env.REPUTATION_SNAPSHOT_ADDRESS || "",
        abi: REPUTATION_SNAPSHOT_ABI,
        fromBlock: parseInt(process.env.REPUTATION_SNAPSHOT_FROM_BLOCK || "0", 10),
      },
    ].filter((c) => c.address),
    startBlock: parseInt(process.env.START_BLOCK || "0", 10),
    checkpointInterval: parseInt(process.env.CHECKPOINT_INTERVAL || "100", 10),
    maxReorgDepth: parseInt(process.env.MAX_REORG_DEPTH || "12", 10),
    pollIntervalMs: parseInt(process.env.POLL_INTERVAL_MS || "5000", 10),
    confirmations: parseInt(process.env.CONFIRMATIONS || "6", 10),
  };
}

async function main() {
  const config = loadConfig();

  if (!config.contracts.length) {
    console.error("No contract addresses configured. Set TRUTH_BOUNTY_ADDRESS, REPUTATION_DECAY_ADDRESS, etc.");
    process.exit(1);
  }

  const indexer = new Indexer(config);

  indexer.onEvent(async (event) => {
    console.log(`[event] ${event.contractName}.${event.eventName} (block ${event.blockNumber})`);
  });

  process.on("SIGINT", async () => {
    console.log("\n[indexer] shutting down...");
    await indexer.stop();
    process.exit(0);
  });

  await indexer.start();
}

main().catch((err) => {
  console.error(`[indexer] fatal: ${err}`);
  process.exit(1);
});
