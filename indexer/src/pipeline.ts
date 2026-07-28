import { ethers } from "ethers";
import { IndexedEvent, ContractConfig, StorageAdapter, IndexerCheckpoint } from "./types";

export class EventPipeline {
  private storage: StorageAdapter;
  private contracts: ContractConfig[];

  constructor(storage: StorageAdapter, contracts: ContractConfig[]) {
    this.storage = storage;
    this.contracts = contracts;
  }

  async fetchLogs(
    provider: ethers.Provider,
    fromBlock: number,
    toBlock: number
  ): Promise<ethers.Log[]> {
    const logs: ethers.Log[] = [];
    for (const contract of this.contracts) {
      const contractLogs = await provider.getLogs({
        address: contract.address,
        fromBlock,
        toBlock,
      });
      logs.push(...contractLogs);
    }
    return logs;
  }

  async processLogs(
    logs: ethers.Log[],
    chainId: number
  ): Promise<IndexedEvent[]> {
    const txHashes = logs.map((l) => l.transactionHash);
    const duplicates = await this.storage.getDuplicateEvents(txHashes);

    const events: IndexedEvent[] = [];
    for (const log of logs) {
      const key = `${log.transactionHash}:${log.index}`;
      if (duplicates.has(key)) continue;

      const contractConfig = this.contracts.find(
        (c) => c.address.toLowerCase() === log.address.toLowerCase()
      );
      if (!contractConfig) continue;

      const iface = new ethers.Interface(contractConfig.abi);
      let parsed: ethers.LogDescription | null;
      try {
        parsed = iface.parseLog({ data: log.data, topics: [...log.topics] });
      } catch {
        continue;
      }
      if (!parsed) continue;

      const block = await log.getBlock();
      events.push({
        chainId,
        blockNumber: log.blockNumber,
        blockHash: log.blockHash,
        transactionHash: log.transactionHash,
        logIndex: log.index,
        contractName: contractConfig.name,
        contractAddress: log.address,
        eventName: parsed.name,
        args: Object.fromEntries(
          Object.entries(parsed.args).filter(
            ([k]) => isNaN(Number(k))
          )
        ),
        timestamp: block?.timestamp ?? 0,
        processedAt: new Date(),
      });
    }
    return events;
  }

  async persistEvents(events: IndexedEvent[]): Promise<void> {
    if (events.length === 0) return;
    await this.storage.saveEvents(events);
  }

  async detectReorg(
    provider: ethers.Provider,
    checkpoint: IndexerCheckpoint,
    maxDepth: number
  ): Promise<number | null> {
    for (let depth = 0; depth < maxDepth; depth++) {
      const blockNumber = checkpoint.blockNumber - depth;
      if (blockNumber < 0) break;

      const block = await provider.getBlock(blockNumber);
      if (!block) continue;

      if (block.hash !== checkpoint.blockHash) {
        return blockNumber;
      }
    }
    return null;
  }
}
