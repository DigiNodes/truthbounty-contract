# Deployment, Release & Migration Guide

## Overview

This document defines the canonical deployment, release, and migration process for TruthBounty Protocol V2. Every deployment is deterministic, reproducible, and verifiable.

## Architecture

```
Deployment Pipeline
├── Foundry Scripts        — Deterministic contract deployment
├── Environment Configs    — Per-environment parameters
├── MigrationManager       — On-chain version & migration registry
├── Release Manifest       — Machine-readable deployment artifact
└── CD Pipeline            — GitHub Actions automation
```

## Environment Configuration

Three environments are supported:

| Environment | Chain ID | RPC | Use |
|-------------|----------|-----|-----|
| `local` | 31337 | `anvil` | Development & testing |
| `testnet` | 11155420 | Optimism Sepolia | Staging & integration |
| `mainnet` | 10 | Optimism Mainnet | Production |

Configuration files are in `deployments/config/<env>.json`. Values are overridable via environment variables.

## Deployment Order

```
1. GovernanceController       — DAO governance
2. MigrationManager           — Version & migration registry
3. TruthBountyToken           — ERC20 bounty token
4. ReputationOracle           — IReputationOracle implementation
5. Staking                    — Lock-duration staking
6. TruthBountyWeighted        — Claims, voting, settlement (canonical)
7. VerifierSlashing           — Admin-initiated slashing
8. TruthBountyClaims          — Treasury batch payouts
```

## Deployment Scripts

### Local (Anvil)

```bash
# Start anvil
anvil

# Deploy
forge script script/deploy/Deploy.s.sol:Deploy \
    --sig "run(string)" "local" \
    --rpc-url http://127.0.0.1:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast

# Verify
forge script script/deploy/Verify.s.sol:Verify \
    --sig "verifyDeployment(address,address,address,address,address,address)" \
    --rpc-url http://127.0.0.1:8545
```

### Testnet

```bash
export DEPLOY_ENV=testnet
export ADMIN_ADDRESS=0x...
export OPTIMISM_SEPOLIA_RPC_URL=https://...

forge script script/deploy/Deploy.s.sol:Deploy \
    --sig "run(string)" "testnet" \
    --rpc-url $OPTIMISM_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

### Mainnet

```bash
export DEPLOY_ENV=mainnet
export ADMIN_ADDRESS=0x...
export OPTIMISM_MAINNET_RPC_URL=https://...
export RELEASE_VERSION=2.0.0

forge script script/deploy/Deploy.s.sol:Deploy \
    --sig "run(string)" "mainnet" \
    --rpc-url $OPTIMISM_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

## Release Manifest

After deployment, a manifest is generated at `deployments/<env>/manifest.json`:

```json
{
  "protocolVersion": "2.0.0",
  "environment": "testnet",
  "deployTimestamp": 1743200000,
  "chainId": 11155420,
  "gitCommit": "a1b2c3d4e5f6...",
  "contracts": {
    "MigrationManager": "0x...",
    "TruthBountyToken": "0x...",
    "ReputationOracle": "0x...",
    "TruthBountyWeighted": "0x...",
    "Staking": "0x...",
    "VerifierSlashing": "0x...",
    "TruthBountyClaims": "0x..."
  }
}
```

## Contract Address Registry

The `MigrationManager` contract stores a canonical on-chain address registry accessible via:

- `getModuleAddress(bytes32 moduleId)` — Single module lookup
- `getAllRegisteredModules()` — Full registry dump
- `isModuleRegistered(bytes32 moduleId)` — Existence check

## Ownership Verification

Post-deployment ownership verification checks:

1. **Token owner** — `TruthBountyToken` admin owns `DEFAULT_ADMIN_ROLE`
2. **Bounty governance** — `TruthBountyWeighted` has `GOVERNANCE_ROLE` granted to `GovernanceController`
3. **Staking configuration** — `Staking` contract has correct token reference
4. **Claims configuration** — `TruthBountyClaims` has correct token reference
5. **Oracle integration** — `TruthBountyWeighted` has correct oracle reference

Run the verification script:

```bash
forge script script/deploy/Verify.s.sol:Verify \
    --sig "verifyDeployment(address,address,address,address,address,address)" \
    <migration_manager> <token> <oracle> <bounty> <staking> <claims>
```

## Migration Framework

### Creating a Release

```solidity
migrationManager.createRelease("2.1.0", 0xabc...);
```

### Registering Modules

```solidity
migrationManager.registerModuleInRegistry(keccak256("TRUTH_BOUNTY"), address(0x...));
```

### Executing a Migration

```solidity
migrationManager.executeMigration(
    "Upgrade TruthBountyWeighted to v2.1.0",
    keccak256(abi.encode(block.timestamp, "upgrade-bounty"))
);
```

### Upgrading a Module Address

```solidity
migrationManager.updateModuleAddress(
    keccak256("TRUTH_BOUNTY"),
    address(newBountyImplementation)
);
```

### Verifying Deployment

```solidity
migrationManager.verifyDeployment(true, true);
```

## CI/CD Pipeline

The CD pipeline is triggered via `workflow_dispatch`:

```yaml
# .github/workflows/deploy.yml
# Inputs: environment (local|testnet|mainnet), release_version
```

### Pipeline Steps

1. **Checkout** — Full git history for commit SHA
2. **Build** — `forge build`
3. **Deploy** — `forge script Deploy.s.sol --broadcast`
4. **Verify** — `forge script Verify.s.sol` — validates all contract references
5. **Upload artifacts** — Manifest + registry saved as CI artifacts (90-day retention)
6. **Tag release** — On mainnet, creates `vX.Y.Z` git tag
7. **Etherscan verification** — Auto-verifies all deployed contracts

## Release Procedure

### Standard Release

```bash
# 1. Create release branch
git checkout -b release/v2.1.0 main

# 2. Deploy to testnet
gh workflow run deploy.yml -f environment=testnet -f release_version=2.1.0

# 3. Verify testnet deployment
# Review manifest, run integration tests

# 4. Deploy to mainnet
gh workflow run deploy.yml -f environment=mainnet -f release_version=2.1.0

# 5. Merge release branch
git checkout main && git merge release/v2.1.0
git tag v2.1.0 && git push origin v2.1.0
```

### Emergency Release

```bash
# Fast-track: skip testnet, deploy directly to mainnet
gh workflow run deploy.yml -f environment=mainnet -f release_version=2.1.1
```

## Rollback Procedure

If a deployment fails verification:

1. **Do not finalize** — Do not call `MigrationManager.verifyDeployment(true, true)`
2. **Deploy previous version** — Use the previous release's manifest to redeploy
3. **Update registry** — Call `updateModuleAddress()` on MigrationManager with old addresses
4. **Document** — Record the rollback as a migration entry

## Security Considerations

- **Private keys** must never be stored in repositories. Always use GitHub Secrets or hardware wallets
- **Environment separation** — Mainnet deployments require manual `workflow_dispatch` trigger; CI never auto-deploys to mainnet
- **Ownership verification** — The Verify script must pass before a deployment is considered complete
- **Release artifacts** — Every manifest includes a `gitCommit` field for audit trail

## Gas Benchmarks

| Operation | Gas (estimated) |
|-----------|----------------|
| `MigrationManager` deployment | ~800,000 |
| `createRelease()` | ~45,000 |
| `registerModuleInRegistry()` | ~55,000 |
| `updateModuleAddress()` | ~35,000 |
| `executeMigration()` | ~50,000 |
| `verifyDeployment()` | ~25,000 |