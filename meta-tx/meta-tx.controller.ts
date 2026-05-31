import { Controller, Post, Body, BadRequestException } from "@nestjs/common";
import { MetaTxService } from "./meta-tx.service";

/**
 * MetaTxController handles HTTP requests for meta-transaction relaying
 * Enforces proper validation and error handling for signature-based operations
 */
@Controller("meta-tx")
export class MetaTxController {
  constructor(private readonly service: MetaTxService) {}

  /**
   * POST /meta-tx/relay
   * Relays a meta-transaction signed by the user
   *
   * Request body:
   * {
   *   "from": "0x...",
   *   "to": "0x...",
   *   "amount": "1000000000000000000",
   *   "deadline": 1234567890,
   *   "signature": "0x..."
   * }
   */
  @Post("relay")
  async relay(
    @Body()
    body: {
      from: string;
      to: string;
      amount: string;
      deadline: number;
      signature: string;
    }
  ) {
    try {
      // Validate required fields
      if (!body.from || !body.to || !body.amount || !body.deadline || !body.signature) {
        throw new BadRequestException("Missing required fields: from, to, amount, deadline, signature");
      }

      // Validate addresses
      if (!this.isValidAddress(body.from)) {
        throw new BadRequestException("Invalid sender address");
      }
      if (!this.isValidAddress(body.to)) {
        throw new BadRequestException("Invalid recipient address");
      }

      // Validate amount
      const amount = BigInt(body.amount);
      if (amount <= 0n) {
        throw new BadRequestException("Amount must be greater than 0");
      }

      // Validate deadline
      if (body.deadline <= Math.floor(Date.now() / 1000)) {
        throw new BadRequestException("Deadline must be in the future");
      }

      // Validate signature format
      if (!body.signature.startsWith("0x")) {
        throw new BadRequestException("Signature must be a hex string starting with 0x");
      }

      // Relay the transaction
      const result = await this.service.relayTransaction(
        body.from,
        body.to,
        amount,
        BigInt(body.deadline),
        body.signature
      );

      return {
        success: true,
        transactionHash: result?.hash,
        blockNumber: result?.blockNumber,
        gasUsed: result?.gasUsed?.toString(),
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : "Unknown error occurred";
      throw new BadRequestException({
        success: false,
        error: errorMessage,
      });
    }
  }

  /**
   * GET /meta-tx/nonce/:address
   * Get the current nonce for an address (used for signing)
   */
  @Post("nonce")
  async getNonce(@Body("address") address: string) {
    try {
      if (!address || !this.isValidAddress(address)) {
        throw new BadRequestException("Invalid address");
      }

      const nonce = await this.service.getNonce(address);

      return {
        success: true,
        address,
        nonce: nonce.toString(),
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : "Unknown error occurred";
      throw new BadRequestException({
        success: false,
        error: errorMessage,
      });
    }
  }

  /**
   * POST /meta-tx/prepare
   * Prepare transfer data for signing
   *
   * Request body:
   * {
   *   "from": "0x...",
   *   "to": "0x...",
   *   "amount": "1000000000000000000",
   *   "deadline": 1234567890
   * }
   */
  @Post("prepare")
  async prepareTransfer(
    @Body()
    body: {
      from: string;
      to: string;
      amount: string;
      deadline: number;
    }
  ) {
    try {
      // Validate required fields
      if (!body.from || !body.to || !body.amount || !body.deadline) {
        throw new BadRequestException("Missing required fields: from, to, amount, deadline");
      }

      // Validate addresses
      if (!this.isValidAddress(body.from)) {
        throw new BadRequestException("Invalid sender address");
      }
      if (!this.isValidAddress(body.to)) {
        throw new BadRequestException("Invalid recipient address");
      }

      // Validate amount
      const amount = BigInt(body.amount);
      if (amount <= 0n) {
        throw new BadRequestException("Amount must be greater than 0");
      }

      // Prepare transfer data
      const preparedData = await this.service.prepareTransfer(
        body.from,
        body.to,
        amount,
        BigInt(body.deadline)
      );

      return {
        success: true,
        domain: preparedData.domain,
        types: preparedData.types,
        value: preparedData.value,
        // Return as string for JSON compatibility
        typeHash: preparedData.typeHash,
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : "Unknown error occurred";
      throw new BadRequestException({
        success: false,
        error: errorMessage,
      });
    }
  }

  /**
   * Helper method to validate Ethereum addresses
   */
  private isValidAddress(address: string): boolean {
    return /^0x[a-fA-F0-9]{40}$/.test(address);
  }
}
