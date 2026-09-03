import { IndexerCheckpoint, StorageAdapter } from "./types";

export class CheckpointManager {
  private storage: StorageAdapter;
  private checkpoint: IndexerCheckpoint | null = null;

  constructor(storage: StorageAdapter) {
    this.storage = storage;
  }

  async load(): Promise<void> {
    this.checkpoint = await this.storage.getCheckpoint();
    if (this.checkpoint) {
      console.log(`[checkpoint] resumed from block ${this.checkpoint.blockNumber}`);
    } else {
      console.log("[checkpoint] no checkpoint found, starting fresh");
    }
  }

  get(): IndexerCheckpoint | null {
    return this.checkpoint;
  }

  async update(blockNumber: number, blockHash: string): Promise<void> {
    this.checkpoint = { blockNumber, blockHash, updatedAt: new Date() };
    await this.storage.saveCheckpoint(this.checkpoint);
  }

  getLastBlockNumber(): number {
    return this.checkpoint?.blockNumber ?? 0;
  }

  getLastBlockHash(): string | null {
    return this.checkpoint?.blockHash ?? null;
  }
}
