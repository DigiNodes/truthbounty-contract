export interface ContractConfig {
  name: string;
  address: string;
  abi: string[];
  fromBlock: number;
}

export interface IndexerConfig {
  chainId: number;
  rpcUrl: string;
  wsUrl?: string;
  contracts: ContractConfig[];
  startBlock: number;
  checkpointInterval: number;
  maxReorgDepth: number;
  pollIntervalMs: number;
  confirmations: number;
}

export interface IndexedEvent {
  chainId: number;
  blockNumber: number;
  blockHash: string;
  transactionHash: string;
  logIndex: number;
  contractName: string;
  contractAddress: string;
  eventName: string;
  args: Record<string, unknown>;
  timestamp: number;
  processedAt: Date;
}

export interface IndexerCheckpoint {
  blockNumber: number;
  blockHash: string;
  updatedAt: Date;
}

export interface StorageAdapter {
  connect(): Promise<void>;
  disconnect(): Promise<void>;
  saveEvents(events: IndexedEvent[]): Promise<void>;
  getDuplicateEvents(txHashes: string[]): Promise<Set<string>>;
  getCheckpoint(): Promise<IndexerCheckpoint | null>;
  saveCheckpoint(checkpoint: IndexerCheckpoint): Promise<void>;
  getLatestBlockNumber(): Promise<number>;
}

export interface EventHandler {
  (event: IndexedEvent): Promise<void>;
}
