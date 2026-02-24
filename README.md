# 📜 TruthBounty Smart Contracts

**On-chain Incentives & Verification Logic**  
*Smart contracts powering decentralized truth verification across Ethereum and Stellar*

![License](https://img.shields.io/badge/license-MIT-green)
![Solidity](https://img.shields.io/badge/solidity-%5E0.8.x-blue)
![Status](https://img.shields.io/badge/status-active%20development-blue)

---

## 🌍 Overview

This repository contains the **smart contracts** that power TruthBounty’s decentralized verification and incentive mechanisms.

The contracts handle:
- Verifier staking
- Reward distribution
- Reputation-weighted participation
- Transparent, auditable verification outcomes

TruthBounty contracts are designed as **public-good primitives**, enabling trust-minimized fact verification at scale.

---

## 🌱 Ecosystem Alignment

TruthBounty contracts are aligned with:

- **Ethereum** – secure, neutral settlement layer  
- **Optimism** – low-cost reward distribution  
- **Stellar (planned)** – micro-rewards & global accessibility  
- **Public Goods Funding** – long-term sustainability via Drips  

Contracts are intentionally modular to support **multi-chain deployments**.

---

## 🔗 Contract Responsibilities

### Core Modules

- **Verifier Staking**
  - Users stake tokens to participate in verification
  - Stake size influences verification weight

- **Reward Distribution**
  - ERC-20 rewards issued based on consensus outcomes
  - Slashing for malicious or incorrect verification

- **Reputation Hooks**
  - Reputation updates triggered by verification results
  - Designed to integrate with off-chain scoring engines

---

## 🌟 Stellar Compatibility (Planned)

TruthBounty smart contracts are designed with **Soroban compatibility** in mind.

### Planned Integrations
- Soroban-based reward settlement
- Stellar-native verifier incentives
- Cross-chain verification proofs (Ethereum ↔ Stellar)
- Low-fee micro-rewards for emerging markets

TruthBounty treats smart contracts as **portable logic**, not ecosystem lock-in.

---

## ⚙️ Tech Stack

| Technology | Purpose |
|---------|--------|
| Solidity | Ethereum smart contracts |
| Optimism | L2 deployment |
| Hardhat / Foundry | Development & testing |
| Ethers.js | Contract interaction |
| Soroban (planned) | Stellar smart contracts |

---

## 🛠️ Development Setup

## 🛠️ Development Setup

### Environment Variables

Copy `.env.example` to `.env` and fill in the required values:

```
PRIVATE_KEY=your_private_key_here
OPTIMISM_SEPOLIA_RPC_URL=https://sepolia.optimism.io
OPTIMISM_SEPOLIA_GAS_PRICE=10000000
OPTIMISM_MAINNET_RPC_URL=https://mainnet.optimism.io
OPTIMISM_MAINNET_GAS_PRICE=10000000
OPTIMISM_ETHERSCAN_API_KEY=your_optimism_etherscan_api_key
```

**Notes:**
- Never commit your real private key.
- Gas price can be omitted for auto, or set for custom deployments.
- Use the correct RPC endpoints for your provider (Infura, Alchemy, etc).


### Prerequisites

- Node.js v18+
- npm or yarn
- Git

---

### Installation

```bash
git clone https://github.com/DigiNodes/truthbounty-contracts.git
cd truthbounty-contracts

npm install

```

## 👥 Contributing

We welcome:

- Smart contract engineers
- Security researchers
- Auditors
- Protocol designers

Please follow Conventional Commits and submit clear PRs.
