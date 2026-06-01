import { ethers } from "ethers";

/**
 * MetaTxService handles meta-transaction relay with EIP-712 signature verification
 * Prevents replay attacks through proper nonce management and domain separation
 */
export class MetaTxService {
  private readonly provider: ethers.Provider;
  private readonly relayer: ethers.Wallet;
  private readonly contractAddress: string;

  /**
   * EIP-712 Domain separator definition
   */
  private readonly domain = {
    name: "MetaTxExample",
    version: "1",
    // chainId will be set dynamically
    // verifyingContract will be set dynamically
  };

  /**
   * Transfer type definition for EIP-712
   */
  private readonly types = {
    Transfer: [
      { name: "from", type: "address" },
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  };

  constructor() {
    if (!process.env.RPC_URL) {
      throw new Error("RPC_URL environment variable is required");
    }
    if (!process.env.RELAYER_KEY) {
      throw new Error("RELAYER_KEY environment variable is required");
    }
    if (!process.env.CONTRACT_ADDRESS) {
      throw new Error("CONTRACT_ADDRESS environment variable is required");
    }

    this.provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
    this.relayer = new ethers.Wallet(process.env.RELAYER_KEY, this.provider);
    this.contractAddress = process.env.CONTRACT_ADDRESS;
  }

  /**
   * Prepare a transfer for meta-transaction execution
   * @param from The sender address
   * @param to The recipient address
   * @param amount The transfer amount in wei
   * @param deadline The signature deadline (Unix timestamp)
   * @returns The transfer data ready to be signed
   */
  async prepareTransfer(
    from: string,
    to: string,
    amount: bigint,
    deadline: bigint
  ): Promise<{
    domain: any;
    types: any;
    value: any;
    typeHash: string;
  }> {
    // Get chain ID
    const network = await this.provider.getNetwork();
    const chainId = network.chainId;

    // Get current nonce from contract
    const contract = new ethers.Contract(
      this.contractAddress,
      ["function getNonce(address) view returns (uint256)"],
      this.provider
    );
    const nonce = await contract.getNonce(from);

    // Construct domain with chain-specific data
    const domain = {
      name: this.domain.name,
      version: this.domain.version,
      chainId,
      verifyingContract: this.contractAddress,
    };

    const value = {
      from,
      to,
      amount,
      nonce,
      deadline,
    };

    const typeHash = ethers.id("Transfer(address from,address to,uint256 amount,uint256 nonce,uint256 deadline)");

    return { domain, types: this.types, value, typeHash };
  }

  /**
   * Verify an EIP-712 signature
   * @param domain The EIP-712 domain
   * @param value The signed data value
   * @param signature The signature to verify
   * @returns The recovered signer address
   */
  async verifySignature(
    domain: any,
    value: any,
    signature: string
  ): Promise<string> {
    try {
      const digest = ethers.TypedDataEncoder.hash(domain, this.types, value);
      const signer = ethers.recoverAddress(digest, signature);
      return signer;
    } catch (error) {
      throw new Error(`Signature verification failed: ${error}`);
    }
  }

  /**
   * Relay a meta-transaction
   * @param from The original sender
   * @param to The recipient
   * @param amount The transfer amount in wei
   * @param deadline The signature deadline
   * @param signature The EIP-712 signature from the user
   * @returns The transaction result
   */
  async relayTransaction(
    from: string,
    to: string,
    amount: bigint,
    deadline: bigint,
    signature: string
  ): Promise<ethers.ContractTransactionResponse | null> {
    // Prepare transfer data
    const { domain, value } = await this.prepareTransfer(from, to, amount, deadline);

    // Verify signature
    const recoveredSigner = await this.verifySignature(domain, value, signature);
    if (recoveredSigner.toLowerCase() !== from.toLowerCase()) {
      throw new Error("Invalid signature: recovered signer does not match sender");
    }

    // Load contract with relayer wallet
    const contract = new ethers.Contract(
      this.contractAddress,
      [
        "function executeTransfer(address from, address to, uint256 amount, uint256 deadline, bytes calldata signature) external",
        "function getNonce(address) view returns (uint256)",
      ],
      this.relayer
    );

    try {
      // Submit transaction via relayer
      const tx = await contract.executeTransfer(from, to, amount, deadline, signature);
      const receipt = await tx.wait();
      return receipt;
    } catch (error) {
      throw new Error(`Transaction relay failed: ${error}`);
    }
  }

  /**
   * Get the current nonce for an address
   * @param address The address to query
   * @returns The current nonce
   */
  async getNonce(address: string): Promise<bigint> {
    const contract = new ethers.Contract(
      this.contractAddress,
      ["function getNonce(address) view returns (uint256)"],
      this.provider
    );
    return contract.getNonce(address);
  }

  /**
   * Check if a signature has been used (already executed)
   * @param digest The signature digest
   * @returns Whether the signature has been used
   */
  async isSignatureUsed(digest: string): Promise<boolean> {
    const contract = new ethers.Contract(
      this.contractAddress,
      ["function usedSignatures(bytes32) view returns (bool)"],
      this.provider
    );
    return contract.usedSignatures(digest);
  }
}
