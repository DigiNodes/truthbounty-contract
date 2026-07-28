# Protocol Bootstrap & Deployment Guide

## Overview

The `BootstrapController` provides a deterministic, verifiable, and repeatable initialization process for every TruthBounty protocol deployment. It enforces dependency ordering, validates all configuration, and permanently records the deployment state.

## Architecture

```
BootstrapController
├── Module Registry          — 11 canonical protocol modules
├── Dependency Validation   — Cross-checks module addresses
├── Configuration Validation — Checks all parameter bounds
├── Initialization Sequence — Deterministic module ordering
└── Bootstrap State         — Permanent deployment record
```

## Module Registry

| Module ID | keccak256 | Description |
|-----------|-----------|-------------|
| `GOVERNANCE` | `keccak256("GOVERNANCE")` | GovernanceController |
| `TOKEN` | `keccak256("TOKEN")` | ERC20 bounty token |
| `REPUTATION_ORACLE` | `keccak256("REPUTATION_ORACLE")` | IReputationOracle impl |
| `STAKING` | `keccak256("STAKING")` | Lock-duration Staking |
| `REPUTATION_DECAY` | `keccak256("REPUTATION_DECAY")` | ReputationDecay |
| `REPUTATION_SNAPSHOT` | `keccak256("REPUTATION_SNAPSHOT")` | ReputationSnapshot |
| `WEIGHTED_STAKING` | `keccak256("WEIGHTED_STAKING")` | WeightedStaking |
| `TRUTH_BOUNTY` | `keccak256("TRUTH_BOUNTY")` | TruthBountyWeighted |
| `VERIFIER_SLASHING` | `keccak256("VERIFIER_SLASHING")` | VerifierSlashing |
| `CLAIMS` | `keccak256("CLAIMS")` | TruthBountyClaims |
| `REPUTATION_RECEIVER` | `keccak256("REPUTATION_RECEIVER")` | ReputationReceiver |

## Initialization Order

Modules are initialized in strict dependency order:

```
1. GOVERNANCE          — No dependencies
2. TOKEN               — No dependencies
3. REPUTATION_ORACLE   — No dependencies
4. STAKING             — Depends on TOKEN
5. REPUTATION_DECAY    — No dependencies
6. REPUTATION_SNAPSHOT — No dependencies
7. WEIGHTED_STAKING    — Depends on REPUTATION_ORACLE
8. TRUTH_BOUNTY        — Depends on TOKEN, REPUTATION_ORACLE
9. VERIFIER_SLASHING   — Depends on STAKING (wired during bootstrap)
10. CLAIMS             — Depends on TOKEN
11. REPUTATION_RECEIVER — Depends on REPUTATION_ORACLE
```

## Dependency Validation

Before bootstrap completes, the controller verifies:

1. **All modules registered** — every standard module ID must have a non-zero address
2. **On-chain address consistency** — calls `bountyToken()` on TRUTH_BOUNTY, `reputationOracle()` on TRUTH_BOUNTY and WEIGHTED_STAKING, `stakingToken()` on STAKING, `bountyToken()` on CLAIMS, and verifies each matches the registered module address
3. **Governance role** — the GOVERNANCE module address must have GOVERNANCE_ROLE or DEFAULT_ADMIN_ROLE on TRUTH_BOUNTY

## Configuration Validation

The `BootstrapConfig` struct is validated against these bounds:

| Parameter | Valid Range | Default |
|-----------|-------------|---------|
| `verificationWindowDuration` | 1–30 days | 7 days |
| `minStakeAmount` | > 0 | 100e18 |
| `settlementThresholdPercent` | 1–100 | 60 |
| `rewardPercent` | 1–100 | 80 |
| `slashPercent` | 1–100 | 20 |
| `confirmationDelay` | any uint256 | 1 hour |
| `minReputationScore` | > 0, < max | 0.1e18 |
| `maxReputationScore` | > min | 10e18 |
| `defaultReputationScore` | > 0 | 1e18 |
| `stakingLockDuration` | ≥ 1 hour | 86400 |

Violations emit `BootstrapValidationFailed` events. The bootstrap does not revert on config validation failures — all violations are surfaced via events for off-chain inspection.

## Hardhat Ignition Deployment

```typescript
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const BootstrapModule = buildModule("BootstrapModule", (m) => {
  // 1. Deploy GovernanceController
  const governance = m.contract("GovernanceController", [admin]);

  // 2. Deploy BootstrapController
  const bootstrap = m.contract("BootstrapController", [admin, governance]);

  // 3. Deploy protocol modules
  const token = m.contract("TruthBountyToken", [admin]);
  const oracle = m.contract("MockReputationOracle", []);
  const staking = m.contract("Staking", [token, lockDuration, admin]);
  const reputationDecay = m.contract("ReputationDecay", [admin]);
  const reputationSnapshot = m.contract("ReputationSnapshot", [admin]);
  const weightedStaking = m.contract("WeightedStaking", [oracle, admin, governance]);
  const truthBounty = m.contract("TruthBountyWeighted", [token, oracle, admin, governance]);
  const slashing = m.contract("VerifierSlashing", [staking, admin, governance]);
  const claims = m.contract("TruthBountyClaims", [token, admin]);

  // 4. Register all modules
  m.call(bootstrap, "registerModules", [
    [keccak256("GOVERNANCE"), keccak256("TOKEN"), ...],
    [governance, token, ...],
    ["Governance", "Token", ...]
  ], { id: "register_modules" });

  // 5. Set configuration
  m.call(bootstrap, "setBootstrapConfig", [{
    verificationWindowDuration: 7 * 86400,
    minStakeAmount: ethers.parseEther("100"),
    // ...
  }], { id: "set_config" });

  // 6. Execute bootstrap
  m.call(bootstrap, "bootstrap", [], { id: "execute_bootstrap" });

  return { bootstrap, token, truthBounty, /* ... */ };
});
```

## Script-Based Deployment

```typescript
import { ethers } from "hardhat";

async function main() {
  const [admin] = await ethers.getSigners();

  // 1. Deploy modules
  const Governance = await ethers.getContractFactory("GovernanceController");
  const governance = await Governance.deploy(admin.address);

  const TruthBountyToken = await ethers.getContractFactory("TruthBountyToken");
  const token = await TruthBountyToken.deploy(admin.address);

  // ... deploy remaining modules ...

  // 2. Deploy BootstrapController
  const BootstrapController = await ethers.getContractFactory("BootstrapController");
  const controller = await BootstrapController.deploy(admin.address, governance.target);
  await controller.waitForDeployment();

  // 3. Grant DEPLOYER_ROLE
  await controller.grantRole(await controller.DEPLOYER_ROLE(), admin.address);

  // 4. Register modules
  await controller.registerModules(
    [ethers.id("GOVERNANCE"), ethers.id("TOKEN"), /* ... */],
    [governance.target, token.target, /* ... */],
    ["Governance", "Token", /* ... */]
  );

  // 5. Set configuration
  await controller.setBootstrapConfig({
    verificationWindowDuration: 7 * 86400,
    minStakeAmount: ethers.parseEther("100"),
    settlementThresholdPercent: 60,
    rewardPercent: 80,
    slashPercent: 20,
    confirmationDelay: 3600,
    minReputationScore: ethers.parseEther("0.1"),
    maxReputationScore: ethers.parseEther("10"),
    defaultReputationScore: ethers.parseEther("1"),
    stakingLockDuration: 86400,
  });

  // 6. Bootstrap
  await controller.bootstrap();

  // 7. Verify
  const state = await controller.getBootstrapState();
  console.log(`Bootstrapped at block ${state.blockNumber}, version ${state.version}`);
}
```

## Post-Deployment Verification

After bootstrap completes, verify:

```typescript
const state = await controller.getBootstrapState();
assert(state.bootstrapped === true);
assert(state.version === "2.0.0");

const fullyInitialized = await controller.isFullyInitialized();
assert(fullyInitialized === true);

// Check each module
for (const id of allModuleIds) {
  const info = await controller.getModuleInfo(id);
  assert(info.registered === true);
  assert(info.initialized === true);
}
```

## Events

| Event | When | Data |
|-------|------|------|
| `ProtocolBootstrapStarted` | Start of `bootstrap()` | — |
| `ModuleRegistered` | Module added to registry | moduleId, address, name |
| `ModuleInitialized` | Module processed during bootstrap | moduleId, address |
| `ProtocolBootstrapCompleted` | Bootstrap finishes successfully | version string |
| `BootstrapValidationFailed` | Config validation violation | bytes32 reason |

## Gas Benchmarks (estimated)

| Operation | Gas |
|-----------|-----|
| `registerModule` (single) | ~45,000 |
| `registerModules` (11 modules) | ~350,000 |
| `setBootstrapConfig` | ~35,000 |
| `bootstrap` (11 modules) | ~120,000 |
| `getModuleAt` (view) | ~8,000 |
| `getAllModules` (view) | ~25,000 |

*Actual gas costs will vary by network and configuration.*

## Security Considerations

- **One-shot bootstrap**: `bootstrap()` reverts with `AlreadyBootstrapped` on second call
- **Access control**: Only `DEPLOYER_ROLE` can register modules, set config, or execute bootstrap. `ADMIN_ROLE` manages deployer role grants
- **Zero-address rejection**: All module addresses are validated to be non-zero
- **Duplicate rejection**: Each module ID can only be registered once
- **Dependency enforcement**: Bootstrap reverts if any standard module is missing from the registry
- **On-chain verification**: Module addresses are cross-checked against the live contract state during dependency validation