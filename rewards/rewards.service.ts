import { ethers } from "ethers";

const TRUTH_BOUNTY_ABI = [
  "function createClaim(string memory content) external returns (uint256)",
  "function stake(uint256 amount) external",
  "function vote(uint256 claimId, bool support, uint256 stakeAmount) external",
  "function settleClaim(uint256 claimId) external",
  "function claimSettlementRewards(uint256 claimId) external",
  "function claims(uint256) external view returns (uint256 id, address submitter, string content, uint256 createdAt, uint256 verificationWindowEnd, bool settled, uint256 totalStakedFor, uint256 totalStakedAgainst, uint256 totalStakeAmount)",
  "function settlementResults(uint256) external view returns (bool passed, uint256 totalRewards, uint256 totalSlashed, uint256 winnerStake, uint256 loserStake)",
  "function votes(uint256, address) external view returns (bool voted, bool support, uint256 stakeAmount, bool rewardClaimed, bool stakeReturned)",
  "function verifierStakes(address) external view returns (uint256 totalStaked, uint256 activeStakes)",
  "event ClaimCreated(uint256 indexed claimId, address indexed submitter, string content, uint256 verificationWindowEnd)",
  "event ClaimSettled(uint256 indexed claimId, bool passed, uint256 totalStakedFor, uint256 totalStakedAgainst, uint256 totalRewards, uint256 totalSlashed)",
  "event RewardsDistributed(uint256 indexed claimId, address indexed verifier, uint256 amount)",
];

export interface ClaimInfo {
  id: string;
  submitter: string;
  content: string;
  createdAt: string;
  verificationWindowEnd: string;
  settled: boolean;
  totalStakedFor: string;
  totalStakedAgainst: string;
  totalStakeAmount: string;
}

export interface SettlementResult {
  passed: boolean;
  totalRewards: string;
  totalSlashed: string;
  winnerStake: string;
  loserStake: string;
}

export interface VoteInfo {
  voted: boolean;
  support: boolean;
  stakeAmount: string;
  rewardClaimed: boolean;
  stakeReturned: boolean;
}

export class RewardsService {
  private contract: ethers.Contract;
  private signer: ethers.Signer;

  constructor(
    contractAddress: string,
    signerOrProvider: ethers.Signer | ethers.Provider
  ) {
    // ethers v6: Signer has getAddress(); Provider does not
    if ("getAddress" in signerOrProvider) {
      this.signer = signerOrProvider as ethers.Signer;
    } else {
      this.signer = null as unknown as ethers.Signer;
    }
    this.contract = new ethers.Contract(contractAddress, TRUTH_BOUNTY_ABI, signerOrProvider);
  }

  async createClaim(content: string): Promise<{ claimId: string; txHash: string }> {
    const tx = await this.contract.createClaim(content);
    const receipt = await tx.wait();

    const event = receipt.logs
      .map((log: ethers.Log) => {
        try { return this.contract.interface.parseLog(log); } catch { return null; }
      })
      .find((e: ethers.LogDescription | null) => e?.name === "ClaimCreated");

    const claimId = event ? event.args.claimId.toString() : "unknown";
    return { claimId, txHash: receipt.hash };
  }

  async getClaim(claimId: string): Promise<ClaimInfo> {
    const c = await this.contract.claims(BigInt(claimId));
    return {
      id: c.id.toString(),
      submitter: c.submitter,
      content: c.content,
      createdAt: c.createdAt.toString(),
      verificationWindowEnd: c.verificationWindowEnd.toString(),
      settled: c.settled,
      totalStakedFor: ethers.formatUnits(c.totalStakedFor, 18),
      totalStakedAgainst: ethers.formatUnits(c.totalStakedAgainst, 18),
      totalStakeAmount: ethers.formatUnits(c.totalStakeAmount, 18),
    };
  }

  async getSettlementResult(claimId: string): Promise<SettlementResult> {
    const r = await this.contract.settlementResults(BigInt(claimId));
    return {
      passed: r.passed,
      totalRewards: ethers.formatUnits(r.totalRewards, 18),
      totalSlashed: ethers.formatUnits(r.totalSlashed, 18),
      winnerStake: ethers.formatUnits(r.winnerStake, 18),
      loserStake: ethers.formatUnits(r.loserStake, 18),
    };
  }

  async getVote(claimId: string, verifier: string): Promise<VoteInfo> {
    const v = await this.contract.votes(BigInt(claimId), verifier);
    return {
      voted: v.voted,
      support: v.support,
      stakeAmount: ethers.formatUnits(v.stakeAmount, 18),
      rewardClaimed: v.rewardClaimed,
      stakeReturned: v.stakeReturned,
    };
  }

  async settleClaim(claimId: string): Promise<{ txHash: string; result: SettlementResult }> {
    const tx = await this.contract.settleClaim(BigInt(claimId));
    const receipt = await tx.wait();
    const result = await this.getSettlementResult(claimId);
    return { txHash: receipt.hash, result };
  }

  async claimRewards(claimId: string): Promise<{ txHash: string; rewardClaimed: boolean }> {
    if (!this.signer) throw new Error("A signer is required to claim rewards");
    const tx = await this.contract.claimSettlementRewards(BigInt(claimId));
    const receipt = await tx.wait();

    const signerAddress = await this.signer.getAddress();
    const vote = await this.getVote(claimId, signerAddress);
    return { txHash: receipt.hash, rewardClaimed: vote.rewardClaimed };
  }

  async getVerifierStake(verifier: string): Promise<{ totalStaked: string; activeStakes: string; available: string }> {
    const s = await this.contract.verifierStakes(verifier);
    // s.totalStaked / s.activeStakes are already bigint from ethers v6 — no BigInt() wrap needed
    const total: bigint = s.totalStaked;
    const active: bigint = s.activeStakes;
    return {
      totalStaked: ethers.formatUnits(total, 18),
      activeStakes: ethers.formatUnits(active, 18),
      available: ethers.formatUnits(total - active, 18),
    };
  }
}

export function createRewardsService(contractAddress?: string, privateKey?: string, rpcUrl?: string): RewardsService {
  const address = contractAddress ?? process.env.TRUTH_BOUNTY_CONTRACT_ADDRESS;
  const key = privateKey ?? process.env.PRIVATE_KEY;
  const rpc = rpcUrl ?? process.env.RPC_URL ?? process.env.OPTIMISM_SEPOLIA_RPC_URL;

  if (!address) throw new Error("TRUTH_BOUNTY_CONTRACT_ADDRESS is required");
  if (!rpc) throw new Error("RPC_URL is required");

  const provider = new ethers.JsonRpcProvider(rpc);
  const signerOrProvider = key ? new ethers.Wallet(key, provider) : provider;
  return new RewardsService(address, signerOrProvider);
}
