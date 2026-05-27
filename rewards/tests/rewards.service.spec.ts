import { RewardsService } from "../rewards.service";
import { RewardsController as Controller } from "../rewards.controller";
import { ethers } from "ethers";

// ─── Helpers ────────────────────────────────────────────────────────────────

function makeClaimTuple(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    id: BigInt(1),
    submitter: "0xSubmitter",
    content: "ipfs://QmTest",
    createdAt: BigInt(1000),
    verificationWindowEnd: BigInt(2000),
    settled: false,
    totalStakedFor: ethers.parseUnits("500", 18),
    totalStakedAgainst: ethers.parseUnits("200", 18),
    totalStakeAmount: ethers.parseUnits("700", 18),
    ...overrides,
  };
}

function makeSettlementTuple(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    passed: true,
    totalRewards: ethers.parseUnits("32", 18),
    totalSlashed: ethers.parseUnits("40", 18),
    winnerStake: ethers.parseUnits("500", 18),
    loserStake: ethers.parseUnits("200", 18),
    ...overrides,
  };
}

function makeVoteTuple(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    voted: true,
    support: true,
    stakeAmount: ethers.parseUnits("100", 18),
    rewardClaimed: false,
    stakeReturned: false,
    ...overrides,
  };
}

function makeStakeTuple(total: string, active: string) {
  return {
    totalStaked: ethers.parseUnits(total, 18),
    activeStakes: ethers.parseUnits(active, 18),
  };
}

// ─── Mock contract factory ───────────────────────────────────────────────────

function buildMockContract(overrides: Record<string, jest.Mock> = {}) {
  const iface = new ethers.Interface([
    "event ClaimCreated(uint256 indexed claimId, address indexed submitter, string content, uint256 verificationWindowEnd)",
  ]);

  // encodeEventLog returns { topics, data } — wrap it so parseLog receives the right shape
  const encodedLog = iface.encodeEventLog("ClaimCreated", [BigInt(1), "0xSubmitter", "ipfs://QmTest", BigInt(2000)]);
  const mockReceipt = () => ({
    hash: "0xTxHash",
    logs: [encodedLog],
  });

  return {
    createClaim: jest.fn().mockResolvedValue({ wait: async () => mockReceipt() }),
    settleClaim: jest.fn().mockResolvedValue({ wait: async () => ({ hash: "0xSettleTx" }) }),
    claimSettlementRewards: jest.fn().mockResolvedValue({ wait: async () => ({ hash: "0xClaimTx" }) }),
    claims: jest.fn().mockResolvedValue(makeClaimTuple()),
    settlementResults: jest.fn().mockResolvedValue(makeSettlementTuple()),
    votes: jest.fn().mockResolvedValue(makeVoteTuple()),
    verifierStakes: jest.fn().mockResolvedValue(makeStakeTuple("1000", "300")),
    interface: iface,
    ...overrides,
  };
}

// ─── RewardsService tests ────────────────────────────────────────────────────

describe("RewardsService", () => {
  let service: RewardsService;
  let mockContract: ReturnType<typeof buildMockContract>;
  let mockSigner: { getAddress: jest.Mock; signTransaction: jest.Mock };

  beforeEach(() => {
    mockContract = buildMockContract();
    mockSigner = {
      getAddress: jest.fn().mockResolvedValue("0xVerifier"),
      signTransaction: jest.fn(),
    };

    service = new RewardsService("0xContract", mockSigner as unknown as ethers.Signer);
    (service as unknown as { contract: unknown }).contract = mockContract;
  });

  describe("createClaim", () => {
    it("returns claimId and txHash from ClaimCreated event", async () => {
      const result = await service.createClaim("ipfs://QmTest");
      expect(result.claimId).toBe("1");
      expect(result.txHash).toBe("0xTxHash");
    });
  });

  describe("getClaim", () => {
    it("returns formatted claim data", async () => {
      const claim = await service.getClaim("1");
      expect(claim.id).toBe("1");
      expect(claim.submitter).toBe("0xSubmitter");
      expect(claim.content).toBe("ipfs://QmTest");
      expect(claim.settled).toBe(false);
      expect(claim.totalStakedFor).toBe("500.0");
      expect(claim.totalStakedAgainst).toBe("200.0");
    });
  });

  describe("getSettlementResult", () => {
    it("returns formatted settlement result", async () => {
      const result = await service.getSettlementResult("1");
      expect(result.passed).toBe(true);
      expect(result.totalRewards).toBe("32.0");
      expect(result.totalSlashed).toBe("40.0");
      expect(result.winnerStake).toBe("500.0");
    });
  });

  describe("getVote", () => {
    it("returns formatted vote info", async () => {
      const vote = await service.getVote("1", "0xVerifier");
      expect(vote.voted).toBe(true);
      expect(vote.support).toBe(true);
      expect(vote.stakeAmount).toBe("100.0");
      expect(vote.rewardClaimed).toBe(false);
    });
  });

  describe("settleClaim", () => {
    it("returns txHash and settlement result", async () => {
      const result = await service.settleClaim("1");
      expect(result.txHash).toBe("0xSettleTx");
      expect(result.result.passed).toBe(true);
      expect(mockContract.settleClaim).toHaveBeenCalledWith(BigInt(1));
    });
  });

  describe("claimRewards", () => {
    it("returns txHash and rewardClaimed status", async () => {
      mockContract.votes.mockResolvedValueOnce(makeVoteTuple({ rewardClaimed: true }));
      const result = await service.claimRewards("1");
      expect(result.txHash).toBe("0xClaimTx");
      expect(result.rewardClaimed).toBe(true);
      expect(mockContract.claimSettlementRewards).toHaveBeenCalledWith(BigInt(1));
    });
  });

  describe("getVerifierStake", () => {
    it("returns totalStaked, activeStakes, and available", async () => {
      const stake = await service.getVerifierStake("0xVerifier");
      expect(stake.totalStaked).toBe("1000.0");
      expect(stake.activeStakes).toBe("300.0");
      expect(stake.available).toBe("700.0");
    });
  });
});

// ─── RewardsController tests ─────────────────────────────────────────────────

describe("RewardsController", () => {
  let controller: Controller;
  let mockService: jest.Mocked<RewardsService>;

  beforeEach(() => {
    mockService = {
      createClaim: jest.fn().mockResolvedValue({ claimId: "1", txHash: "0xTx" }),
      getClaim: jest.fn().mockResolvedValue(makeClaimTuple()),
      getSettlementResult: jest.fn().mockResolvedValue(makeSettlementTuple()),
      getVote: jest.fn().mockResolvedValue(makeVoteTuple()),
      settleClaim: jest.fn().mockResolvedValue({ txHash: "0xTx", result: makeSettlementTuple() }),
      claimRewards: jest.fn().mockResolvedValue({ txHash: "0xTx", rewardClaimed: true }),
      getVerifierStake: jest.fn().mockResolvedValue({ totalStaked: "1000.0", activeStakes: "300.0", available: "700.0" }),
    } as unknown as jest.Mocked<RewardsService>;

    controller = new Controller(mockService);
  });

  it("createClaim — calls service and returns result", async () => {
    const result = await controller.createClaim("ipfs://QmTest");
    expect(mockService.createClaim).toHaveBeenCalledWith("ipfs://QmTest");
    expect(result).toEqual({ claimId: "1", txHash: "0xTx" });
  });

  it("createClaim — throws on empty content", async () => {
    await expect(controller.createClaim("")).rejects.toThrow("content is required");
  });

  it("getClaim — calls service with claimId", async () => {
    await controller.getClaim("1");
    expect(mockService.getClaim).toHaveBeenCalledWith("1");
  });

  it("getClaim — throws on missing claimId", async () => {
    await expect(controller.getClaim("")).rejects.toThrow("claimId is required");
  });

  it("getSettlementResult — returns settlement data", async () => {
    const result = await controller.getSettlementResult("1");
    expect(mockService.getSettlementResult).toHaveBeenCalledWith("1");
    expect(result).toEqual(makeSettlementTuple()); // mockService returns makeSettlementTuple() directly
  });

  it("getVote — calls service with claimId and verifier", async () => {
    await controller.getVote("1", "0xVerifier");
    expect(mockService.getVote).toHaveBeenCalledWith("1", "0xVerifier");
  });

  it("getVote — throws on missing verifier", async () => {
    await expect(controller.getVote("1", "")).rejects.toThrow("verifier address is required");
  });

  it("settleClaim — calls service and returns result", async () => {
    const result = await controller.settleClaim("1");
    expect(mockService.settleClaim).toHaveBeenCalledWith("1");
    expect(result.txHash).toBe("0xTx");
  });

  it("claimRewards — calls service and returns rewardClaimed", async () => {
    const result = await controller.claimRewards("1");
    expect(mockService.claimRewards).toHaveBeenCalledWith("1");
    expect(result.rewardClaimed).toBe(true);
  });

  it("getVerifierStake — returns stake breakdown", async () => {
    const result = await controller.getVerifierStake("0xVerifier");
    expect(mockService.getVerifierStake).toHaveBeenCalledWith("0xVerifier");
    expect(result.available).toBe("700.0");
  });

  it("getVerifierStake — throws on missing address", async () => {
    await expect(controller.getVerifierStake("")).rejects.toThrow("verifier address is required");
  });
});
