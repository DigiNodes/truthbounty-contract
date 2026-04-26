// Before (broken):
// const CONFIRMATION_DEPTH = 12; // hardcoded, never changes

// After — configurable, validated:
export class ReorgHandler {
    private confirmationDepth: number;
  
    constructor(depth: number = parseInt(process.env.CONFIRMATION_DEPTH ?? '12', 10)) {
      if (!Number.isInteger(depth) || depth < 1) {
        throw new Error(`Invalid confirmation depth: ${depth}. Must be a positive integer.`);
      }
      this.confirmationDepth = depth;
    }
  
    setConfirmationDepth(depth: number): void {
      if (!Number.isInteger(depth) || depth < 1) {
        throw new Error(`Invalid confirmation depth: ${depth}`);
      }
      this.confirmationDepth = depth;
    }
  
    getConfirmationDepth(): number {
      return this.confirmationDepth;
    }
  
    // ... rest of your reorg handling logic using this.confirmationDepth
  }