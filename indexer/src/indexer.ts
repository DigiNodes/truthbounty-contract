import { ProviderManager } from "./provider";
import { CheckpointManager } from "./checkpoint";
import { EventPipeline } from "./pipeline";
import { IndexerConfig, StorageAdapter, IndexedEvent } from "./types";
import { InMemoryStorage } from "./storage";

export class Indexer {
  private config: IndexerConfig;
  private provider: ProviderManager;
  private checkpoint: CheckpointManager;
  private pipeline: EventPipeline;
  private storage: StorageAdapter;
  private running = false;
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private eventHandlers: Array<(event: IndexedEvent) => Promise<void>> = [];

  constructor(config: IndexerConfig) {
    this.config = config;
    this.storage = new InMemoryStorage();
    this.provider = new ProviderManager(config.rpcUrl, config.wsUrl);
    this.checkpoint = new CheckpointManager(this.storage);
    this.pipeline = new EventPipeline(this.storage, config.contracts);
  }

  onEvent(handler: (event: IndexedEvent) => Promise<void>): void {
    this.eventHandlers.push(handler);
  }

  getStorage(): StorageAdapter {
    return this.storage;
  }

  async start(): Promise<void> {
    this.running = true;
    await this.storage.connect();
    await this.checkpoint.load();

    console.log(`[indexer] starting from block ${this.checkpoint.getLastBlockNumber() || this.config.startBlock}`);

    await this.syncHistorical();

    if (this.provider.hasWebSocket) {
      await this.provider.onNewBlock((blockNumber) => {
        this.onNewBlock(blockNumber).catch((err) =>
          console.error(`[indexer] live block error: ${err}`)
        );
      });
    }

    this.startPolling();
    console.log("[indexer] live listening started");
  }

  async stop(): Promise<void> {
    this.running = false;
    if (this.pollTimer) clearInterval(this.pollTimer);
    this.provider.destroy();
    await this.storage.disconnect();
    console.log("[indexer] stopped");
  }

  private async syncHistorical(): Promise<void> {
    const startBlock = this.checkpoint.getLastBlockNumber() || this.config.startBlock;
    const latestBlock = await this.provider.getBlockNumber();
    const safeLatest = latestBlock - this.config.confirmations;

    if (startBlock >= safeLatest) return;

    console.log(`[indexer] historical sync: blocks ${startBlock} → ${safeLatest}`);

    const batchSize = 1000;
    for (let from = startBlock; from < safeLatest; from += batchSize) {
      if (!this.running) break;
      const to = Math.min(from + batchSize - 1, safeLatest);
      await this.syncBlocks(from, to);
    }
  }

  private async syncBlocks(fromBlock: number, toBlock: number): Promise<void> {
    const logs = await this.pipeline.fetchLogs(this.provider.provider, fromBlock, toBlock);
    if (logs.length === 0) {
      await this.checkpoint.update(toBlock, "");
      return;
    }

    const events = await this.pipeline.processLogs(logs, this.config.chainId);
    await this.pipeline.persistEvents(events);
    await this.runHandlers(events);

    const lastLog = logs[logs.length - 1];
    await this.checkpoint.update(lastLog.blockNumber, lastLog.blockHash);

    console.log(`[indexer] synced blocks ${fromBlock}-${toBlock}: ${events.length} events`);
  }

  private async onNewBlock(blockNumber: number): Promise<void> {
    const cp = this.checkpoint.get();
    if (cp) {
      const reorgBlock = await this.pipeline.detectReorg(
        this.provider.provider,
        cp,
        this.config.maxReorgDepth
      );
      if (reorgBlock !== null) {
        console.log(`[indexer] reorg detected at block ${reorgBlock}, rolling back`);
        await this.syncBlocks(reorgBlock, blockNumber);
        return;
      }
    }

    const fromBlock = this.checkpoint.getLastBlockNumber() + 1;
    if (fromBlock <= blockNumber) {
      await this.syncBlocks(fromBlock, blockNumber);
    }
  }

  private startPolling(): void {
    this.pollTimer = setInterval(async () => {
      if (!this.running) return;
      try {
        const latest = await this.provider.getBlockNumber();
        const safeLatest = latest - this.config.confirmations;
        const lastIndexed = this.checkpoint.getLastBlockNumber();

        if (safeLatest > lastIndexed) {
          await this.onNewBlock(safeLatest);
        }
      } catch (err) {
        console.error(`[indexer] poll error: ${err}`);
      }
    }, this.config.pollIntervalMs);
  }

  private async runHandlers(events: IndexedEvent[]): Promise<void> {
    for (const event of events) {
      for (const handler of this.eventHandlers) {
        await handler(event);
      }
    }
  }
}

export { InMemoryStorage };
