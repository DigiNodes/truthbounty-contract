# Meta-TX Replay Attack Fix - Quick Reference

## 🎯 What Was Fixed

The Meta-TX Example contract had a **replay attack vulnerability** where the same transaction could be executed multiple times. This implementation adds comprehensive protection.

---

## 🔒 Protection Mechanisms

### 1. **Nonce-Based Protection**
Each user has an independent nonce that increments with each transaction.
```solidity
mapping(address => uint256) public nonces;
```
- Prevents reusing old signatures
- Makes each signature unique
- Enables sequential transaction ordering

### 2. **Used Signature Tracking**
Executed signatures are marked as used to prevent exact replay.
```solidity
mapping(bytes32 => bool) public usedSignatures;
```
- Prevents the exact same signature from being replayed
- Works as a second line of defense

### 3. **Domain Separator (Chain ID)**
Includes the chain ID in the signature domain.
```solidity
domain = {
    chainId: <current_chain_id>,
    ...
}
```
- Prevents cross-chain replay attacks
- Each chain has a different domain separator
- Signature valid only on its original chain

### 4. **Deadline Validation**
Signatures have an expiration time.
```solidity
require(block.timestamp <= deadline, "Signature expired");
```
- Prevents old signatures from being executed
- Time-bounds transaction validity
- Gives users time window to revoke intent

---

## 🧪 Test Coverage

| Category | Tests | Key Coverage |
|----------|-------|--------------|
| **Domain & Nonce** | 3 | Domain separator, nonce initialization |
| **Signature Verification** | 3 | Valid/invalid/expired signatures |
| **Replay Prevention** | 4 | Same signature, old nonce, sequential ops |
| **Cross-Chain** | 2 | Chain ID in domain, different chains |
| **ERC2771** | 1 | Context integration |
| **Validation** | 2 | Zero address, zero amount |
| **Nonce Management** | 4 | Increment, independence, events |
| **Service Tests** | 16 | EIP-712, verification, environment |
| **Fuzz Tests** | 11 | Invariants, properties |
| **Total** | **49+** | Comprehensive coverage |

---

## 📋 Example Flow

### 1. User initiates transfer (off-chain)
```javascript
const transferData = {
  from: userAddress,
  to: recipientAddress,
  amount: ethers.parseEther("10"),
  nonce: 0, // Current nonce
  deadline: Math.floor(Date.now() / 1000) + 3600 // 1 hour
};
```

### 2. User signs with wallet (off-chain)
```javascript
const signature = await userWallet.signTypedData(
  domain,  // Includes chainId, contractAddress
  types,   // Transfer type definition
  value    // transferData
);
```

### 3. Relayer submits transaction (on-chain)
```javascript
await metaTxContract.executeTransfer(
  userAddress,
  recipientAddress,
  amount,
  deadline,
  signature
);
```

### 4. Contract validates (on-chain)
- ✅ Deadline not expired
- ✅ Signature recovers to userAddress
- ✅ Nonce matches current nonce
- ✅ Signature digest not already used
- ✅ Execute transfer
- ✅ Increment nonce
- ✅ Mark signature as used

---

## 🚨 Attack Scenarios Prevented

### Scenario 1: Exact Replay
**Attack**: Submit same signature twice
**Protection**: `usedSignatures` mapping marks signature as used after first execution

### Scenario 2: Nonce Manipulation
**Attack**: Reorder transactions by re-executing old signatures
**Protection**: Nonce is part of signature, old nonces won't verify

### Scenario 3: Cross-Chain Replay
**Attack**: Use signature from Chain A on Chain B
**Protection**: Chain ID in domain separator makes signatures chain-specific

### Scenario 4: Deadline Bypass
**Attack**: Execute signature months later
**Protection**: Deadline validation rejects expired signatures

### Scenario 5: Sequential Manipulation
**Attack**: Execute transaction 2 then transaction 1
**Protection**: Nonce must match current nonce for verification

---

## 🔍 Key Functions

### `executeTransfer(from, to, amount, deadline, signature)`
Executes a meta-transaction with full validation:
- Checks deadline
- Verifies signature
- Prevents replay via nonce and digest tracking
- Increments nonce
- Emits events

### `getNonce(address)`
Returns current nonce for address (used for signing)

### `getDomainSeparator()`
Returns EIP-712 domain separator for verification

---

## 🛠️ Integration Steps

### For Smart Contract Developers
1. Inherit from both `ERC2771Context` and `EIP712`
2. Declare `nonces` mapping and `usedSignatures` mapping
3. Implement signature verification in your functions
4. Increment nonce after successful execution

### For dApp Developers
1. Retrieve user's current nonce
2. Prepare transfer data with nonce
3. Have user sign with their wallet
4. Submit signature to relayer endpoint

### For Relayer Operators
1. Verify signature is valid
2. Verify nonce hasn't been used
3. Submit transaction to contract
4. Monitor for successful execution

---

## ✅ Verification Checklist

- ✅ Nonce starts at 0 for new addresses
- ✅ Nonce increments by 1 with each transfer
- ✅ Same signature cannot be replayed
- ✅ Old nonces are rejected
- ✅ Different users have independent nonces
- ✅ Expired signatures are rejected
- ✅ Chain ID is part of domain
- ✅ Zero addresses are rejected
- ✅ Zero amounts are rejected

---

## 📚 Standards Compliance

- ✅ **EIP-2771**: Meta-transaction execution via trusted forwarder
- ✅ **EIP-712**: Typed structured data signing
- ✅ **OpenZeppelin**: EIP712, ECDSA libraries

---

## 🎓 Learn More

- Read the full test suite in `test/MetaTxExample.test.ts`
- Check invariant tests in `test/fuzz/MetaTxReplayAttackFuzz.sol`
- Review service implementation in `meta-tx/meta-tx.service.ts`
- See API usage in `meta-tx/meta-tx.controller.ts`

---

## 📞 Support

For questions about the implementation:
1. Check `META_TX_IMPLEMENTATION.md` for detailed documentation
2. Review test cases for usage examples
3. Examine service code for integration patterns
4. Check fuzz tests for invariant properties
