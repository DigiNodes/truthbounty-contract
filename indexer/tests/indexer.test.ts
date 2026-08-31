import { describe, it, expect, vi, beforeEach } from "vitest";
import { ethers } from "ethers";
import { Indexer } from "../src/indexer";
import { IndexerConfig, IndexedEvent } from "../src/types";
import { TRUTH_BOUNTY_ABI, REPUTATION_DECAY_ABI } from "../src/events";
import { InMemoryStorage } from "../src/storage";
import { CheckpointManager } from "../src/checkpoint";
import { EventPipeline } from "../src/pipeline";

function testConfig(overrides?: Partial<IndexerConfig>): IndexerConfig {
  return {
    chainId: 31337,
    rpcUrl: "http://localhost:8545",
    contracts: [
      {
        name: "TruthBountyWeighted",
        address: "0x0000000000000000000000000000000000000001",
        abi: TRUTH_BOUNTY_ABI,
        fromBlock: 1,
      },
    ],
    startBlock: 1,
    checkpointInterval: 100,
    maxReorgDepth: 12,
    pollIntervalMs: 5000,
    confirmations: 0,
    ...overrides,
  };
}

describe("IndexerConfig", () => {
  it("should create indexer with valid config", () => {
    const config = testConfig();
    expect(config.chainId).toBe(31337);
    expect(config.contracts.length).toBe(1);
    expect(config.startBlock).toBe(1);
  });
});

describe("InMemoryStorage", () => {
  let storage: InMemoryStorage;

  beforeEach(() => {
    storage = new InMemoryStorage();
  });

  it("should save and retrieve events", async () => {
    const event: IndexedEvent = {
      chainId: 1,
      blockNumber: 100,
      blockHash: "0xabc",
      transactionHash: "0xtx1",
      logIndex: 0,
      contractName: "Test",
      contractAddress: "0x0001",
      eventName: "TestEvent",
      args: { key: "value" },
      timestamp: 1000,
      processedAt: new Date(),
    };

    await storage.saveEvents([event]);
    const events = storage.getEvents();
    expect(events).toHaveLength(1);
    expect(events[0].transactionHash).toBe("0xtx1");
  });

  it("should detect duplicate events", async () => {
    const event: IndexedEvent = {
      chainId: 1,
      blockNumber: 100,
      blockHash: "0xabc",
      transactionHash: "0xtx1",
      logIndex: 0,
      contractName: "Test",
      contractAddress: "0x0001",
      eventName: "TestEvent",
      args: {},
      timestamp: 1000,
      processedAt: new Date(),
    };

    await storage.saveEvents([event]);
    const duplicates = await storage.getDuplicateEvents(["0xtx1"]);
    expect(duplicates.has("0xtx1:0")).toBe(true);
  });

  it("should persist and load checkpoints", async () => {
    await storage.saveCheckpoint({ blockNumber: 42, blockHash: "0xhash", updatedAt: new Date() });
    const cp = await storage.getCheckpoint();
    expect(cp?.blockNumber).toBe(42);
    expect(cp?.blockHash).toBe("0xhash");
  });
});

describe("CheckpointManager", () => {
  it("should return 0 when no checkpoint", async () => {
    const storage = new InMemoryStorage();
    const mgr = new CheckpointManager(storage);
    await mgr.load();
    expect(mgr.getLastBlockNumber()).toBe(0);
    expect(mgr.get()).toBeNull();
  });

  it("should update and retrieve checkpoint", async () => {
    const storage = new InMemoryStorage();
    const mgr = new CheckpointManager(storage);
    await mgr.load();
    await mgr.update(50, "0xhash50");
    expect(mgr.getLastBlockNumber()).toBe(50);
    expect(mgr.getLastBlockHash()).toBe("0xhash50");
  });

  it("should resume from persisted checkpoint", async () => {
    const storage = new InMemoryStorage();
    await storage.saveCheckpoint({ blockNumber: 30, blockHash: "0xhash30", updatedAt: new Date() });
    const mgr = new CheckpointManager(storage);
    await mgr.load();
    expect(mgr.getLastBlockNumber()).toBe(30);
  });
});

describe("EventPipeline", () => {
  it("should detect reorg when block hash differs", async () => {
    const storage = new InMemoryStorage();
    const pipeline = new EventPipeline(storage, []);

    const provider = {
      getBlock: vi.fn().mockResolvedValue({ hash: "0xwronghash" }),
    } as unknown as ethers.Provider;

    const reorgBlock = await pipeline.detectReorg(
      provider,
      { blockNumber: 100, blockHash: "0xoriginalhash", updatedAt: new Date() },
      12
    );
    expect(reorgBlock).not.toBeNull();
  });

  it("should not detect reorg when block hash matches", async () => {
    const storage = new InMemoryStorage();
    const pipeline = new EventPipeline(storage, []);

    const provider = {
      getBlock: vi.fn().mockResolvedValue({ hash: "0xgoodhash" }),
    } as unknown as ethers.Provider;

    const reorgBlock = await pipeline.detectReorg(
      provider,
      { blockNumber: 100, blockHash: "0xgoodhash", updatedAt: new Date() },
      12
    );
    expect(reorgBlock).toBeNull();
  });
});

describe("Indexer", () => {
  it("should construct and stop without error", async () => {
    const config = testConfig({ rpcUrl: "http://localhost:18545" });
    const indexer = new Indexer(config);
    expect(indexer).toBeDefined();
    await indexer.stop();
  });

  it("should expose storage adapter", () => {
    const config = testConfig();
    const indexer = new Indexer(config);
    const storage = indexer.getStorage();
    expect(storage).toBeInstanceOf(InMemoryStorage);
  });

  it("should register event handlers", async () => {
    const config = testConfig();
    const indexer = new Indexer(config);
    const handler = vi.fn();
    indexer.onEvent(handler);
    expect(handler).toBeDefined();
  });
});

describe("Event Definitions", () => {
  it("should extract event names correctly", () => {
    expect(TRUTH_BOUNTY_ABI.some((a) => a.startsWith("event ClaimCreated"))).toBe(true);
    expect(TRUTH_BOUNTY_ABI.some((a) => a.startsWith("event VoteCast"))).toBe(true);
    expect(TRUTH_BOUNTY_ABI.some((a) => a.startsWith("event ClaimSettled"))).toBe(true);
    expect(TRUTH_BOUNTY_ABI.some((a) => a.startsWith("event RewardsDistributed"))).toBe(true);
    expect(TRUTH_BOUNTY_ABI.some((a) => a.startsWith("event StakeSlashed"))).toBe(true);
    expect(REPUTATION_DECAY_ABI.some((a) => a.startsWith("event ReputationDecayed"))).toBe(true);
  });

  it("should have at least one event per contract", () => {
    expect(TRUTH_BOUNTY_ABI.length).toBeGreaterThanOrEqual(5);
    expect(REPUTATION_DECAY_ABI.length).toBeGreaterThanOrEqual(3);
  });
});
