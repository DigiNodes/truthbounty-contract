import { IndexedEvent, IndexerCheckpoint, StorageAdapter } from "./types";

export class InMemoryStorage implements StorageAdapter {
  private events: IndexedEvent[] = [];
  private checkpoint: IndexerCheckpoint | null = null;

  async connect(): Promise<void> {}
  async disconnect(): Promise<void> {}

  async saveEvents(events: IndexedEvent[]): Promise<void> {
    this.events.push(...events);
  }

  async getDuplicateEvents(txHashes: string[]): Promise<Set<string>> {
    const seen = new Set<string>();
    for (const event of this.events) {
      const key = `${event.transactionHash}:${event.logIndex}`;
      seen.add(key);
    }
    return seen;
  }

  async getCheckpoint(): Promise<IndexerCheckpoint | null> {
    return this.checkpoint;
  }

  async saveCheckpoint(cp: IndexerCheckpoint): Promise<void> {
    this.checkpoint = cp;
  }

  async getLatestBlockNumber(): Promise<number> {
    if (this.events.length === 0) return 0;
    return Math.max(...this.events.map((e) => e.blockNumber));
  }

  getEvents(): IndexedEvent[] {
    return this.events;
  }
}
