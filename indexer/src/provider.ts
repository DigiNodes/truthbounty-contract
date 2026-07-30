import { ethers } from "ethers";

export class ProviderManager {
  private rpc: ethers.JsonRpcProvider;
  private ws: ethers.WebSocketProvider | null;
  private wsUrl: string | null;
  private useWebSocket = false;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;
  private reconnectDelayMs = 2000;

  constructor(rpcUrl: string, wsUrl?: string) {
    this.rpc = new ethers.JsonRpcProvider(rpcUrl, undefined, { staticNetwork: true });
    this.wsUrl = wsUrl ?? null;
    this.ws = this.wsUrl
      ? new ethers.WebSocketProvider(this.wsUrl, undefined, { staticNetwork: true })
      : null;
  }

  get provider(): ethers.JsonRpcProvider | ethers.WebSocketProvider {
    return this.useWebSocket && this.ws ? this.ws : this.rpc;
  }

  get hasWebSocket(): boolean {
    return this.ws !== null;
  }

  async getBlockNumber(): Promise<number> {
    return this.provider.getBlockNumber();
  }

  async getBlock(block: number | string): Promise<ethers.Block | null> {
    return this.provider.getBlock(block);
  }

  async onNewBlock(callback: (blockNumber: number) => void): Promise<void> {
    if (!this.ws || !this.wsUrl) return;

    this.ws.on("block", (blockNumber: number) => {
      this.reconnectAttempts = 0;
      this.useWebSocket = true;
      callback(blockNumber);
    });

    this.ws.on("error", async () => {
      this.reconnectAttempts++;
      if (this.reconnectAttempts > this.maxReconnectAttempts) return;

      this.useWebSocket = false;
      await new Promise((r) => setTimeout(r, this.reconnectDelayMs * this.reconnectAttempts));

      const poll = setInterval(async () => {
        try {
          const block = await this.getBlockNumber();
          callback(block);
          clearInterval(poll);

          this.ws = new ethers.WebSocketProvider(this.wsUrl!, undefined, { staticNetwork: true });
          this.useWebSocket = true;
          this.onNewBlock(callback);
        } catch {
          // retry
        }
      }, this.reconnectDelayMs);
    });
  }

  destroy(): void {
    this.ws?.destroy();
  }
}
