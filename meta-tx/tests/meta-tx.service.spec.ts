import { Test, TestingModule } from "@nestjs/testing";
import { MetaTxService } from "../meta-tx.service";
import { ethers } from "ethers";

/**
 * Unit tests for MetaTxService
 * Tests EIP-712 signature verification and relay functionality
 * Verifies replay attack protection and nonce management
 */
describe("MetaTxService", () => {
  let service: MetaTxService;
  let mockProvider: any;
  let mockContract: any;

  const testDomain = {
    name: "MetaTxExample",
    version: "1",
    chainId: 31337n, // Hardhat chain ID
    verifyingContract: "0x5FbDB2315678afccb333f8a9c45b65d30e8be10C",
  };

  const types = {
    Transfer: [
      { name: "from", type: "address" },
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  };

  beforeEach(async () => {
    // Mock environment variables
    process.env.RPC_URL = "http://localhost:8545";
    process.env.RELAYER_KEY = "0x0000000000000000000000000000000000000000000000000000000000000001";
    process.env.CONTRACT_ADDRESS = "0x5FbDB2315678afccb333f8a9c45b65d30e8be10C";

    // Mock ethers.JsonRpcProvider and ethers.Wallet
    jest.spyOn(ethers, "JsonRpcProvider" as any).mockImplementation(() => mockProvider);
    jest.spyOn(ethers, "Wallet" as any).mockImplementation(() => ({
      address: "0x70997970C51812e339D9B73b0245ad59E56eFe1D",
    }));
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe("Constructor", () => {
    it("should throw if RPC_URL is missing", () => {
      delete process.env.RPC_URL;
      expect(() => new MetaTxService()).toThrow("RPC_URL environment variable is required");
    });

    it("should throw if RELAYER_KEY is missing", () => {
      delete process.env.RELAYER_KEY;
      expect(() => new MetaTxService()).toThrow("RELAYER_KEY environment variable is required");
    });

    it("should throw if CONTRACT_ADDRESS is missing", () => {
      delete process.env.CONTRACT_ADDRESS;
      expect(() => new MetaTxService()).toThrow("CONTRACT_ADDRESS environment variable is required");
    });

    it("should initialize with valid environment variables", () => {
      expect(() => new MetaTxService()).not.toThrow();
    });
  });

  describe("Signature Verification", () => {
    let service: MetaTxService;
    let signer: ethers.Wallet;

    beforeEach(() => {
      service = new MetaTxService();
      signer = ethers.Wallet.createRandom();
    });

    it("should verify a valid EIP-712 signature", async () => {
      const value = {
        from: signer.address,
        to: "0x3C44CdDdB6a900c2f40dc16f7ABC4d697c223C03",
        amount: ethers.parseEther("10"),
        nonce: 0n,
        deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
      };

      const signature = await signer.signTypedData(testDomain, types, value);

      const recoveredSigner = await service.verifySignature(testDomain, value, signature);

      expect(recoveredSigner.toLowerCase()).toBe(signer.address.toLowerCase());
    });

    it("should reject invalid signature", async () => {
      const value = {
        from: signer.address,
        to: "0x3C44CdDdB6a900c2f40dc16f7ABC4d697c223C03",
        amount: ethers.parseEther("10"),
        nonce: 0n,
        deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
      };

      const invalidSignature = "0x" + "00".repeat(65);

      await expect(
        service.verifySignature(testDomain, value, invalidSignature)
      ).rejects.toThrow("Signature verification failed");
    });

    it("should reject signature with tampered data", async () => {
      const value = {
        from: signer.address,
        to: "0x3C44CdDdB6a900c2f40dc16f7ABC4d697c223C03",
        amount: ethers.parseEther("10"),
        nonce: 0n,
        deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
      };

      const signature = await signer.signTypedData(testDomain, types, value);

      // Tamper with the data
      const tamperedValue = {
        ...value,
        amount: ethers.parseEther("100"), // Changed amount
      };

      const recoveredSigner = await service.verifySignature(testDomain, tamperedValue, signature);

      // Should recover a different signer due to tampered data
      expect(recoveredSigner.toLowerCase()).not.toBe(signer.address.toLowerCase());
    });
  });

  describe("Nonce Management", () => {
    it("should retrieve the current nonce for an address", async () => {
      const service = new MetaTxService();
      const mockGetNonce = jest.fn().mockResolvedValue(5n);

      // Mock the contract call
      const originalContract = ethers.Contract;
      jest.spyOn(ethers, "Contract" as any).mockImplementation(() => ({
        getNonce: mockGetNonce,
      }));

      const nonce = await service.getNonce("0x3C44CdDdB6a900c2f40dc16f7ABC4d697c223C03");

      expect(nonce).toBe(5n);
    });
  });

  describe("Replay Attack Prevention", () => {
    let service: MetaTxService;
    let signer: ethers.Wallet;

    beforeEach(() => {
      service = new MetaTxService();
      signer = ethers.Wallet.createRandom();
    });

    it("should prevent signature replay with different nonces", async () => {
      const value1 = {
        from: signer.address,
        to: "0x3C44CdDdB6a900c2f40dc16f7ABC4d697c223C03",
        amount: ethers.parseEther("10"),
        nonce: 0n,
        deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
      };

      const value2 = {
        ...value1,
        nonce: 1n, // Different nonce
      };

      const signature1 = await signer.signTypedData(testDomain, types, value1);
      const signature2 = await signer.signTypedData(testDomain, types, value2);

      // Signatures should be different due to different nonces
      expect(signature1).not.toBe(signature2);

      // Both should verify correctly with their respective data
      const recovered1 = await service.verifySignature(testDomain, value1, signature1);
      const recovered2 = await service.verifySignature(testDomain, value2, signature2);

      expect(recovered1.toLowerCase()).toBe(signer.address.toLowerCase());
      expect(recovered2.toLowerCase()).toBe(signer.address.toLowerCase());
    });

    it("should prevent cross-chain replay", async () => {
      const value = {
        from: signer.address,
        to: "0x3C44CdDdB6a900c2f40dc16f7ABC4d697c223C03",
        amount: ethers.parseEther("10"),
        nonce: 0n,
        deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
      };

      const signature = await signer.signTypedData(testDomain, types, value);

      // Try to verify with different chain domain
      const differentChainDomain = {
        ...testDomain,
        chainId: 999n, // Different chain
      };

      const recoveredOnDifferentChain = await service.verifySignature(
        differentChainDomain,
        value,
        signature
      );

      // Should recover different signer due to different domain
      expect(recoveredOnDifferentChain.toLowerCase()).not.toBe(
        signer.address.toLowerCase()
      );
    });
  });

  describe("Input Validation", () => {
    let service: MetaTxService;

    beforeEach(() => {
      service = new MetaTxService();
    });

    it("should accept valid addresses", async () => {
      const validAddress = "0x3C44CdDdB6a900c2f40dc16f7ABC4d697c223C03";
      const signer = ethers.Wallet.createRandom();

      const value = {
        from: validAddress,
        to: signer.address,
        amount: ethers.parseEther("10"),
        nonce: 0n,
        deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
      };

      // Should not throw
      const signature = await signer.signTypedData(testDomain, types, value);
      await service.verifySignature(testDomain, value, signature);
    });

    it("should handle large amounts", async () => {
      const signer = ethers.Wallet.createRandom();
      const largeAmount = ethers.parseEther("1000000");

      const value = {
        from: signer.address,
        to: "0x3C44CdDdB6a900c2f40dc16f7ABC4d697c223C03",
        amount: largeAmount,
        nonce: 0n,
        deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
      };

      const signature = await signer.signTypedData(testDomain, types, value);
      const recoveredSigner = await service.verifySignature(testDomain, value, signature);

      expect(recoveredSigner.toLowerCase()).toBe(signer.address.toLowerCase());
    });
  });
});
