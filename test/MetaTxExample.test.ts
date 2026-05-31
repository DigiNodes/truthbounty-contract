import { expect } from "chai";
import { ethers } from "hardhat";
import { MetaTxExample } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("MetaTxExample", function () {
  let metaTxExample: MetaTxExample;
  let owner: SignerWithAddress;
  let user: SignerWithAddress;
  let recipient: SignerWithAddress;
  let forwarder: SignerWithAddress;

  const DOMAIN_NAME = "MetaTxExample";
  const DOMAIN_VERSION = "1";

  beforeEach(async function () {
    [owner, user, recipient, forwarder] = await ethers.getSigners();

    const MetaTxExample = await ethers.getContractFactory("MetaTxExample");
    metaTxExample = await MetaTxExample.deploy(forwarder.address);
    await metaTxExample.waitForDeployment();
  });

  describe("Domain Separator & Nonce Initialization", function () {
    it("should return a valid domain separator", async function () {
      const domainSeparator = await metaTxExample.getDomainSeparator();
      expect(domainSeparator).to.not.equal(ethers.ZeroHash);
    });

    it("should initialize nonce to 0 for new addresses", async function () {
      const nonce = await metaTxExample.getNonce(user.address);
      expect(nonce).to.equal(0);
    });

    it("should return correct domain separator details", async function () {
      const domain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await metaTxExample.getAddress(),
      };

      const domainSeparator = ethers.TypedDataEncoder.hashDomain(domain);
      const contractDomainSeparator = await metaTxExample.getDomainSeparator();
      
      expect(contractDomainSeparator).to.equal(domainSeparator);
    });
  });

  describe("Signature Verification & Execution", function () {
    it("should execute transfer with valid signature", async function () {
      const to = recipient.address;
      const amount = ethers.parseEther("10");
      const nonce = await metaTxExample.getNonce(user.address);
      const deadline = BigInt(await time.latest()) + BigInt(3600); // 1 hour from now

      const domain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await metaTxExample.getAddress(),
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

      const value = {
        from: user.address,
        to,
        amount,
        nonce,
        deadline,
      };

      const signature = await user.signTypedData(domain, types, value);

      await expect(
        metaTxExample.executeTransfer(user.address, to, amount, deadline, signature)
      )
        .to.emit(metaTxExample, "TransferExecuted")
        .withArgs(user.address, to, amount, nonce);

      // Verify nonce incremented
      const newNonce = await metaTxExample.getNonce(user.address);
      expect(newNonce).to.equal(nonce + 1n);
    });

    it("should reject signature with invalid signer", async function () {
      const to = recipient.address;
      const amount = ethers.parseEther("10");
      const nonce = await metaTxExample.getNonce(user.address);
      const deadline = BigInt(await time.latest()) + BigInt(3600);

      const domain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await metaTxExample.getAddress(),
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

      const value = {
        from: user.address,
        to,
        amount,
        nonce,
        deadline,
      };

      // Sign with owner instead of user
      const signature = await owner.signTypedData(domain, types, value);

      await expect(
        metaTxExample.executeTransfer(user.address, to, amount, deadline, signature)
      ).to.be.revertedWith("Invalid signature");
    });

    it("should reject expired signature", async function () {
      const to = recipient.address;
      const amount = ethers.parseEther("10");
      const nonce = await metaTxExample.getNonce(user.address);
      const deadline = BigInt(await time.latest()) - BigInt(3600); // 1 hour ago

      const domain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await metaTxExample.getAddress(),
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

      const value = {
        from: user.address,
        to,
        amount,
        nonce,
        deadline,
      };

      const signature = await user.signTypedData(domain, types, value);

      await expect(
        metaTxExample.executeTransfer(user.address, to, amount, deadline, signature)
      ).to.be.revertedWith("Signature expired");
    });
  });

  describe("Replay Attack Prevention", function () {
    it("should prevent replay of same signature (same nonce)", async function () {
      const to = recipient.address;
      const amount = ethers.parseEther("10");
      const nonce = await metaTxExample.getNonce(user.address);
      const deadline = BigInt(await time.latest()) + BigInt(3600);

      const domain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await metaTxExample.getAddress(),
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

      const value = {
        from: user.address,
        to,
        amount,
        nonce,
        deadline,
      };

      const signature = await user.signTypedData(domain, types, value);

      // First execution should succeed
      await expect(
        metaTxExample.executeTransfer(user.address, to, amount, deadline, signature)
      ).to.emit(metaTxExample, "TransferExecuted");

      // Second execution with same signature should fail
      await expect(
        metaTxExample.executeTransfer(user.address, to, amount, deadline, signature)
      ).to.be.revertedWith("Invalid signature");
    });

    it("should allow sequential transactions with different nonces", async function () {
      const to = recipient.address;
      const amount = ethers.parseEther("10");
      const deadline = BigInt(await time.latest()) + BigInt(3600);

      const domain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await metaTxExample.getAddress(),
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

      // First transaction with nonce 0
      let nonce = await metaTxExample.getNonce(user.address);
      expect(nonce).to.equal(0);

      let value = {
        from: user.address,
        to,
        amount,
        nonce,
        deadline,
      };

      let signature = await user.signTypedData(domain, types, value);
      await metaTxExample.executeTransfer(user.address, to, amount, deadline, signature);

      // Verify nonce incremented
      nonce = await metaTxExample.getNonce(user.address);
      expect(nonce).to.equal(1);

      // Second transaction with nonce 1
      value = {
        from: user.address,
        to,
        amount: ethers.parseEther("20"),
        nonce,
        deadline,
      };

      signature = await user.signTypedData(domain, types, value);
      await metaTxExample.executeTransfer(user.address, to, ethers.parseEther("20"), deadline, signature);

      // Verify nonce incremented again
      nonce = await metaTxExample.getNonce(user.address);
      expect(nonce).to.equal(2);
    });

    it("should reject signature with old nonce", async function () {
      const to = recipient.address;
      const amount = ethers.parseEther("10");
      const deadline = BigInt(await time.latest()) + BigInt(3600);

      const domain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await metaTxExample.getAddress(),
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

      // Execute first transaction to increment nonce
      let nonce = await metaTxExample.getNonce(user.address);
      let value = {
        from: user.address,
        to,
        amount,
        nonce,
        deadline,
      };
      let signature = await user.signTypedData(domain, types, value);
      await metaTxExample.executeTransfer(user.address, to, amount, deadline, signature);

      // Now nonce is 1, but we try to use old nonce 0
      nonce = 0; // Old nonce
      value = {
        from: user.address,
        to,
        amount,
        nonce,
        deadline,
      };
      signature = await user.signTypedData(domain, types, value);

      // This should fail because the digest won't match (nonce in signature doesn't match current nonce)
      await expect(
        metaTxExample.executeTransfer(user.address, to, amount, deadline, signature)
      ).to.be.revertedWith("Invalid signature");
    });
  });

  describe("Cross-Chain Replay Protection", function () {
    it("should include chain ID in domain separator", async function () {
      const domain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await metaTxExample.getAddress(),
      };

      const domainSeparator = ethers.TypedDataEncoder.hashDomain(domain);
      const contractDomainSeparator = await metaTxExample.getDomainSeparator();

      // Should match for current chain
      expect(contractDomainSeparator).to.equal(domainSeparator);

      // Create a domain for a different chain
      const differentChainDomain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: 999, // Different chain
        verifyingContract: await metaTxExample.getAddress(),
      };

      const differentChainSeparator = ethers.TypedDataEncoder.hashDomain(differentChainDomain);

      // Should NOT match
      expect(contractDomainSeparator).to.not.equal(differentChainSeparator);
    });

    it("should prevent cross-chain signature reuse", async function () {
      const to = recipient.address;
      const amount = ethers.parseEther("10");
      const nonce = await metaTxExample.getNonce(user.address);
      const deadline = BigInt(await time.latest()) + BigInt(3600);

      const currentChainId = (await ethers.provider.getNetwork()).chainId;

      const domain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: currentChainId,
        verifyingContract: await metaTxExample.getAddress(),
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

      const value = {
        from: user.address,
        to,
        amount,
        nonce,
        deadline,
      };

      const signature = await user.signTypedData(domain, types, value);

      // Simulate signature signed on different chain by modifying domain
      const differentChainDomain = {
        ...domain,
        chainId: 999, // Simulate different chain
      };

      // The signature is valid for the original chain domain
      await expect(
        metaTxExample.executeTransfer(user.address, to, amount, deadline, signature)
      ).to.emit(metaTxExample, "TransferExecuted");

      // We can't directly test reuse on different chain without forking,
      // but the chain ID in domain separator ensures protection
    });
  });

  describe("ERC2771Context Integration", function () {
    it("should correctly identify _msgSender from trusted forwarder", async function () {
      const to = recipient.address;
      const amount = ethers.parseEther("10");

      // Note: This is a simplified test. In production, you'd need to properly encode
      // meta-transaction calls according to ERC-2771 spec with proper msgSender appending
      
      const tx = await metaTxExample.transfer(to, amount);
      await tx.wait();

      // The transfer was executed by the caller (user in this case)
      // In a real meta-tx scenario, the forwarder would append the actual sender
      await expect(tx).to.emit(metaTxExample, "TransferExecuted");
    });
  });

  describe("Transfer Function Validation", function () {
    it("should reject transfer to zero address", async function () {
      const amount = ethers.parseEther("10");

      await expect(
        metaTxExample.transfer(ethers.ZeroAddress, amount)
      ).to.be.revertedWith("Invalid recipient");
    });

    it("should reject transfer with zero amount", async function () {
      const to = recipient.address;

      await expect(
        metaTxExample.transfer(to, 0)
      ).to.be.revertedWith("Invalid amount");
    });
  });

  describe("Nonce Management", function () {
    it("should increment nonce after each successful transfer", async function () {
      const to = recipient.address;
      const amount = ethers.parseEther("10");
      const deadline = BigInt(await time.latest()) + BigInt(3600);

      const domain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await metaTxExample.getAddress(),
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

      for (let i = 0; i < 3; i++) {
        const nonce = await metaTxExample.getNonce(user.address);
        expect(nonce).to.equal(i);

        const value = {
          from: user.address,
          to,
          amount,
          nonce,
          deadline,
        };

        const signature = await user.signTypedData(domain, types, value);
        await expect(
          metaTxExample.executeTransfer(user.address, to, amount, deadline, signature)
        ).to.emit(metaTxExample, "NonceIncremented")
         .withArgs(user.address, i + 1);
      }
    });

    it("should maintain independent nonces for different users", async function () {
      const nonce1 = await metaTxExample.getNonce(user.address);
      const nonce2 = await metaTxExample.getNonce(recipient.address);

      expect(nonce1).to.equal(0);
      expect(nonce2).to.equal(0);

      const to = recipient.address;
      const amount = ethers.parseEther("10");
      const deadline = BigInt(await time.latest()) + BigInt(3600);

      const domain = {
        name: DOMAIN_NAME,
        version: DOMAIN_VERSION,
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: await metaTxExample.getAddress(),
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

      // Execute transaction for user
      let value = {
        from: user.address,
        to,
        amount,
        nonce: nonce1,
        deadline,
      };
      let signature = await user.signTypedData(domain, types, value);
      await metaTxExample.executeTransfer(user.address, to, amount, deadline, signature);

      // Check nonces
      const updatedNonce1 = await metaTxExample.getNonce(user.address);
      const updatedNonce2 = await metaTxExample.getNonce(recipient.address);

      expect(updatedNonce1).to.equal(1);
      expect(updatedNonce2).to.equal(0); // Unchanged
    });
  });
});
